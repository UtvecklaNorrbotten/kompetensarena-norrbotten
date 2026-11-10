# Hjälpfunktioner för Skolverkets SIRIS-exporter.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(tidyr)
})

skv_decode_csv <- function(raw) {
  text <- rawToChar(raw)
  text <- sub("^\\ufeff", "", text)
  lines <- strsplit(text, "\\r?\\n", perl = TRUE)[[1]]

  header_index <- which(grepl("^(Skola|Skolenhet);", lines))[1]
  if (is.na(header_index)) stop("SIRIS-exporten saknar tabellhuvud")

  table_text <- paste(lines[header_index:length(lines)], collapse = "\n")

  data <- read_delim(
    I(table_text),
    delim = ";",
    col_types = cols(.default = col_character()),
    locale = locale(decimal_mark = ",", encoding = "UTF-8"),
    trim_ws = TRUE,
    name_repair = "minimal",
    show_col_types = FALSE
  )

  empty_names <- which(is.na(names(data)) | names(data) == "")
  if (length(empty_names)) data <- data[, -empty_names, drop = FALSE]
  data
}

skv_exact_number <- function(x) {
  x <- trimws(as.character(x))
  exact <- grepl("^-?[0-9]+([,.][0-9]+)?$", x)
  out <- rep(NA_real_, length(x))
  out[exact] <- parse_number(
    x[exact],
    locale = locale(decimal_mark = ",", grouping_mark = " ")
  )
  out
}

skv_valid_school_rows <- function(data, school_col, municipality_col) {
  school <- as.character(data[[school_col]])
  municipality <- as.character(data[[municipality_col]])

  grepl("^[0-9]{8}$", school) &
    grepl("^[0-9]{4}$", municipality)
}

skv_common_dimensions <- function(data, school_name, school_code,
                                  municipality_name, municipality_code,
                                  owner_type = NULL) {
  lapply(seq_len(nrow(data)), function(i) {
    out <- list(
      skolenhet_code = as.character(data[[school_code]][[i]]),
      skolenhet_name = as.character(data[[school_name]][[i]]),
      kommun_code = as.character(data[[municipality_code]][[i]]),
      kommun_name = as.character(data[[municipality_name]][[i]]),
      lan_code = substr(as.character(data[[municipality_code]][[i]]), 1L, 2L)
    )

    if (!is.null(owner_type) && owner_type %in% names(data)) {
      value <- as.character(data[[owner_type]][[i]])
      if (!is.na(value) && nzchar(value)) out$huvudman_typ <- value
    }

    out
  })
}

skv_make_observations <- function(data, period, value_col, school_name,
                                  school_code, municipality_name,
                                  municipality_code, owner_type = NULL) {
  values <- skv_exact_number(data[[value_col]])
  keep <- !is.na(values) &
    values >= 0 &
    values <= 100 &
    skv_valid_school_rows(data, school_code, municipality_code)

  data <- data[keep, , drop = FALSE]
  values <- values[keep]

  dims <- skv_common_dimensions(
    data, school_name, school_code, municipality_name, municipality_code, owner_type
  )

  lapply(seq_len(nrow(data)), function(i) {
    list(
      geo_code = as.character(data[[municipality_code]][[i]]),
      period = as.character(period),
      value = values[[i]],
      dimensions = dims[[i]]
    )
  })
}

skv_parse_gr9 <- function(data, period) {
  required <- c(
    "Skola", "Skol-enhetskod", "Skolkommun", "Kommun-kod", "Typ av huvudman",
    "Kön", "Andel (%) elever behöriga till yrkesprog."
  )
  missing <- setdiff(required, names(data))
  if (length(missing)) stop("Åk 9-export saknar kolumner: ", paste(missing, collapse = ", "))

  data <- data |>
    filter(Kön == "Samtliga")

  skv_make_observations(
    data = data,
    period = period,
    value_col = "Andel (%) elever behöriga till yrkesprog.",
    school_name = "Skola",
    school_code = "Skol-enhetskod",
    municipality_name = "Skolkommun",
    municipality_code = "Kommun-kod",
    owner_type = "Typ av huvudman"
  )
}

