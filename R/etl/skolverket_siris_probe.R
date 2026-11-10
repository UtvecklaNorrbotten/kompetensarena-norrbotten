# ---- Skolverket SIRIS direct export probe ----

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(readr)
})

base <- "https://siris.skolverket.se/siris/reports/export_api"
out_dir <- "artifacts/skolverket_siris_probe"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

get_text <- function(url) {
  request(url) |>
    req_user_agent("Kompetensarena-Norrbotten-Skolverket-ETL/1.0") |>
    req_timeout(120) |>
    req_retry(max_tries = 4, retry_on_failure = TRUE) |>
    req_perform() |>
    resp_body_string()
}

get_years <- function(verkform, export_id) {
  url <- paste0(
    base, "/lasar/?pVerkform=", URLencode(verkform),
    "&pExportID=", export_id,
    "&svAjaxReqParam=ajax"
  )
  txt <- get_text(url)
  writeLines(txt, file.path(out_dir, paste0("years_", verkform, "_", export_id, ".json")))
  fromJSON(txt, simplifyVector = TRUE)
}

export_url <- function(verkform, export_id, year, format = "csv") {
  paste0(
    base, "/runexport/?",
    "pFormat=", format,
    "&pExportID=", export_id,
    "&pAr=", URLencode(as.character(year)),
    "&pLan=&pKommun=&pHmantyp=&pUttag=&pSortering=&pToken=",
    "&pVerkform=", URLencode(verkform),
    "&pFlikar=0"
  )
}

download_probe <- function(verkform, export_id, year, label) {
  url <- export_url(verkform, export_id, year)
  resp <- request(url) |>
    req_user_agent("Kompetensarena-Norrbotten-Skolverket-ETL/1.0") |>
    req_timeout(180) |>
    req_retry(max_tries = 4, retry_on_failure = TRUE) |>
    req_perform()

  raw <- resp_body_raw(resp)
  raw_path <- file.path(out_dir, paste0(label, "_", year, ".csv"))
  writeBin(raw, raw_path)

  # SIRIS CSV has historically used semicolon + decimal comma.
  df <- tryCatch(
    read_delim(
      I(raw),
      delim = ";",
      locale = locale(decimal_mark = ",", encoding = "UTF-8"),
      show_col_types = FALSE,
      name_repair = "minimal",
      trim_ws = TRUE
    ),
    error = function(e) NULL
  )

  summary <- c(
    paste0("label=", label),
    paste0("url=", url),
    paste0("status=", resp_status(resp)),
    paste0("bytes=", length(raw)),
    paste0("content_type=", resp_header(resp, "content-type")),
    paste0("parsed=", !is.null(df)),
    paste0("rows=", if (is.null(df)) NA_integer_ else nrow(df)),
    paste0("columns=", if (is.null(df)) "" else paste(names(df), collapse = "|"))
  )
  writeLines(summary, file.path(out_dir, paste0(label, "_", year, "_summary.txt")))

  if (!is.null(df)) {
    writeLines(
      capture.output(print(head(df, 10), width = Inf)),
      file.path(out_dir, paste0(label, "_", year, "_head.txt"))
    )
  }

  invisible(df)
}

# Target export families discovered from the live SIRIS D-form.
targets <- list(
  gr9_eligibility = list(verkform = "11", export_id = 5L),
  gy_graduates = list(verkform = "21", export_id = 88L),
  gy_throughput_all = list(verkform = "21", export_id = 90L),
  gy_throughput_3y_series = list(verkform = "21", export_id = 360L),
  gy_throughput_4y_series = list(verkform = "21", export_id = 405L),
  gy_throughput_5y_series = list(verkform = "21", export_id = 410L)
)

manifest <- list()

for (nm in names(targets)) {
  x <- targets[[nm]]
  years <- get_years(x$verkform, x$export_id)
  manifest[[nm]] <- years

  data <- years$data
  if (is.data.frame(data) && nrow(data) > 0L) {
    latest <- as.character(data$kod[[1]])
    download_probe(x$verkform, x$export_id, latest, nm)
  } else {
    writeLines("No years returned", file.path(out_dir, paste0(nm, "_no_years.txt")))
  }
}

writeLines(
  toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null"),
  file.path(out_dir, "manifest.json")
)
