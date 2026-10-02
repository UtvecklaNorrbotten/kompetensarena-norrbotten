# SCB AFR – synk av juridiska enheter (JE) och arbetsställen (AE).
#
# Lägen (AFR_MODE):
#   count-only       api-info + count + kodtabeller; loggar volym och uppskattningar. Inget importeras.
#   initial-load     första fullständiga laddningen (chunkad, återupptagbar, atomiskt finaliserad).
#   daily            daglig kontroll: oförändrat källdatum -> no_change; annars full traversering + delta.
#   cleanup-initial  städar en misslyckad första laddning stegvis.
#
# Säkerhetsregler:
#   - bortfall skickas aldrig om traverseringen inte avslutats med hasMore = FALSE,
#     unikt antal == count, och count före == count efter.
#   - databasen gör egen balans- och bortfallskontroll före finalisering.

source("R/etl/etl_api.R")
source("R/etl/afr_client.R")
source("R/etl/afr_normalize.R")

AFR_SOURCE_ID <- "scb-afr"
AFR_REMOVED_PER_CHUNK <- 50000L
AFR_HASH_PAGE <- 50000L

afr_mode <- Sys.getenv("AFR_MODE", unset = "daily")
afr_confirm_removal <- tolower(Sys.getenv("AFR_CONFIRM_LARGE_REMOVAL", unset = "false")) == "true"
started <- Sys.time()

afr_post <- function(path, body, retry_safe = TRUE, timeout = 300) {
  payload <- toJSON(body, auto_unbox = TRUE, na = "null", null = "null", digits = NA)
  if (nchar(payload, type = "bytes") > 5800000) stop("Chunk för stor: ", nchar(payload, type = "bytes"), " byte")
  etl_request(path) |>
    req_method("POST") |>
    req_body_raw(payload, type = "application/json") |>
    etl_perform_json(retry_safe = retry_safe, timeout = timeout)
}

afr_log_check <- function(status, source_date = NULL, details = list(), error_message = NULL) {
  body <- list(status = status, details = details)
  if (!is.null(source_date)) body$source_date <- source_date
  if (!is.null(error_message)) body$error_message <- substr(error_message, 1, 1000)
  try(afr_post("/api/public/jobs/afr/check", body), silent = TRUE)
}

afr_fetch_hashes <- function(entity) {
  keys <- list(); hashes <- list(); after <- NULL
  repeat {
    req <- etl_request("/api/public/jobs/afr/hashes") |>
      req_url_query(entity = entity, limit = AFR_HASH_PAGE)
    if (!is.null(after)) req <- req |> req_url_query(after = after)
    page <- etl_perform_json(req, retry_safe = TRUE)
    items <- page$items
    if (length(items)) {
      keys[[length(keys) + 1L]] <- as.character(items[, 1])
      hashes[[length(hashes) + 1L]] <- as.character(items[, 2])
    }
    if (!isTRUE(page$has_more)) break
    after <- page$next_after
  }
  list(key = unlist(keys, use.names = FALSE), hash = unlist(hashes, use.names = FALSE))
}

afr_sort <- function(df, entity) {
  o <- if (entity == "ae") order(as.numeric(df$key)) else order(df$key, method = "radix")
  df[o, , drop = FALSE]
}

afr_build_chunks <- function(df, removed) {
  chunks <- list()
  n <- nrow(df)
  if (n > 0) for (s in seq(1L, n, by = AFR_PAGE_LIMIT)) {
    chunks[[length(chunks) + 1L]] <- list(rows = s:min(n, s + AFR_PAGE_LIMIT - 1L), removed = character())
  }
  if (length(removed)) for (s in seq(1L, length(removed), by = AFR_REMOVED_PER_CHUNK)) {
    chunks[[length(chunks) + 1L]] <- list(rows = integer(), removed = removed[s:min(length(removed), s + AFR_REMOVED_PER_CHUNK - 1L)])
  }
  chunks
}

