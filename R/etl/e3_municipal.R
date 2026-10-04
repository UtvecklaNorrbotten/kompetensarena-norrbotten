# Kompetensarena Norrbotten – E3 för alla kommuner.
# Skapad 2026-10-04. Joe Lindehag / Region Norrbotten.
# Strömmar en SCB-del i taget; ofullständig data blir aldrig publik.

# ---- Plan och query ----

e3_municipal_plan <- function(regions, years, education, sni, contents, max_cells = 150000L) {
  cells_per_region <- length(sni) * length(contents)
  per_request <- floor(max_cells / cells_per_region)
  if (per_request < 1L) stop("En kommun överskrider SCB:s cellgräns")
  region_parts <- split(regions, ceiling(seq_along(regions) / per_request))
  parts <- list()
  next_index <- 0L
  for (year in years) {
    for (edu in education) {
      for (region_part in region_parts) {
        rows <- length(region_part) * cells_per_region
        chunks <- ceiling(rows / 5000L)
        parts[[length(parts) + 1L]] <- list(
          year = year, education = edu, regions = unname(region_part),
          rows = rows, chunks = chunks, first_chunk = next_index
        )
        next_index <- next_index + chunks
      }
    }
  }
  if (!length(parts)) stop("E3-urvalet är tomt")
  list(parts = parts, rows = sum(vapply(parts, function(x) x$rows, numeric(1))),
       chunks = next_index)
}

e3_municipal_query <- function(part, sni, contents) {
  list(selection = list(
    list(variableCode = "Region", valueCodes = as.list(part$regions), codelist = "vs_CKM03Kommun"),
    list(variableCode = "Tid", valueCodes = list(part$year)),
    list(variableCode = "Utbildning", valueCodes = list(part$education), codelist = "vs_UtbildningsgruppE2-3N1-2"),
    list(variableCode = "SNI2007", valueCodes = as.list(sni)),
    list(variableCode = "ContentsCode", valueCodes = as.list(contents)),
    # Obligatorisk SCB-variabel: ett enda totalvärde, ingen demografisk uppdelning.
    list(variableCode = "KonAlderFodelseland", valueCodes = list("totalt"), codelist = "vs_KonCKMRMI")
  ))
}

e3_municipal_normalize <- function(data, meta, part, sni, contents) {
  variables <- pxweb2_get_variables(meta)
  data <- scb_standardize_variable_names(data, variables)
  required <- c("ContentsCode", "Tid", "SNI2007", "Region", "Utbildning", "value")
  if (length(setdiff(required, names(data)))) stop("SCB-data saknar obligatoriska kolumner")
  region_col <- scb_find_code_column(data, "region")
  edu_col <- scb_find_code_column(data, "utbildning")
  code <- function(variable, values) {
    labels <- unlist(meta$dimension[[variable]]$category$label)
    values <- as.character(values)
    # pxweb2r kan exponera koder eller etiketter beroende på variabel.
    result <- values
    missing <- !values %in% names(labels)
    result[missing] <- names(labels)[match(values[missing], labels)]
    if (anyNA(result)) stop("Okända SCB-värden i ", variable)
    result
  }
  data$geo_code <- as.character(data[[region_col]])
  data$education_code <- as.character(data[[edu_col]])
  data$contents_code <- code("ContentsCode", data$ContentsCode)
  data$sni_code <- code("SNI2007", data$SNI2007)
  data$period <- as.character(data$Tid)
  data$value <- as.numeric(data$value)
  if (any(!is.na(data$value) & !is.finite(data$value))) stop("E3 innehåller icke-ändliga värden")
  if (nrow(data) != part$rows ||
      anyNA(data$geo_code) || anyNA(data$education_code) ||
      !all(data$geo_code %in% part$regions) ||
      !all(data$education_code == part$education) ||
      !all(data$period == part$year) ||
      !all(data$contents_code %in% contents) ||
      !all(data$sni_code %in% sni)) stop("SCB-delens radantal eller urval stämmer inte")
  key <- data[c("geo_code", "period", "education_code", "contents_code", "sni_code")]
  if (anyDuplicated(key)) stop("Dubbletter i SCB-del")
  # Deterministisk ordning ger identiska chunkar och checksumma vid återstart.
  data <- data[do.call(order, key), , drop = FALSE]
  rownames(data) <- NULL
  data
}

