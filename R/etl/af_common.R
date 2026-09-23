# Gemensamma hjälpfunktioner för Arbetsförmedlingens månadsfiler.
#
# Grundprincip:
# 1. kontrollera endast den lilla HTML-sidan varje dag
# 2. identifiera aktuell YYYY-MM i filnamnet för samtliga primärkällor
# 3. ladda INTE ned någon xlsx förrän alla fem filer visar samma nya period
# 4. efter lyckad fullimport markeras perioden som importerad av den framtida
#    AF-orkestreringen; då laddas filerna inte igen nästa dag

suppressPackageStartupMessages({
  library(httr2)
  library(xml2)
  library(digest)
})

source("R/etl/af_sources.R")

af_discover_sources <- function(page_url = af_source_page) {
  response <- request(page_url) |>
    req_user_agent("Kompetensarena-Norrbotten-ETL/1.0") |>
    req_retry(
      max_tries = 5,
      retry_on_failure = TRUE,
      is_transient = function(resp) resp_status(resp) %in% c(429L, 502L, 503L, 504L)
    ) |>
    req_timeout(60) |>
    req_perform()

  html <- resp_body_string(response)
  doc <- read_html(html)
  hrefs <- xml_attr(xml_find_all(doc, ".//a[@href]"), "href")
  hrefs <- unique(stats::na.omit(hrefs))
  hrefs <- url_absolute(hrefs, page_url)

  rows <- lapply(names(af_sources), function(source_key) {
    cfg <- af_sources[[source_key]]
    prefix <- cfg$filename_prefix

    pattern <- paste0(
      prefix,
      "-(20[0-9]{2}-(?:0[1-9]|1[0-2]))\\.xlsx$"
    )

    clean_urls <- sub("[?#].*$", "", hrefs)
    filenames <- basename(clean_urls)
    is_match <- grepl(pattern, filenames, ignore.case = TRUE, perl = TRUE)

    matched <- hrefs[is_match]
    matched_filenames <- filenames[is_match]

    if (length(matched) == 0) {
      stop("Hittade ingen aktuell AF-fil för: ", cfg$label)
    }

    periods <- sub(
      pattern,
      "\\1",
      matched_filenames,
      ignore.case = TRUE,
      perl = TRUE
    )
    latest_period <- max(periods)
    latest_matches <- matched[periods == latest_period]

    if (length(latest_matches) != 1) {
      stop(
        "Förväntade exakt en senaste fil för ", cfg$label,
        " men hittade ", length(latest_matches), " för perioden ", latest_period
      )
    }

    data.frame(
      source_key = source_key,
      label = cfg$label,
      filename_prefix = prefix,
      period = latest_period,
      url = latest_matches[[1]],
      filename = basename(sub("[?#].*$", "", latest_matches[[1]])),
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

af_common_period <- function(manifest) {
  periods <- unique(manifest$period)

  if (length(periods) != 1) {
    status <- paste(
      paste0(manifest$source_key, "=", manifest$period),
      collapse = ", "
    )
    message("AF-filerna är ännu inte synkroniserade: ", status)
    return(NA_character_)
  }

  periods[[1]]
}

af_should_import <- function(manifest, last_imported_period = NA_character_) {
  common_period <- af_common_period(manifest)
  if (is.na(common_period)) return(FALSE)

  if (
    !is.na(last_imported_period) &&
    nzchar(last_imported_period) &&
    common_period <= last_imported_period
  ) {
    message(
      "AF-period ", common_period,
      " är redan importerad (senast ", last_imported_period, ")."
    )
    return(FALSE)
  }

  TRUE
}

af_download_sources <- function(manifest, dest_dir) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

  result <- manifest
  result$path <- NA_character_
  result$sha256 <- NA_character_
  result$bytes <- NA_real_

  for (i in seq_len(nrow(result))) {
    target <- file.path(dest_dir, result$filename[[i]])

    response <- request(result$url[[i]]) |>
      req_user_agent("Kompetensarena-Norrbotten-ETL/1.0") |>
      req_retry(
        max_tries = 5,
        retry_on_failure = TRUE,
        is_transient = function(resp) resp_status(resp) %in% c(429L, 502L, 503L, 504L)
      ) |>
      req_timeout(600) |>
      req_perform(path = target)

    if (!file.exists(target)) {
      stop("Nedladdningen skapade ingen fil: ", result$filename[[i]])
    }

    size <- file.info(target)$size
    if (is.na(size) || size < 10000) {
      stop("AF-filen är orimligt liten: ", result$filename[[i]], " (", size, " byte)")
    }

    signature <- readBin(target, what = "raw", n = 4)
    if (!identical(as.integer(signature), c(80L, 75L, 3L, 4L))) {
      stop("Nedladdningen är inte en giltig xlsx/zip-fil: ", result$filename[[i]])
    }

    result$path[[i]] <- normalizePath(target, winslash = "/", mustWork = TRUE)
    result$sha256[[i]] <- digest(file = target, algo = "sha256")
    result$bytes[[i]] <- size

    message(
      sprintf(
        "Hämtade %s: %.1f MB",
        result$filename[[i]],
        size / 1024^2
      )
    )
  }

  result
}
