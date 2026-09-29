# Separat historikvalidering för Arbetsförmedlingens källor.
# Körs per källa eller per korsvalidering så att fel isoleras och jobben kan gå parallellt.

source("R/etl/af_common.R")
source("R/etl/af_normalize.R")

target <- Sys.getenv("AF_VALIDATION_TARGET", unset = "")
kind <- Sys.getenv("AF_VALIDATION_KIND", unset = "")
report_dir <- Sys.getenv("AF_VALIDATION_REPORT_DIR", unset = "artifacts/af-history")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

if (!target %in% c("sok", "tid", "svag", "yrke", "bas")) {
  stop("Ogiltigt AF_VALIDATION_TARGET: ", target)
}
if (!kind %in% c("structure", "compare")) {
  stop("Ogiltigt AF_VALIDATION_KIND: ", kind)
}
if (kind == "compare" && target == "tid") {
  stop("compare stöds inte för target=tid")
}

manifest_all <- af_discover_sources()
common_period <- af_common_period(manifest_all)
if (is.na(common_period)) {
  stop("AF-filerna visar inte samma period; historikvalidering avbryts.")
}

source_keys <- switch(
  target,
  sok = "arbetssokande",
  tid = c("tid_utan_arbete", "tid_utan_arbete_riket"),
  svag = "svag_konkurrensformaga",
  yrke = "yrkesomrade",
  bas = "arbetskraft_bas"
)
if (kind == "compare") {
  source_keys <- unique(c(source_keys, "tid_utan_arbete"))
}

manifest <- manifest_all |>
  dplyr::filter(source_key %in% source_keys)

tmp <- tempfile("af-history-")
dir.create(tmp)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

files <- af_download_sources(manifest, tmp)
path_for <- function(key) files$path[match(key, files$source_key)][[1]]

utils::write.csv(
  files |>
    dplyr::select(source_key, label, period, filename, url, sha256, bytes),
  file.path(report_dir, "source-manifest.csv"),
  row.names = FALSE,
  na = ""
)

municipality_lookup <- af_get_municipality_codes()
municipality_codes <- unique(unname(municipality_lookup))
if (length(municipality_codes) != 290L) {
  stop("SCB:s kommunlista innehåller inte 290 kommuner")
}

af_history_normalize_target <- function(target) {
  switch(
    target,
    sok = af_normalize_web_sok(path_for("arbetssokande")),
    tid = af_normalize_tid_utan_arbete(
      path_for("tid_utan_arbete"),
      riket_path = path_for("tid_utan_arbete_riket")
    ),
    svag = af_normalize_svag_konkurrensformaga(path_for("svag_konkurrensformaga")),
    yrke = af_normalize_yrkesomrade(path_for("yrkesomrade")),
    bas = af_normalize_bas(path_for("arbetskraft_bas"))
  )
}

