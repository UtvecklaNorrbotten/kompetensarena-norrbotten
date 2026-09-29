# Dry-run för Arbetsförmedlingens sex nödvändiga månadsfiler.
# Hämtar, normaliserar och gör strukturella kontroller samt korsvalideringar.
# Publicerar inget.
#
# Normal validate:
# - hela historiken normaliseras
# - aktuell gemensam period måste vara helt konsistent mellan källorna
# - historiska källskillnader rapporteras men blockerar inte
#
# Strict validate:
# - även historiska källskillnader blockerar körningen

source("R/etl/af_common.R")
source("R/etl/af_normalize.R")

af_env_flag <- function(name, default = FALSE) {
  value <- trimws(tolower(Sys.getenv(name, unset = if (default) "true" else "false")))
  value %in% c("1", "true", "yes", "ja")
}

af_control_compare <- function(
  actual,
  expected,
  label,
  latest_period,
  municipality_codes,
  strict_history = FALSE,
  tolerance = 1e-8
) {
  keys <- c("period", "geo_code", "sex")

  actual <- actual |>
    filter(geo_code %in% municipality_codes) |>
    select(all_of(keys), actual)

  expected <- expected |>
    filter(geo_code %in% municipality_codes) |>
    select(all_of(keys), expected)

  duplicate_actual <- actual |>
    count(across(all_of(keys)), name = "n") |>
    filter(n > 1)
  duplicate_expected <- expected |>
    count(across(all_of(keys)), name = "n") |>
    filter(n > 1)

  if (nrow(duplicate_actual) > 0 || nrow(duplicate_expected) > 0) {
    stop(
      "Korsvalideringen har dubblettnycklar: ", label,
      " (actual=", nrow(duplicate_actual),
      ", expected=", nrow(duplicate_expected), ")"
    )
  }

  check <- full_join(actual, expected, by = keys) |>
    mutate(
      issue_type = case_when(
        is.na(actual) & !is.na(expected) ~ "saknas_i_actual",
        !is.na(actual) & is.na(expected) ~ "saknas_i_expected",
        !is.na(actual) & !is.na(expected) & abs(actual - expected) > tolerance ~ "avvikelse",
        TRUE ~ NA_character_
      ),
      diff = ifelse(
        !is.na(actual) & !is.na(expected),
        actual - expected,
        NA_real_
      ),
      is_latest = period == latest_period
    )

  comparable <- check |>
    filter(!is.na(actual), !is.na(expected))

  issues <- check |>
    filter(!is.na(issue_type))

  latest_issues <- issues |>
    filter(is_latest)

  historical_issues <- issues |>
    filter(!is_latest)

  summary <- data.frame(
    label = label,
    latest_period = latest_period,
    compared_total = nrow(comparable),
    issues_total = nrow(issues),
    issues_latest = nrow(latest_issues),
    issues_historical = nrow(historical_issues),
    missing_actual_total = sum(issues$issue_type == "saknas_i_actual"),
    missing_expected_total = sum(issues$issue_type == "saknas_i_expected"),
    mismatches_total = sum(issues$issue_type == "avvikelse"),
    fatal = nrow(latest_issues) > 0 || (strict_history && nrow(historical_issues) > 0),
    stringsAsFactors = FALSE
  )

  message(sprintf(
    paste0(
      "Korsvalidering %s: %s jämförda rader, %s avvikelser totalt ",
      "(aktuell period: %s, historik: %s)."
    ),
    label,
    format(nrow(comparable), big.mark = " "),
    format(nrow(issues), big.mark = " "),
    format(nrow(latest_issues), big.mark = " "),
    format(nrow(historical_issues), big.mark = " ")
  ))

  if (nrow(historical_issues) > 0 && nrow(latest_issues) == 0) {
    message(
      "OBS: historiska skillnader finns mellan källorna men aktuell period ",
      latest_period,
      " är konsistent. Historiska skillnader sparas i valideringsrapporten."
    )
  }

  if (nrow(latest_issues) > 0) {
    example <- latest_issues[1, , drop = FALSE]
    message(
      "AKTUELL AVVIKELSE: ", label,
      "; period=", example$period,
      ", geo=", example$geo_code,
      ", kön=", example$sex,
      ", actual=", example$actual,
      ", expected=", example$expected,
      ", typ=", example$issue_type
    )
  }

  list(
    summary = summary,
    issues = issues |>
      mutate(label = label) |>
      select(
        label, period, geo_code, sex, issue_type,
        actual, expected, diff, is_latest
      )
  )
}