skv_parse_graduates <- function(data, period) {
  required <- c(
    "Skola", "Skol-enhetskod", "Skolkommun", "Kommun-kod", "Typ av huvudman",
    "Program", "Andel (%) med examen", "Andel (%) med grundl. behörighet"
  )
  missing <- setdiff(required, names(data))
  if (length(missing)) stop("Gymnasieexport saknar kolumner: ", paste(missing, collapse = ", "))

  data <- data |>
    filter(Program == "Nationella program")

  list(
    exam = skv_make_observations(
      data, period, "Andel (%) med examen",
      "Skola", "Skol-enhetskod", "Skolkommun", "Kommun-kod", "Typ av huvudman"
    ),
    higher_education = skv_make_observations(
      data, period, "Andel (%) med grundl. behörighet",
      "Skola", "Skol-enhetskod", "Skolkommun", "Kommun-kod", "Typ av huvudman"
    )
  )
}

skv_parse_throughput_series <- function(data, expected_label = NULL, periods = 10L) {
  required <- c(
    "Skolenhet", "Skolenhets-kod", "Kommun", "Kommun-kod",
    "Typ av huvudman", "Program", "Genomströmning"
  )
  missing <- setdiff(required, names(data))
  if (length(missing)) stop("Genomströmningsfil saknar kolumner: ", paste(missing, collapse = ", "))

  data <- data |>
    filter(Program == "Gymnasieskolan totalt")

  if (!is.null(expected_label) && any(data$Genomströmning != expected_label, na.rm = TRUE)) {
    stop("Genomströmningsdefinitionen har ändrats")
  }

  period_cols <- names(data)[grepl("^[0-9]{4}/[0-9]{2}$", names(data))]
  if (length(period_cols) < periods) stop("Genomströmningsfilen har färre än ", periods, " perioder")
  period_cols <- head(period_cols, periods)

  long <- data |>
    select(all_of(required), all_of(period_cols)) |>
    pivot_longer(all_of(period_cols), names_to = "period", values_to = "source_value") |>
    mutate(value = skv_exact_number(source_value))

  keep <- !is.na(long$value) &
    long$value >= 0 &
    long$value <= 100 &
    skv_valid_school_rows(long, "Skolenhets-kod", "Kommun-kod")

  long <- long[keep, , drop = FALSE]

  dims <- skv_common_dimensions(
    long, "Skolenhet", "Skolenhets-kod", "Kommun", "Kommun-kod", "Typ av huvudman"
  )

  lapply(seq_len(nrow(long)), function(i) {
    list(
      geo_code = as.character(long[["Kommun-kod"]][[i]]),
      period = as.character(long$period[[i]]),
      value = long$value[[i]],
      dimensions = dims[[i]]
    )
  })
}

skv_validate_observations <- function(observations, indicator_id, expected_periods = 10L) {
  if (!length(observations)) stop(indicator_id, ": inga publicerbara observationer")

  periods <- unique(vapply(observations, function(x) x$period, character(1)))
  if (length(periods) != expected_periods) {
    stop(indicator_id, ": förväntade ", expected_periods, " perioder men fick ", length(periods))
  }

  values <- vapply(observations, function(x) as.numeric(x$value), numeric(1))
  if (any(!is.finite(values) | values < 0 | values > 100)) {
    stop(indicator_id, ": orimliga procentvärden")
  }

  keys <- vapply(observations, function(x) {
    paste(x$geo_code, x$period, x$dimensions$skolenhet_code, sep = "|")
  }, character(1))
  if (anyDuplicated(keys)) stop(indicator_id, ": dubbletter på kommun/period/skolenhet")

  if (!any(startsWith(vapply(observations, function(x) x$geo_code, character(1)), "25"))) {
    stop(indicator_id, ": inga skolor i Norrbotten hittades")
  }

  invisible(TRUE)
}