afr_send_chunks <- function(sync_id, entity, df, chunks, skip = 0L) {
  # Chunkar skickas i ordning; de första `skip` finns redan i databasen.
  if (skip > 0) message(sprintf("%s: hoppar över %d redan mottagna chunkar", entity, skip))
  for (i in seq_along(chunks)) {
    if (i <= skip) next
    ch <- chunks[[i]]
    recs <- df[ch$rows, , drop = FALSE]
    rownames(recs) <- NULL
    afr_post("/api/public/jobs/afr/chunk", list(
      sync_id = sync_id, entity = entity, chunk_index = i - 1L,
      records = recs, removed = I(ch$removed)
    ))
    if (i %% 20 == 0) message(sprintf("%s: %d/%d chunkar skickade", entity, i, length(chunks)))
  }
}

afr_fetch_entity <- function(entity, count_before) {
  norm <- if (entity == "je") afr_normalize_je_page else afr_normalize_ae_page
  tr <- afr_traverse(entity, norm)
  df <- afr_combine_pages(tr$pages)
  if (anyNA(df$key)) stop(entity, ": poster utan nyckel i AFR-uttaget")
  unique_n <- length(unique(df$key))
  if (unique_n != nrow(df)) stop(sprintf("%s: %d dubbletter i uttaget", entity, nrow(df) - unique_n))
  if (!isTRUE(tr$has_more_false)) stop(entity, ": traverseringen nådde inte hasMore = FALSE")
  if (unique_n != count_before) {
    stop(sprintf("%s: observerat %d unika men count är %d – ofullständigt uttag", entity, unique_n, count_before))
  }
  df$hash <- if (entity == "je") afr_hash_je(df) else afr_hash_ae(df)
  list(df = afr_sort(df, entity), pages = tr$page_count, unique = unique_n)
}

afr_rebuild_indexes <- function() {
  repeat {
    r <- afr_post("/api/public/jobs/afr/maintenance", list(action = "rebuild_indexes"))
    if (!is.null(r$built)) message(sprintf("Byggde %s (%d ms), %d kvar", r$built, as.integer(r$ms), as.integer(r$remaining)))
    if (isTRUE(r$done)) break
    if (is.null(r$built)) stop("Index/kopplingar kunde inte byggas: ", r$remaining, " kvar")
  }
}

afr_backfill_primary_sni <- function() {
  from <- 0L
  repeat {
    r <- afr_post("/api/public/jobs/afr/maintenance", list(action = "backfill_primary_sni", from_page = from, pages = 1000L))
    from <- as.integer(r$next_page)
    if (isTRUE(r$done)) break
  }
  message("primary_sni ifylld")
}

sync_id <- NULL
source_date <- NULL