af_history_structure <- function(data, target, latest_period) {
  if (nrow(data) == 0) stop(target, ": normaliseringen gav 0 rader")
  if (any(is.na(data$period) | !nzchar(data$period))) stop(target, ": saknad period")
  if (any(is.na(data$geo_code) | !nzchar(data$geo_code))) stop(target, ": saknad geokod")
  if (all(is.na(data$value))) stop(target, ": endast NA-värden")

  max_period <- max(as.character(data$period), na.rm = TRUE)
  if (!identical(max_period, latest_period)) {
    stop(target, ": maxperiod ", max_period, " men filerna anger ", latest_period)
  }

  key_cols <- c(
    "period", "geo_code", "geo_level", "sex",
    "dimension_type", "dimension_value", "measure_code"
  )
  dup <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(key_cols))) |>
    dplyr::summarise(n = dplyr::n(), .groups = "drop") |>
    dplyr::filter(n > 1)
  if (nrow(dup) > 0) {
    utils::write.csv(
      dup,
      file.path(report_dir, paste0("duplicate-keys-", target, ".csv")),
      row.names = FALSE,
      na = ""
    )
    stop(target, ": ", nrow(dup), " dubblettnycklar efter normalisering")
  }

  coverage <- data |>
    dplyr::distinct(period, geo_code, geo_level) |>
    dplyr::count(period, geo_level, name = "n_geographies") |>
    tidyr::pivot_wider(
      names_from = geo_level,
      values_from = n_geographies,
      values_fill = 0
    ) |>
    dplyr::arrange(period)

  for (nm in c("kommun", "län", "riket")) {
    if (!nm %in% names(coverage)) coverage[[nm]] <- 0L
  }

  utils::write.csv(
    coverage,
    file.path(report_dir, paste0("coverage-", target, ".csv")),
    row.names = FALSE,
    na = ""
  )

  latest <- coverage |>
    dplyr::filter(period == latest_period)

  if (nrow(latest) != 1L) {
    stop(target, ": saknar täckningsrad för aktuell period ", latest_period)
  }
  if (latest$kommun[[1]] != 290L) {
    stop(target, ": aktuell period har ", latest$kommun[[1]], " kommuner, förväntat 290")
  }
  if (latest$län[[1]] != 21L) {
    stop(target, ": aktuell period har ", latest$län[[1]], " län, förväntat 21")
  }
  if (latest$riket[[1]] != 1L) {
    stop(target, ": aktuell period saknar exakt en rikspost")
  }

  lower_bounds <- if ("value_is_lower_bound" %in% names(data)) {
    sum(data$value_is_lower_bound %in% TRUE)
  } else {
    0L
  }

  summary <- data.frame(
    target = target,
    rows = nrow(data),
    first_period = min(as.character(data$period), na.rm = TRUE),
    last_period = max_period,
    periods = dplyr::n_distinct(data$period),
    lower_bound_rows = lower_bounds,
    latest_municipalities = latest$kommun[[1]],
    latest_counties = latest$län[[1]],
    latest_riket = latest$riket[[1]],
    stringsAsFactors = FALSE
  )

  utils::write.csv(
    summary,
    file.path(report_dir, paste0("structure-summary-", target, ".csv")),
    row.names = FALSE,
    na = ""
  )

  message(
    target, ": struktur OK; ",
    format(nrow(data), big.mark = " "), " rader; period ",
    summary$first_period, "–", summary$last_period,
    "; aktuell period 290 kommuner + 21 län + Riket."
  )
}

