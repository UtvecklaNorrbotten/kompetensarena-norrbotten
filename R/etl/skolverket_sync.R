# -------------------------------------------------------------------
# Kompetensarena Norrbotten - ETL Skolverket/SIRIS
# -------------------------------------------------------------------
# Avgränsning:
# - åk 9: behörighet till gymnasieskolans nationella program
# - grundläggande högskolebehörighet
# - gymnasieexamen
# - genomströmning med examen inom 3, 4 och 5 år
# - exakt tio historiska perioder per indikator
#
# Skolenhetskod lagras som dimension. geo_code är skolkommunens kommunkod.
# Skolverkets sekretess-/approximationstecken publiceras inte som exakta värden.
# -------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(httr2)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(stringr)
  library(tidyr)
})

source("R/etl/etl_api.R")
source("R/etl/skolverket_values.R")

skv_source_id <- "skolverket-siris"
skv_source_name <- "Skolverket"
skv_base <- "https://siris.skolverket.se/siris/reports/export_api"
skv_test_mode <- tolower(Sys.getenv("ETL_TEST_MODE", unset = "false")) %in% c("1", "true", "yes")

skv_indicators <- list(
  gr9 = "skolverket-ak9-gymnasiebehorighet",
  higher = "skolverket-grundlaggande-hogskolebehorighet",
  exam = "skolverket-gymnasieexamen",
  y3 = "skolverket-genomstromning-3-ar",
  y4 = "skolverket-genomstromning-4-ar",
  y5 = "skolverket-genomstromning-5-ar"
)

skv_request <- function(url) {
  request(url) |>
    req_user_agent("Kompetensarena-Norrbotten-Skolverket-ETL/1.0") |>
    req_timeout(180) |>
    req_retry(
      max_tries = 5,
      retry_on_failure = TRUE,
      is_transient = function(resp) resp_status(resp) %in% c(408L, 429L, 500L, 502L, 503L, 504L)
    )
}

skv_years <- function(verkform, export_id) {
  url <- paste0(
    skv_base, "/lasar/?pVerkform=", verkform,
    "&pExportID=", export_id,
    "&svAjaxReqParam=ajax"
  )

  x <- skv_request(url) |>
    req_perform() |>
    resp_body_json(simplifyVector = TRUE)

  data <- x$data
  if (!is.data.frame(data) || !all(c("kod", "namn") %in% names(data)) || !nrow(data)) {
    stop("SIRIS saknar periodmetadata för export ", export_id)
  }

  tibble::tibble(
    code = as.character(data$kod),
    label = as.character(data$namn)
  )
}

skv_export_url <- function(verkform, export_id, year_code) {
  paste0(
    skv_base, "/runexport/?",
    "pFormat=csv",
    "&pExportID=", export_id,
    "&pAr=", URLencode(as.character(year_code)),
    "&pLan=&pKommun=&pHmantyp=&pUttag=&pSortering=&pToken=",
    "&pVerkform=", verkform,
    "&pFlikar=0"
  )
}

skv_export <- function(verkform, export_id, year_code) {
  response <- skv_request(skv_export_url(verkform, export_id, year_code)) |>
    req_perform()

  raw <- resp_body_raw(response)
  if (!length(raw)) stop("Tom SIRIS-export ", export_id, "/", year_code)

  skv_decode_csv(raw)
}

skv_academic_period <- function(label) {
  str_extract(label, "^[0-9]{4}/[0-9]{2}")
}

skv_recent_periods <- function(verkform, export_id, n = 10L) {
  periods <- skv_years(verkform, export_id) |>
    mutate(period = skv_academic_period(label)) |>
    filter(!is.na(period)) |>
    slice_head(n = n)

  if (nrow(periods) != n) stop("Export ", export_id, " har färre än ", n, " perioder")
  periods
}

skv_download_annual <- function(verkform, export_id, parser, n = 10L) {
  periods <- skv_recent_periods(verkform, export_id, n)
  out <- vector("list", nrow(periods))

  for (i in seq_len(nrow(periods))) {
    message("Skolverket export ", export_id, ": ", periods$period[[i]])
    data <- skv_export(verkform, export_id, periods$code[[i]])
    out[[i]] <- parser(data, periods$period[[i]])
  }

  out
}

skv_latest_series <- function(export_id, expected_label) {
  years <- skv_years("21", export_id)
  latest_code <- years$code[[1]]
  data <- skv_export("21", export_id, latest_code)

  skv_parse_throughput_series(
    data,
    expected_label = expected_label,
    periods = 10L
  )
}

skv_publish_or_test <- function(indicator_id, observations) {
  skv_validate_observations(observations, indicator_id, expected_periods = 10L)

  message(
    indicator_id, ": ",
    format(length(observations), big.mark = " "),
    " exakta skolenhetsvärden, ",
    length(unique(vapply(observations, function(x) x$period, character(1)))),
    " perioder"
  )

  if (skv_test_mode) return(invisible(list(rows = length(observations), test = TRUE)))

  etl_publish_batch(
    indicator_id = indicator_id,
    source = skv_source_name,
    source_updated_date = NULL,
    observations = observations
  )
}

run_skolverket_sync <- function() {
  gr9_parts <- skv_download_annual("11", 5L, skv_parse_gr9, 10L)
  gr9 <- unlist(gr9_parts, recursive = FALSE)

  graduate_parts <- skv_download_annual("21", 88L, skv_parse_graduates, 10L)
  exam <- unlist(lapply(graduate_parts, function(x) x$exam), recursive = FALSE)
  higher <- unlist(lapply(graduate_parts, function(x) x$higher_education), recursive = FALSE)

  y3 <- skv_latest_series(
    360L,
    "Andel elever (%) med examen från gymnasieskolan inom 3 år"
  )
  y4 <- skv_latest_series(
    405L,
    "Andel elever (%) med examen från gymnasieskolan inom 4 år"
  )
  y5 <- skv_latest_series(
    410L,
    "Andel elever (%) med examen från gymnasieskolan inom 5 år"
  )

  results <- list(
    gr9 = skv_publish_or_test(skv_indicators$gr9, gr9),
    higher = skv_publish_or_test(skv_indicators$higher, higher),
    exam = skv_publish_or_test(skv_indicators$exam, exam),
    y3 = skv_publish_or_test(skv_indicators$y3, y3),
    y4 = skv_publish_or_test(skv_indicators$y4, y4),
    y5 = skv_publish_or_test(skv_indicators$y5, y5)
  )

  if (!skv_test_mode) {
    latest_gr9 <- skv_recent_periods("11", 5L, 1L)$period[[1]]
    latest_gy <- skv_recent_periods("21", 88L, 1L)$period[[1]]

    etl_update_source_state(
      source_id = skv_source_id,
      status = "succeeded",
      latest_available_period = paste0("Grundskola ", latest_gr9, "; gymnasium ", latest_gy),
      latest_successful_period = paste0("Grundskola ", latest_gr9, "; gymnasium ", latest_gy),
      details = list(
        history_periods = 10L,
        source = "SIRIS export API",
        exports = list(
          gr9 = 5L,
          graduates = 88L,
          throughput = c(360L, 405L, 410L)
        ),
        privacy_rule = "Endast exakt numeriska källvärden publiceras; ., .. och ~-markerade värden utelämnas",
        geography_rule = "geo_code=skolkommun; skolenhetskod i dimensions"
      )
    )
  }

  invisible(results)
}

if (Sys.getenv("SKOLVERKET_LOAD_ONLY", unset = "false") != "true") {
  run_skolverket_sync()
}
