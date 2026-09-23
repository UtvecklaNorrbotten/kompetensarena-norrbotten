# Gemensam klient för Kompetensarenas ETL-endpoints.
# Används av GitHub Actions och R-skript. Hemligheter läses endast från miljön.

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})

# Samma gräns finns i API-valideringen och databasens check constraint.
ETL_MAX_CHUNKS <- 2000L

etl_base_url <- function() {
  x <- Sys.getenv("ETL_BASE_URL", unset = "")
  if (!nzchar(x)) stop("ETL_BASE_URL saknas")
  sub("/+$", "", x)
}

etl_key <- function() {
  x <- Sys.getenv("ETL_PUBLISH_KEY", unset = "")
  if (!nzchar(x)) stop("ETL_PUBLISH_KEY saknas")
  x
}

etl_request <- function(path) {
  request(paste0(etl_base_url(), path)) |>
    req_auth_bearer_token(etl_key()) |>
    req_headers("Accept" = "application/json")
}

etl_perform_json <- function(req, retry_safe = FALSE) {
  # Start/no-change kan skapa nya poster och får inte upprepas automatiskt
  # efter ett tappat svar. Chunk/finalize/abort och läsning tål återförsök.
  if (retry_safe) {
    req <- req |>
      req_retry(
        max_tries = 5,
        retry_on_failure = TRUE,
        is_transient = function(resp) resp_status(resp) %in% c(429L, 502L, 503L, 504L)
      )
  }

  resp <- req |>
    req_timeout(60) |>
    req_error(is_error = function(resp) FALSE) |>
    req_perform()

  status <- resp_status(resp)
  body <- tryCatch(
    resp_body_json(resp, simplifyVector = TRUE),
    error = function(e) list(error = resp_body_string(resp))
  )

  if (status < 200 || status >= 300) {
    msg <- body$message %||% body$error %||% paste("HTTP", status)
    stop(sprintf("ETL-anrop misslyckades (%s): %s", status, msg), call. = FALSE)
  }

  body
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

etl_get_state <- function(indicator_id) {
  etl_request("/api/public/jobs/etl-state") |>
    req_url_query(indicator_id = indicator_id) |>
    etl_perform_json(retry_safe = TRUE)
}

etl_log_no_change <- function(indicator_id, source) {
  etl_request("/api/public/jobs/etl-no-change") |>
    req_method("POST") |>
    req_body_json(list(indicator_id = indicator_id, source = source), auto_unbox = TRUE) |>
    etl_perform_json()
}

etl_split_observations <- function(observations, max_rows = 5000L, max_bytes = 5000000L) {
  stopifnot(is.list(observations))
  if (length(observations) == 0) return(list())

  rough <- split(observations, ceiling(seq_along(observations) / max_rows))
  out <- list()

  split_if_needed <- function(chunk) {
    payload_size <- nchar(
      toJSON(chunk, auto_unbox = TRUE, null = "null", na = "null", digits = NA),
      type = "bytes"
    )
    if (payload_size <= max_bytes) return(list(chunk))
    if (length(chunk) <= 1) stop("En enskild observation överskrider chunkgränsen")
    mid <- floor(length(chunk) / 2)
    c(split_if_needed(chunk[seq_len(mid)]), split_if_needed(chunk[(mid + 1):length(chunk)]))
  }

  for (chunk in rough) out <- c(out, split_if_needed(unname(chunk)))
  out
}

etl_start_batch <- function(indicator_id, source, source_updated_date, expected_chunks, expected_rows) {
  start_body <- list(
    indicator_id = indicator_id,
    source = source,
    expected_chunks = expected_chunks,
    expected_rows = expected_rows
  )
  if (!is.null(source_updated_date) && !is.na(source_updated_date) && nzchar(source_updated_date)) {
    start_body$kalla_uppdaterad_datum <- source_updated_date
  }

  start <- etl_request("/api/public/jobs/etl-batch/start") |>
    req_method("POST") |>
    req_body_json(start_body, auto_unbox = TRUE, null = "null") |>
    etl_perform_json()

  if (is.null(start$batch_id) || !nzchar(start$batch_id)) {
    stop("Batch-start returnerade inget batch_id")
  }

  start
}

etl_chunk_payload_json <- function(batch_id, indicator_id, chunk_index, observations) {
  as.character(toJSON(
    list(
      batch_id = batch_id,
      indicator_id = indicator_id,
      chunk_index = chunk_index,
      observations = observations
    ),
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA
  ))
}

etl_chunk_request <- function(payload_json) {
  etl_request("/api/public/jobs/etl-batch/chunk") |>
    req_method("POST") |>
    req_body_raw(payload_json, type = "application/json") |>
    req_timeout(180) |>
    req_retry(
      max_tries = 5,
      retry_on_failure = TRUE,
      is_transient = function(resp) resp_status(resp) %in% c(429L, 502L, 503L, 504L)
    ) |>
    req_error(is_error = function(resp) FALSE)
}

etl_check_chunk_response <- function(resp, chunk_index) {
  if (inherits(resp, "error") || inherits(resp, "condition")) {
    stop(sprintf("Chunk %d misslyckades: %s", chunk_index + 1L, conditionMessage(resp)), call. = FALSE)
  }

  status <- resp_status(resp)
  body <- tryCatch(
    resp_body_json(resp, simplifyVector = TRUE),
    error = function(e) list(error = resp_body_string(resp))
  )

  if (status < 200 || status >= 300) {
    msg <- body$message %||% body$error %||% paste("HTTP", status)
    stop(sprintf("Chunk %d misslyckades (%s): %s", chunk_index + 1L, status, msg), call. = FALSE)
  }

  body
}

etl_publish_batch_chunk <- function(batch_id, indicator_id, chunk_index, observations) {
  json_started <- proc.time()[["elapsed"]]
  # Koda en gång före HTTP-anropet: ger separat tidsmätning och samma
  # färdiga payload vid varje återförsök.
  payload_json <- etl_chunk_payload_json(batch_id, indicator_id, chunk_index, observations)
  json_seconds <- proc.time()[["elapsed"]] - json_started
  request_started <- proc.time()[["elapsed"]]
  on.exit(message(sprintf(
    "Chunk %d: JSON %.2f s; HTTP inkl. återförsök %.2f s",
    chunk_index + 1L, json_seconds, proc.time()[["elapsed"]] - request_started
  )), add = TRUE)
  result <- etl_check_chunk_response(
    req_perform(etl_chunk_request(payload_json)),
    chunk_index
  )
  if (!is.null(result$rpc_ms)) {
    message(sprintf("Chunk %d: serverns senaste databas-RPC %.0f ms", chunk_index + 1L, result$rpc_ms))
  }
  result
}



etl_finalize_batch <- function(batch_id) {
  etl_request("/api/public/jobs/etl-batch/finalize") |>
    req_method("POST") |>
    req_body_json(list(batch_id = batch_id), auto_unbox = TRUE) |>
    etl_perform_json(retry_safe = TRUE)
}

etl_abort_batch <- function(batch_id, reason = "R-jobbet avbröts före lyckad finalisering") {
  etl_request("/api/public/jobs/etl-batch/abort") |>
    req_method("POST") |>
    req_body_json(list(batch_id = batch_id, reason = reason), auto_unbox = TRUE) |>
    etl_perform_json(retry_safe = TRUE)
}

etl_publish_batch <- function(indicator_id, source, source_updated_date, observations) {
  chunks <- etl_split_observations(observations)
  if (length(chunks) == 0) stop("Inga observationer att publicera")
  if (length(chunks) > ETL_MAX_CHUNKS) {
    stop(sprintf(
      "Importen kräver %d chunkar; gränsen är %d",
      length(chunks), ETL_MAX_CHUNKS
    ))
  }

  start <- etl_start_batch(
    indicator_id = indicator_id,
    source = source,
    source_updated_date = source_updated_date,
    expected_chunks = length(chunks),
    expected_rows = length(observations)
  )
  batch_id <- start$batch_id

  ok <- FALSE
  on.exit({
    if (!ok) try(etl_abort_batch(batch_id), silent = TRUE)
  }, add = TRUE)

  for (i in seq_along(chunks)) {
    etl_publish_batch_chunk(
      batch_id = batch_id,
      indicator_id = indicator_id,
      chunk_index = i - 1L,
      observations = chunks[[i]]
    )
    message(sprintf("Publicerade chunk %d/%d", i, length(chunks)))
  }

  result <- etl_finalize_batch(batch_id)
  ok <- TRUE
  result
}