af_compare_shared_coverage <- function(actual, expected, label) {
  keys <- c("period", "geo_code", "sex")

  if (!"actual_is_lower_bound" %in% names(actual)) {
    actual$actual_is_lower_bound <- FALSE
  }
  if (!"expected_is_lower_bound" %in% names(expected)) {
    expected$expected_is_lower_bound <- FALSE
  }

  actual <- actual |>
    dplyr::filter(geo_code %in% municipality_codes) |>
    dplyr::select(dplyr::all_of(keys), actual, actual_is_lower_bound)

  expected <- expected |>
    dplyr::filter(geo_code %in% municipality_codes) |>
    dplyr::select(dplyr::all_of(keys), expected, expected_is_lower_bound)

  dup_actual <- actual |>
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) |>
    dplyr::summarise(n = dplyr::n(), .groups = "drop") |>
    dplyr::filter(n > 1)
  dup_expected <- expected |>
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) |>
    dplyr::summarise(n = dplyr::n(), .groups = "drop") |>
    dplyr::filter(n > 1)

  if (nrow(dup_actual) > 0 || nrow(dup_expected) > 0) {
    stop(
      label, ": dubblettnycklar före jämförelse (actual=",
      nrow(dup_actual), ", expected=", nrow(dup_expected), ")"
    )
  }

  overlap <- dplyr::inner_join(actual, expected, by = keys)

  if (nrow(overlap) == 0) {
    stop(label, ": inga gemensamma rader att jämföra")
  }

  exact_or_valid_bound <- overlap |>
    dplyr::mutate(
      issue = dplyr::case_when(
        is.na(actual) | is.na(expected) ~ NA_character_,
        !actual_is_lower_bound & !expected_is_lower_bound &
          abs(actual - expected) > 1e-8 ~ "avvikelse",
        actual_is_lower_bound & !expected_is_lower_bound &
          expected < actual - 1e-8 ~ "under_undre_grans",
        !actual_is_lower_bound & expected_is_lower_bound &
          actual < expected - 1e-8 ~ "under_undre_grans",
        TRUE ~ NA_character_
      )
    )

  issues <- exact_or_valid_bound |>
    dplyr::filter(!is.na(issue))

  actual_keys <- actual |>
    dplyr::select(dplyr::all_of(keys))
  expected_keys <- expected |>
    dplyr::select(dplyr::all_of(keys))

  only_actual <- dplyr::anti_join(actual_keys, expected_keys, by = keys)
  only_expected <- dplyr::anti_join(expected_keys, actual_keys, by = keys)

  coverage <- data.frame(
    label = label,
    actual_first_period = min(actual$period),
    actual_last_period = max(actual$period),
    expected_first_period = min(expected$period),
    expected_last_period = max(expected$period),
    actual_keys = nrow(actual),
    expected_keys = nrow(expected),
    overlap_keys = nrow(overlap),
    only_actual_keys = nrow(only_actual),
    only_expected_keys = nrow(only_expected),
    comparable_exact_or_bound = sum(!is.na(overlap$actual) & !is.na(overlap$expected)),
    lower_bound_rows = sum(
      overlap$actual_is_lower_bound | overlap$expected_is_lower_bound,
      na.rm = TRUE
    ),
    issues = nrow(issues),
    stringsAsFactors = FALSE
  )

  utils::write.csv(
    coverage,
    file.path(report_dir, paste0("comparison-coverage-", target, ".csv")),
    row.names = FALSE,
    na = ""
  )
  utils::write.csv(
    issues,
    file.path(report_dir, paste0("comparison-issues-", target, ".csv")),
    row.names = FALSE,
    na = ""
  )

  if (nrow(issues) > 0) {
    ex <- issues[1, , drop = FALSE]
    stop(
      label, ": ", nrow(issues),
      " verkliga avvikelser inom gemensam täckning. Första: period=",
      ex$period, ", geo=", ex$geo_code, ", kön=", ex$sex,
      ", actual=", ex$actual, ", expected=", ex$expected,
      ", typ=", ex$issue
    )
  }

  message(
    label, ": OK inom gemensam täckning (",
    format(nrow(overlap), big.mark = " "), " nycklar). ",
    "Utanför överlapp: actual=", format(nrow(only_actual), big.mark = " "),
    ", expected=", format(nrow(only_expected), big.mark = " "),
    "; dessa rapporteras som täckning, inte datafel."
  )
}

if (kind == "structure") {
  data <- af_history_normalize_target(target)
  af_history_structure(data, target, common_period)
} else {
  expected <- af_control_tid_sex(path_for("tid_utan_arbete"))

  actual <- switch(
    target,
    sok = af_control_web_sok_total_by_sex(path_for("arbetssokande")),
    svag = af_control_svag_samtliga(path_for("svag_konkurrensformaga")),
    yrke = af_control_yrkesomrade_total(path_for("yrkesomrade")),
    bas = af_control_bas_sok(path_for("arbetskraft_bas"))
  )

  label <- switch(
    target,
    sok = "web-sok INSAL mot tid-filen ARBETSLÖSA",
    svag = "svag konkurrensförmåga SAMTLIGA mot tid-filen ARBETSLÖSA",
    yrke = "yrkesområden summerade mot tid-filen ARBETSLÖSA",
    bas = "BAS-filens SOK-tal mot tid-filen ARBETSLÖSA"
  )

  af_compare_shared_coverage(actual, expected, label)
}
