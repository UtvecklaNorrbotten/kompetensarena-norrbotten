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

  periods <- sort(unique(as.character(data$period)))

  bind_rows(lapply(periods, function(p) {
    block <- data[as.character(data$period) == p, , drop = FALSE]
    lower_bound <- if ("value_is_lower_bound" %in% names(block)) {
      ifelse(block$value_is_lower_bound %in% TRUE, "1", "0")
    } else {
      rep("0", nrow(block))
    }

    canonical <- data.frame(
      geo_code = af_fingerprint_escape(block$geo_code),
      geo_level = af_fingerprint_escape(block$geo_level),
      sex = af_fingerprint_escape(block$sex),
      dimension_type = af_fingerprint_escape(block$dimension_type),
      dimension_value = af_fingerprint_escape(block$dimension_value),
      measure_code = af_fingerprint_escape(block$measure_code),
      measure_label = af_fingerprint_escape(block$measure_label),
      value = af_fingerprint_number(block$value),
      lower_bound = lower_bound,
      stringsAsFactors = FALSE
    ) |>
      arrange(
        geo_code, geo_level, sex,
        dimension_type, dimension_value,
        measure_code, measure_label, value, lower_bound
      )

    lines <- paste(
      canonical$geo_code,
      canonical$geo_level,
      canonical$sex,
      canonical$dimension_type,
      canonical$dimension_value,
      canonical$measure_code,
      canonical$measure_label,
      canonical$value,
      canonical$lower_bound,
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