e3_municipal_observations <- function(data, meta) {
  label <- function(variable, codes) {
    unname(unlist(meta$dimension[[variable]]$category$label)[codes])
  }
  contents_label <- label("ContentsCode", data$contents_code)
  sni_label <- label("SNI2007", data$sni_code)
  education_label <- label("Utbildning", data$education_code)
  if (anyNA(c(contents_label, sni_label, education_label))) stop("SCB-etiketter saknas")
  lapply(seq_len(nrow(data)), function(i) list(
    geo_code = data$geo_code[[i]], period = data$period[[i]], value = data$value[[i]],
    dimensions = list(
      contents_code = data$contents_code[[i]], contents_label = contents_label[[i]],
      sni2007_code = data$sni_code[[i]], sni2007_label = sni_label[[i]],
      utbildning_indelning_code = "grupp", utbildning_indelning_label = "Utbildningsgrupp",
      utbildning_codelist = "vs_UtbildningsgruppE2-3N1-2",
      utbildning_code = data$education_code[[i]], utbildning_label = education_label[[i]],
      kon_alder_fodelseland_code = "totalt", kon_alder_fodelseland_label = "totalt"
    )
  ))
}

# ---- Körning ----

e3_municipal_run <- function() {
  suppressPackageStartupMessages(library(pxweb2r))
  source("R/etl/etl_api.R")
  source("R/etl/scb_common.R")

  flag <- function(name) tolower(Sys.getenv(name, "false")) %in% c("1", "true", "yes")
  test <- flag("ETL_TEST_MODE")
  finalize_test <- flag("ETL_TEST_FINALIZE")
  dry_run <- flag("ETL_DRY_RUN")
  if (test && finalize_test) stop("Välj endast ett testläge")
  indicator <- if (test || finalize_test) "e3-matchning-utbildning-kommun-etl-test" else "e3-matchning-utbildning-kommun"

  # Hämta metadata även vid återstart. Tidpunkten ingår i importens identitet.
  meta <- pxweb2_get_metadata("TAB6929")
  updated <- meta$updated
  if (is.null(updated) || length(updated) != 1L || is.na(updated) || !nzchar(updated)) {
    stop("SCB:s versionsdatum saknas; säker återstart är inte möjlig")
  }
  regions <- sort(scb_get_codelist_codes("vs_CKM03Kommun"))
  education <- sort(scb_get_codelist_codes("vs_UtbildningsgruppE2-3N1-2"))
  codes <- function(variable) sort(names(meta$dimension[[variable]]$category$index))
  years <- codes("Tid")
  sni <- codes("SNI2007")
  contents <- setdiff(codes("ContentsCode"), "000008QW")
  if (!length(regions) || any(!grepl("^[0-9]{4}$", regions)) ||
      !"000008QW" %in% codes("ContentsCode") ||
      !"000008QS" %in% contents || !"totalt" %in% codes("KonAlderFodelseland")) {
    stop("SCB:s dimensioner har ändrats; kontrollera definitionen")
  }
  if (test || finalize_test) {
    regions <- head(regions, 2L)
    education <- head(education, 2L)
    years <- tail(years, 1L)
    if (test) sni <- "A-U"
  }
  plan <- e3_municipal_plan(regions, years, education, sni, contents)
  if (plan$chunks > ETL_MAX_CHUNKS) stop("Importen överskrider batchgränsen")
  message(sprintf("E3 kommun: %d kommuner × %d år × %d utbildningsgrupper × %d näringsgrenar × %d mått = %.0f rader; %d chunkar",
                  length(regions), length(years), length(education), length(sni), length(contents), plan$rows, plan$chunks))
  spec <- list(version = "e3-kommun-v1", updated = updated, indicator = indicator,
               regions = regions, years = years, education = education, sni = sni,
               contents = contents, chunk_rows = 5000L, test = test, finalize_test = finalize_test)
  import_key <- digest::digest(as.character(jsonlite::toJSON(spec, auto_unbox = TRUE)), algo = "sha256", serialize = FALSE)

  if (dry_run) {
    part <- plan$parts[[1L]]
    sample <- pxweb2_get_data(meta, query = e3_municipal_query(part, sni, contents), quiet = TRUE)
    sample <- e3_municipal_normalize(sample, meta, part, sni, contents)
    payload <- e3_municipal_observations(head(sample, 5000L), meta)
    if (!length(payload)) stop("Inget provdata")
    message("SCB-prov godkänt; inga databasanrop eller publiceringar utförda")
    return(invisible(plan))
  }

  resume <- etl_get_resumable_history_batch(indicator, import_key)
  if (is.null(resume) && !test && !finalize_test && !flag("ETL_FORCE_REFRESH")) {
    state <- etl_get_state(indicator)
    last <- state$last_successful_at
    if (!is.null(last) && !is.na(last) && nzchar(last) &&
        isFALSE(pxweb2_table_needs_update("TAB6929", reference_datetime = last))) {
      etl_log_no_change(indicator, "SCB")
      message("E3 kommun: SCB har inte publicerat en ny version")
      return(invisible(NULL))
    }
  }
  if (!is.null(resume)) {
    if (resume$expected_rows != plan$rows || resume$expected_chunks != plan$chunks) stop("Återstartens plan stämmer inte")
    etl_reopen_history_batch(resume$id)
    batch_id <- resume$id
    next_chunk <- as.integer(resume$next_chunk_index)
  } else {
    batch <- etl_start_batch(indicator, "SCB", substr(updated, 1L, 10L),
                             plan$chunks, plan$rows, import_key = import_key)
    batch_id <- batch$batch_id
    next_chunk <- 0L
  }
  message(sprintf("Batch %s, fortsätter från chunk %d/%d", batch_id, next_chunk + 1L, plan$chunks))
  # Lämna staged-data för återstart även om processen dödas av GitHub Actions.
  ok <- FALSE
  on.exit({
    if (!ok) try(etl_abort_batch(batch_id, "E3 kommun avbruten; sparade chunkar kan återupptas med samma importnyckel"), silent = TRUE)
  }, add = TRUE)
  started <- proc.time()[["elapsed"]]
  budget <- as.numeric(Sys.getenv("ETL_RUN_BUDGET_SECONDS", "14400"))
  if (!is.finite(budget) || budget < 1) stop("Ogiltig tidsbudget")
  assert_version <- function() {
    current <- pxweb2_get_metadata("TAB6929")
    if (!identical(current$updated, updated)) stop("SCB-versionen ändrades under importen; publicering stoppad")
  }
  for (part in plan$parts) {
    if (part$first_chunk + part$chunks <= next_chunk) next
    assert_version()
    message(sprintf("SCB-del: år %s, utbildning %s, %d kommuner", part$year, part$education, length(part$regions)))
    data <- pxweb2_get_data(meta, query = e3_municipal_query(part, sni, contents), quiet = TRUE)
    data <- e3_municipal_normalize(data, meta, part, sni, contents)
    for (i in seq_len(part$chunks)) {
      index <- part$first_chunk + i - 1L
      # En delvis sparad SCB-del spelas om från början. Checksumma verifierar
      # att omhämtade värden är identiska med de redan sparade.
      from <- (i - 1L) * 5000L + 1L
      to <- min(i * 5000L, nrow(data))
      observations <- e3_municipal_observations(data[from:to, , drop = FALSE], meta)
      etl_publish_batch_chunk(batch_id, indicator, index, observations)
      message(sprintf("Sparad chunk %d/%d", index + 1L, plan$chunks))
      if (proc.time()[["elapsed"]] - started >= budget && index + 1L < plan$chunks) {
        etl_abort_batch(batch_id, "Planerad paus vid tidsbudget; fortsätt vid nästa körning")
        ok <- TRUE
        message("Import pausad. Sparade chunkar fortsätter nästa körning; ingen data publicerad.")
        return(invisible(list(paused = TRUE, batch_id = batch_id)))
      }
    }
    rm(data, observations)
  }
  assert_version()
  if (test) {
    result <- etl_abort_batch(batch_id, "Kontrollerat kommunprov utan publicering")
  } else {
    result <- etl_finalize_batch(batch_id)
  }
  ok <- TRUE
  message(sprintf("E3 kommun klart: %s, %.0f rader, batch %s", if (test) "prov" else "publicerad", plan$rows, batch_id))
  invisible(result)
}

if (tolower(Sys.getenv("ETL_E3_FUNCTIONS_ONLY", "false")) != "true") e3_municipal_run()
