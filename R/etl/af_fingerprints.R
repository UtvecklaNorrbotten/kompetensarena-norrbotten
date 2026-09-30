# Stabil källfingerprint per AF-target och period.
# Samma R-kod används vid baseline, månadsimport och kvartalskontroll.

suppressPackageStartupMessages({
  library(digest)
  library(dplyr)
})

af_fingerprint_escape <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- "<NA>"
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("|", "\\|", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x
}

af_fingerprint_number <- function(x) {
  out <- rep("<NA>", length(x))
  ok <- !is.na(x)
  out[ok] <- sprintf("%.17g", as.numeric(x[ok]))
  out
}

af_period_fingerprints <- function(data) {
  required <- c(
    "period", "geo_code", "geo_level", "sex",
    "dimension_type", "dimension_value",
    "measure_code", "measure_label", "value"
  )
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop("Fingerprint saknar kolumner: ", paste(missing, collapse = ", "))
  }

  lower_bound <- if ("value_is_lower_bound" %in% names(data)) {
    ifelse(data$value_is_lower_bound %in% TRUE, "1", "0")
  } else {
    rep("0", nrow(data))
  }

  canonical <- data.frame(
    period = as.character(data$period),
    geo_code = af_fingerprint_escape(data$geo_code),
    geo_level = af_fingerprint_escape(data$geo_level),
    sex = af_fingerprint_escape(data$sex),
    dimension_type = af_fingerprint_escape(data$dimension_type),
    dimension_value = af_fingerprint_escape(data$dimension_value),
    measure_code = af_fingerprint_escape(data$measure_code),
    measure_label = af_fingerprint_escape(data$measure_label),
    value = af_fingerprint_number(data$value),
    lower_bound = lower_bound,
    stringsAsFactors = FALSE
  )

  canonical <- canonical |>
    arrange(
      period, geo_code, geo_level, sex,
      dimension_type, dimension_value,
      measure_code, measure_label, value, lower_bound
    )

  periods <- unique(canonical$period)

  bind_rows(lapply(periods, function(p) {
    block <- canonical[canonical$period == p, , drop = FALSE]

    lines <- paste(
      block$geo_code,
      block$geo_level,
      block$sex,
      block$dimension_type,
      block$dimension_value,
      block$measure_code,
      block$measure_label,
      block$value,
      block$lower_bound,
      sep = "|"
    )

    data.frame(
      period = p,
      checksum = digest(
        paste(lines, collapse = "\n"),
        algo = "sha256",
        serialize = FALSE
      ),
      row_count = nrow(block),
      stringsAsFactors = FALSE
    )
  })) |>
    arrange(period)
}

af_source_manifest_list <- function(files) {
  lapply(seq_len(nrow(files)), function(i) {
    list(
      source_key = as.character(files$source_key[[i]]),
      period = as.character(files$period[[i]]),
      filename = as.character(files$filename[[i]]),
      sha256 = as.character(files$sha256[[i]]),
      bytes = as.numeric(files$bytes[[i]])
    )
  })
}