run_af_normalization_validation <- function() {
  strict_history <- af_env_flag("AF_VALIDATION_STRICT", FALSE)
  report_dir <- Sys.getenv(
    "AF_VALIDATION_REPORT_DIR",
    unset = "artifacts/af-validation"
  )
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

  message(
    "AF-validering: ",
    if (strict_history) "STRICT (historiska avvikelser blockerar)" else
      "NORMAL (endast aktuell period blockerar vid källskillnader)"
  )

  manifest <- af_discover_sources()
  common_period <- af_common_period(manifest)
  if (is.na(common_period)) {
    stop("AF-filerna visar inte samma period; validering avbryts.")
  }

  tmp <- tempfile("af-validation-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

  files <- af_download_sources(manifest, tmp)
  path_for <- function(key) files$path[match(key, files$source_key)][[1]]

  manifest_report <- files |>
    select(source_key, label, period, filename, url, sha256, bytes)

  utils::write.csv(
    manifest_report,
    file.path(report_dir, "source-manifest.csv"),
    row.names = FALSE,
    na = ""
  )

  for (i in seq_len(nrow(manifest_report))) {
    message(
      "Källfil: ", manifest_report$source_key[[i]],
      " | period=", manifest_report$period[[i]],
      " | bytes=", manifest_report$bytes[[i]],
      " | sha256=", manifest_report$sha256[[i]]
    )
  }

  message("Normaliserar web-sok-lan-kom ...")
  sok <- af_normalize_web_sok(path_for("arbetssokande"))

  message("Normaliserar tid utan arbete ...")
  tid <- af_normalize_tid_utan_arbete(
    path_for("tid_utan_arbete"),
    riket_path = path_for("tid_utan_arbete_riket")
  )

  message("Normaliserar svag konkurrensförmåga ...")
  svag <- af_normalize_svag_konkurrensformaga(path_for("svag_konkurrensformaga"))

  message("Normaliserar yrkesområde ...")
  yrke <- af_normalize_yrkesomrade(path_for("yrkesomrade"))

  message("Normaliserar BAS ...")
  bas <- af_normalize_bas(path_for("arbetskraft_bas"))

  datasets <- list(sok = sok, tid = tid, svag = svag, yrke = yrke, bas = bas)

  municipality_lookup <- af_get_municipality_codes()
  municipality_codes <- unique(unname(municipality_lookup))
  if (length(municipality_codes) != 290L) {
    stop("SCB:s kommunlista innehåller inte 290 kommuner")
  }

  structure_report <- list()

  for (nm in names(datasets)) {
    x <- datasets[[nm]]

    if (nrow(x) == 0) stop("Normaliseringen gav 0 rader för ", nm)
    if (any(is.na(x$period) | !nzchar(x$period))) stop(nm, " har saknad period")
    if (any(is.na(x$geo_code) | !nzchar(x$geo_code))) stop(nm, " har saknad geokod")
    if (all(is.na(x$value))) stop(nm, " har bara NA-värden")

    source_max_period <- max(as.character(x$period), na.rm = TRUE)
    if (!identical(source_max_period, common_period)) {
      stop(
        nm, " har maxperiod ", source_max_period,
        " men filnamnen anger gemensam period ", common_period
      )
    }

    latest <- x |>
      filter(period == common_period)

    if (nrow(latest) == 0) {
      stop(nm, " saknar rader för aktuell period ", common_period)
    }

    geo_counts_all <- x |>
      distinct(geo_code, geo_level) |>
      count(geo_level, name = "n_geographies")

    geo_counts_latest <- latest |>
      distinct(geo_code, geo_level) |>
      count(geo_level, name = "n_geographies")

    get_count <- function(tab, level) {
      value <- tab$n_geographies[tab$geo_level == level]
      if (length(value) == 0) 0L else as.integer(value[[1]])
    }

    municipality_count <- get_count(geo_counts_all, "kommun")
    county_count <- get_count(geo_counts_all, "län")
    riket_count <- get_count(geo_counts_all, "riket")

    municipality_count_latest <- get_count(geo_counts_latest, "kommun")
    county_count_latest <- get_count(geo_counts_latest, "län")
    riket_count_latest <- get_count(geo_counts_latest, "riket")

    if (municipality_count != 290L) {
      stop(nm, " innehåller inte samtliga 290 kommuner")
    }
    if (county_count != 21L) {
      stop(nm, " innehåller inte samtliga 21 län")
    }
    if (riket_count != 1L || !"00" %in% x$geo_code) {
      stop(nm, " saknar beräknad riksnivå")
    }

    if (municipality_count_latest != 290L) {
      stop(
        nm, " innehåller inte samtliga 290 kommuner i aktuell period ",
        common_period, " (", municipality_count_latest, ")"
      )
    }
    if (county_count_latest != 21L) {
      stop(
        nm, " innehåller inte samtliga 21 län i aktuell period ",
        common_period, " (", county_count_latest, ")"
      )
    }
    if (riket_count_latest != 1L || !"00" %in% latest$geo_code) {
      stop(nm, " saknar Riket i aktuell period ", common_period)
    }

    latest_riket_na <- sum(latest$geo_level == "riket" & is.na(latest$value))
    if (latest_riket_na > 0) {
      stop(
        nm, " har ", latest_riket_na,
        " NA-värden för Riket i aktuell period ", common_period
      )
    }

    approx_mb <- as.numeric(utils::object.size(x)) / 1024^2
    incomplete_riket <- sum(x$geo_level == "riket" & is.na(x$value))

    structure_report[[length(structure_report) + 1L]] <- data.frame(
      dataset = nm,
      rows = nrow(x),
      memory_mb = approx_mb,
      max_period = source_max_period,
      municipalities_all = municipality_count,
      counties_all = county_count,
      riket_all = riket_count,
      municipalities_latest = municipality_count_latest,
      counties_latest = county_count_latest,
      riket_latest = riket_count_latest,
      riket_na_all = incomplete_riket,
      riket_na_latest = latest_riket_na,
      stringsAsFactors = FALSE
    )

    message(sprintf(
      paste0(
        "%s: %s rader, %.1f MB; hela historiken 290 kommuner + 21 län + Riket; ",
        "%s: 290 kommuner + 21 län + Riket"
      ),
      nm,
      format(nrow(x), big.mark = " "),
      approx_mb,
      common_period
    ))

    if (incomplete_riket > 0) {
      message(sprintf(
        "%s: %s historiska riksrader är NA eftersom minst ett länsvärde saknas/maskeras; aktuell period har 0.",
        nm,
        format(incomplete_riket, big.mark = " ")
      ))
    }
  }

  structure_report <- bind_rows(structure_report)
  utils::write.csv(
    structure_report,
    file.path(report_dir, "structure-summary.csv"),
    row.names = FALSE,
    na = ""
  )

  total_rows <- sum(vapply(datasets, nrow, integer(1)))
  total_mb <- sum(vapply(
    datasets,
    function(x) as.numeric(utils::object.size(x)) / 1024^2,
    numeric(1)
  ))
  message(sprintf(
    "AF totalt efter normalisering: %s rader, cirka %.1f MB i R-minne.",
    format(total_rows, big.mark = " "),
    total_mb
  ))

  # Överlappande mått används som regressionskontroller.
  # Aktuell gemensam period måste matcha exakt. Historiska differenser mellan
  # separata AF-filer rapporteras eftersom AF kan revidera historiska uttag
  # oberoende av varandra utan att ändra YYYY-MM i filnamnet.
  tid_control <- af_control_tid_sex(path_for("tid_utan_arbete"))

  sok_control <- sok |>
    filter(
      geo_level == "kommun",
      dimension_type == "ålder",
      measure_code == "INSAL"
    ) |>
    group_by(period, geo_code, sex) |>
    summarise(actual = af_sum_complete(value), .groups = "drop")

  svag_control <- af_control_svag_samtliga(
    path_for("svag_konkurrensformaga")
  )

  yrke_control <- yrke |>
    filter(geo_level == "kommun") |>
    group_by(period, geo_code, sex) |>
    summarise(actual = af_sum_complete(value), .groups = "drop")

  bas_control <- af_control_bas_sok(path_for("arbetskraft_bas"))

  comparisons <- list(
    af_control_compare(
      sok_control,
      tid_control,
      "web-sok INSAL mot tid-filen ARBETSLÖSA",
      common_period,
      municipality_codes,
      strict_history
    ),
    af_control_compare(
      svag_control,
      tid_control,
      "svag konkurrensförmåga SAMTLIGA mot tid-filen ARBETSLÖSA",
      common_period,
      municipality_codes,
      strict_history
    ),
    af_control_compare(
      yrke_control,
      tid_control,
      "yrkesområden summerade mot tid-filen ARBETSLÖSA",
      common_period,
      municipality_codes,
      strict_history
    ),
    af_control_compare(
      bas_control,
      tid_control,
      "BAS-filens SOK-tal mot tid-filen ARBETSLÖSA",
      common_period,
      municipality_codes,
      strict_history
    )
  )

  control_summary <- bind_rows(lapply(comparisons, function(x) x$summary))
  control_issues <- bind_rows(lapply(comparisons, function(x) x$issues))

  utils::write.csv(
    control_summary,
    file.path(report_dir, "control-summary.csv"),
    row.names = FALSE,
    na = ""
  )
  utils::write.csv(
    control_issues,
    file.path(report_dir, "control-issues.csv"),
    row.names = FALSE,
    na = ""
  )

  if (!any(yrke$dimension_value == "Uppgift saknas")) {
    stop("Yrkesområdesfilen saknar förväntad kategori 'Uppgift saknas'")
  }

  if (!any(bas$measure_code == "TOTAK")) {
    stop("BAS-normaliseringen saknar TOTAK")
  }

  fatal_controls <- control_summary |>
    filter(fatal)

  if (nrow(fatal_controls) > 0) {
    labels <- paste(fatal_controls$label, collapse = "; ")
    stop(
      "AF-korsvalideringen misslyckades efter att samtliga kontroller körts. ",
      "Se artifact af-validation-report. Felande kontroller: ",
      labels
    )
  }

  message(
    "AF-normalisering godkänd för period ", common_period,
    ". Ingen data publicerades. Rapport: ", report_dir
  )
  invisible(datasets)
}

run_af_normalization_validation()