result <- tryCatch({
  if (afr_mode == "cleanup-initial") {
    open <- etl_request("/api/public/jobs/afr/resume") |> etl_perform_json(retry_safe = TRUE)
    if (is.null(open) || length(open) == 0) { message("Ingen ofullbordad första laddning att städa."); quit(status = 0) }
    if (open$status == "receiving") {
      afr_post("/api/public/jobs/afr/abort", list(sync_id = open$id, reason = "Städas manuellt"))
    }
    repeat {
      r <- afr_post("/api/public/jobs/afr/cleanup", list(sync_id = open$id, max_rows = 20000L))
      message(sprintf("Städade %d rader", r$deleted_rows))
      if (!isTRUE(r$remaining)) break
    }
    message("Städning klar.")
    quit(status = 0)
  }

  info <- afr_api_info()
  source_date <- as.character(info$senasteUppdateringsDatum)
  message("AFR källdatum: ", source_date, " (", info$apiNamn %||% "", ")")

  state <- etl_get_source_state(AFR_SOURCE_ID)
  last_ok <- state$state$latest_successful_period %||% NA_character_

  if (afr_mode == "daily" && identical(as.character(last_ok), source_date)) {
    message("Källdatum oförändrat – ingen synk.")
    afr_log_check("no_change", source_date, list(
      api_name = info$apiNamn, source_date = source_date, last_successful = last_ok,
      requests = afr_stats$requests
    ))
    quit(status = 0)
  }

  je_count <- afr_count("je")
  ae_count <- afr_count("ae")
  message(sprintf("JE-count %d, AE-count %d", je_count, ae_count))

  code_tables <- afr_fetch_code_tables()
  code_result <- afr_post("/api/public/jobs/afr/codes", list(tables = code_tables))
  code_changes <- code_result$tables

  if (afr_mode == "count-only") {
    je_pages <- ceiling(je_count / AFR_PAGE_LIMIT)
    ae_pages <- ceiling(ae_count / AFR_PAGE_LIMIT)
    details <- list(
      api_name = info$apiNamn, api_version = AFR_API_VERSION, source_date = source_date,
      je_count = je_count, ae_count = ae_count,
      je_pages = je_pages, ae_pages = ae_pages, page_limit = AFR_PAGE_LIMIT,
      estimated_api_calls_full_sync = je_pages + ae_pages + 3L + length(AFR_CODE_TABLES),
      estimated_initial_import_mb = round((je_count * 450 + ae_count * 550) / 1e6),
      estimated_storage_mb = round((je_count + ae_count) * 1500 / 1e6),
      estimate_note = "Grov uppskattning: ~450/550 byte per JE/AE i import, ~1,5 kB per objekt lagrat inkl. historik, SNI och index.",
      code_tables = code_changes, requests = afr_stats$requests,
      retries = afr_stats$retries, http_429 = afr_stats$http_429,
      throttle = afr_throttle_summary()
    )
    print(str(details))
    afr_log_check("count_only", source_date, details)
    quit(status = 0)
  }

  if (!afr_mode %in% c("initial-load", "daily")) stop("Okänt AFR_MODE: ", afr_mode)

  je <- afr_fetch_entity("je", je_count)
  ae <- afr_fetch_entity("ae", ae_count)

  je_after <- afr_count("je"); ae_after <- afr_count("ae")
  if (je_after != je_count || ae_after != ae_count) {
    stop(sprintf("Källan ändrades under uttaget (JE %d→%d, AE %d→%d) – körs om senare", je_count, je_after, ae_count, ae_after))
  }
  info_after <- afr_api_info()
  if (!identical(as.character(info_after$senasteUppdateringsDatum), source_date)) {
    stop("Källdatum ändrades under uttaget – körs om senare")
  }

  base_stats <- list(
    api_name = info$apiNamn, je_pages = je$pages, ae_pages = ae$pages,
    je_count_before = je_count, je_count_after = je_after, ae_count_before = ae_count, ae_count_after = ae_after,
    je_observed = je$unique, ae_observed = ae$unique, code_tables = code_changes,
    throttle = afr_throttle_summary()
  )

  if (afr_mode == "initial-load") {
    je_chunks <- afr_build_chunks(je$df, character())
    ae_chunks <- afr_build_chunks(ae$df, character())

    open <- etl_request("/api/public/jobs/afr/resume") |> etl_perform_json(retry_safe = TRUE)
    if (!is.null(open) && length(open) > 0) {
      same <- identical(open$source_date, source_date) && open$je_source_count == je_count &&
        open$ae_source_count == ae_count && open$expected_je_chunks == length(je_chunks) &&
        open$expected_ae_chunks == length(ae_chunks)
      if (!same) stop("En ofullbordad första laddning finns från ett annat källdatum – kör cleanup-initial först")
      if (open$status == "failed") afr_post("/api/public/jobs/afr/resume", list(sync_id = open$id))
      sync_id <- open$id
      skip_je <- as.integer(open$received_je_chunks %||% 0L)
      skip_ae <- as.integer(open$received_ae_chunks %||% 0L)
      message("Återupptar första laddning ", sync_id)
    } else {
      start <- afr_post("/api/public/jobs/afr/start", list(
        mode = "initial", source_date = source_date, api_version = AFR_API_VERSION,
        fetched_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
        je_source_count = je_count, ae_source_count = ae_count,
        expected_je_chunks = length(je_chunks), expected_ae_chunks = length(ae_chunks),
        details = base_stats
      ), retry_safe = FALSE)
      sync_id <- start$sync_id
      skip_je <- 0L; skip_ae <- 0L
    }
    afr_send_chunks(sync_id, "je", je$df, je_chunks, skip_je)
    afr_send_chunks(sync_id, "ae", ae$df, ae_chunks, skip_ae)
    # Hjälpindex och kopplingar är pausade under första laddningen; databasen vägrar finalisera utan dem.
    afr_backfill_primary_sni()
    afr_rebuild_indexes()
  } else {
    afr_rebuild_indexes()
    old_je <- afr_fetch_hashes("je")
    old_ae <- afr_fetch_hashes("ae")

    delta <- function(df, old) {
      idx <- match(df$key, old$key)
      is_new <- is.na(idx)
      is_changed <- !is_new & old$hash[idx] != df$hash
      list(up = df[is_new | is_changed, , drop = FALSE], n_new = sum(is_new), n_changed = sum(is_changed),
           n_unchanged = sum(!is_new & !is_changed), removed = setdiff(old$key, df$key))
    }
    dj <- delta(je$df, old_je)
    da <- delta(ae$df, old_ae)
    message(sprintf("JE: %d nya, %d ändrade, %d bortfallna. AE: %d nya, %d ändrade, %d bortfallna.",
      dj$n_new, dj$n_changed, length(dj$removed), da$n_new, da$n_changed, length(da$removed)))

    je_chunks <- afr_build_chunks(dj$up, dj$removed)
    ae_chunks <- afr_build_chunks(da$up, da$removed)

    start <- afr_post("/api/public/jobs/afr/start", list(
      mode = "daily", source_date = source_date, api_version = AFR_API_VERSION,
      fetched_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      je_source_count = je_count, ae_source_count = ae_count,
      expected_je_chunks = length(je_chunks), expected_ae_chunks = length(ae_chunks),
      confirm_large_removal = afr_confirm_removal,
      details = c(base_stats, list(etl_je_new = dj$n_new, etl_je_changed = dj$n_changed, etl_je_removed = length(dj$removed),
        etl_ae_new = da$n_new, etl_ae_changed = da$n_changed, etl_ae_removed = length(da$removed)))
    ), retry_safe = FALSE)
    sync_id <- start$sync_id
    afr_send_chunks(sync_id, "je", dj$up, je_chunks)
    afr_send_chunks(sync_id, "ae", da$up, ae_chunks)
  }

  fin <- afr_post("/api/public/jobs/afr/finalize", list(sync_id = sync_id, stats = list(
    duration_seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs"))),
    afr_requests = afr_stats$requests, afr_retries = afr_stats$retries, afr_http_429 = afr_stats$http_429,
    afr_bytes = afr_stats$bytes
  )))
  message("AFR-synk publicerad: ", toJSON(fin$stats, auto_unbox = TRUE))
  "ok"
}, error = function(e) {
  msg <- conditionMessage(e)
  message("AFR-synk misslyckades: ", msg)
  if (!is.null(sync_id)) {
    # Första laddningen markeras som misslyckad men kan återupptas; daglig staging rensas.
    try(afr_post("/api/public/jobs/afr/abort", list(sync_id = sync_id, reason = substr(msg, 1, 900))), silent = TRUE)
  } else {
    afr_log_check("failed", source_date, list(mode = afr_mode, requests = afr_stats$requests,
      retries = afr_stats$retries, http_429 = afr_stats$http_429), msg)
  }
  "failed"
})

if (!identical(result, "ok")) quit(status = 1)
