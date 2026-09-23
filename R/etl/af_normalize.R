# Normalisering av Arbetsförmedlingens fem primära månadsfiler.
# Kanoniskt format är långt. Denna modul publicerar inte data; den används först
# för strukturell validering och korskontroller.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readxl)
})

source("R/etl/af_geography.R")
source("R/etl/af_pivot_cache.R")

af_add_geo <- function(data, county_col, municipality_col) {
  geo <- af_geo_from_names(data[[county_col]], data[[municipality_col]])
  bind_cols(data, geo) |>
    filter(!is.na(geo_code))
}

af_normalize_web_sok <- function(path) {
  caches <- list(
    list(id = 3L, dimension_type = "ålder", dimension_field = "ALDGR"),
    list(id = 2L, dimension_type = "födelseland", dimension_field = "FODLGRP"),
    list(id = 1L, dimension_type = "utbildningsnivå", dimension_field = "UTBILDNING")
  )

  bind_rows(lapply(caches, function(cfg) {
    fields <- c(
      "PERIOD", "KOEN", "LAN", "KOMMUN_BESKR",
      cfg$dimension_field, "INSAL"
    )

    raw <- af_read_pivot_cache(
      path,
      cache_id = cfg$id,
      keep_fields = fields,
      row_filter = function(row) {
        af_keep_geo(row[["LAN"]], row[["KOMMUN_BESKR"]])
      }
    )

    af_add_geo(raw, "LAN", "KOMMUN_BESKR") |>
      transmute(
        period = PERIOD,
        geo_code,
        geo_level,
        sex = KOEN,
        dimension_type = cfg$dimension_type,
        dimension_value = .data[[cfg$dimension_field]],
        measure_code = "INSAL",
        measure_label = "Inskrivna arbetslösa",
        value = suppressWarnings(as.numeric(INSAL))
      )
  }))
}

af_normalize_tid_utan_arbete <- function(path) {
  sheet_specs <- list(
    list(sheet = "Total", dimension_type = "totalt", dimension_field = NULL),
    list(sheet = "Kön", dimension_type = "kön", dimension_field = "KOEN"),
    list(sheet = "Ålder", dimension_type = "ålder", dimension_field = "ALDER"),
    list(sheet = "Utbildningsnivå", dimension_type = "utbildningsnivå", dimension_field = "UTBILDNINGSNIVÅ"),
    list(sheet = "Födelseland", dimension_type = "födelseland", dimension_field = "FÖDELSELAND")
  )

  value_fields <- c(
    "Utan arbete mer än 6 månader",
    "Utan arbete mer än 12 månader",
    "Utan arbete mer än 24 månader"
  )

  bind_rows(lapply(sheet_specs, function(cfg) {
    raw <- readxl::read_excel(path, sheet = cfg$sheet, skip = 4)
    required <- c("PERIOD", "LÄN", "KOMMUN", "ARBETSLÖSA", value_fields)
    if (!is.null(cfg$dimension_field)) required <- c(required, cfg$dimension_field)
    missing <- setdiff(required, names(raw))
    if (length(missing) > 0) {
      stop(cfg$sheet, " saknar kolumner: ", paste(missing, collapse = ", "))
    }

    raw <- af_add_geo(raw, "LÄN", "KOMMUN")
    raw$dimension_value <- if (is.null(cfg$dimension_field)) {
      "Totalt"
    } else {
      as.character(raw[[cfg$dimension_field]])
    }

    raw |>
      select(
        PERIOD, geo_code, geo_level, dimension_value,
        all_of(value_fields)
      ) |>
      pivot_longer(
        cols = all_of(value_fields),
        names_to = "measure_label",
        values_to = "value"
      ) |>
      mutate(
        dimension_type = cfg$dimension_type,
        measure_code = case_when(
          measure_label == value_fields[[1]] ~ "KUA06",
          measure_label == value_fields[[2]] ~ "KUA12",
          measure_label == value_fields[[3]] ~ "KUA24",
          TRUE ~ NA_character_
        )
      ) |>
      transmute(
        period = as.character(PERIOD),
        geo_code,
        geo_level,
        sex = if (cfg$dimension_type == "kön") dimension_value else NA_character_,
        dimension_type,
        dimension_value,
        measure_code,
        measure_label,
        value = suppressWarnings(as.numeric(value))
      )
  }))
}

af_normalize_svag_konkurrensformaga <- function(path) {
  raw <- af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c(
      "PERIOD", "KOEN", "LAN_BESKR", "KOMMUN_BESKR",
      "KUA06", "KUA12", "KUA24", "UTSATTA"
    ),
    row_filter = function(row) {
      af_keep_geo(row[["LAN_BESKR"]], row[["KOMMUN_BESKR"]])
    }
  ) |>
    af_add_geo("LAN_BESKR", "KOMMUN_BESKR") |>
    mutate(UTSATTA = suppressWarnings(as.numeric(UTSATTA)))

  base <- raw |>
    group_by(PERIOD, geo_code, geo_level, KOEN) |>
    summarise(value = sum(UTSATTA, na.rm = TRUE), .groups = "drop") |>
    mutate(measure_code = "UTSATTA_TOTAL", measure_label = "Svag konkurrensförmåga")

  durations <- bind_rows(
    raw |> filter(KUA06 == "Ja") |> mutate(measure_code = "UTSATTA_KUA06", measure_label = "Svag konkurrensförmåga, utan arbete >6 månader"),
    raw |> filter(KUA12 == "Ja") |> mutate(measure_code = "UTSATTA_KUA12", measure_label = "Svag konkurrensförmåga, utan arbete >12 månader"),
    raw |> filter(KUA24 == "Ja") |> mutate(measure_code = "UTSATTA_KUA24", measure_label = "Svag konkurrensförmåga, utan arbete >24 månader")
  ) |>
    group_by(PERIOD, geo_code, geo_level, KOEN, measure_code, measure_label) |>
    summarise(value = sum(UTSATTA, na.rm = TRUE), .groups = "drop")

  bind_rows(base, durations) |>
    transmute(
      period = PERIOD,
      geo_code,
      geo_level,
      sex = KOEN,
      dimension_type = "kön",
      dimension_value = KOEN,
      measure_code,
      measure_label,
      value
    )
}

af_normalize_yrkesomrade <- function(path) {
  af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c("PERIOD", "KÖN", "YRKESOMRÅDE", "LÄN", "KOMMUN", "KVAR"),
    row_filter = function(row) {
      af_keep_geo(row[["LÄN"]], row[["KOMMUN"]])
    }
  ) |>
    af_add_geo("LÄN", "KOMMUN") |>
    transmute(
      period = PERIOD,
      geo_code,
      geo_level,
      sex = KÖN,
      dimension_type = "yrkesområde",
      dimension_value = ifelse(
        is.na(YRKESOMRÅDE) | !nzchar(YRKESOMRÅDE),
        "Uppgift saknas",
        YRKESOMRÅDE
      ),
      measure_code = "KVAR",
      measure_label = "Inskrivna arbetslösa",
      value = suppressWarnings(as.numeric(KVAR))
    )
}

af_bas_measure_map <- data.frame(
  measure_code = c(
    "TOTAK", "KVIAK", "MANAK",
    "UNGAK", "UNGKAK", "UNGMAK",
    "GAMAK", "GAMKAK", "GAMMAK",
    "INRAK", "INRKAK", "INRMAK",
    "UTRAK", "UTRKAK", "UTRMAK",
    "FGAK", "FGKAK", "FGMAK",
    "GYAK", "GYKAK", "GYMAK",
    "EGAK", "EGKAK", "EGMAK"
  ),
  dimension_type = c(
    rep("totalt", 3),
    rep("ålder", 6),
    rep("födelseland", 6),
    rep("utbildningsnivå", 9)
  ),
  dimension_value = c(
    "Totalt", "Totalt", "Totalt",
    "18-24", "18-24", "18-24",
    "55-64", "55-64", "55-64",
    "Inrikesfödda", "Inrikesfödda", "Inrikesfödda",
    "Utrikesfödda", "Utrikesfödda", "Utrikesfödda",
    "Förgymnasial", "Förgymnasial", "Förgymnasial",
    "Gymnasial", "Gymnasial", "Gymnasial",
    "Eftergymnasial", "Eftergymnasial", "Eftergymnasial"
  ),
  sex = rep(c(NA, "K", "M"), 8),
  stringsAsFactors = FALSE
)

af_normalize_bas <- function(path) {
  fields <- c("PERIOD", "LAN", "KOM", af_bas_measure_map$measure_code)

  raw <- af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = fields,
    row_filter = function(row) {
      af_keep_geo(row[["LAN"]], row[["KOM"]])
    }
  ) |>
    af_add_geo("LAN", "KOM")

  raw |>
    select(PERIOD, geo_code, geo_level, all_of(af_bas_measure_map$measure_code)) |>
    pivot_longer(
      cols = all_of(af_bas_measure_map$measure_code),
      names_to = "measure_code",
      values_to = "value"
    ) |>
    left_join(af_bas_measure_map, by = "measure_code") |>
    transmute(
      period = PERIOD,
      geo_code,
      geo_level,
      sex,
      dimension_type,
      dimension_value,
      measure_code,
      measure_label = "Arbetskraft BAS",
      value = suppressWarnings(as.numeric(value))
    )
}


# ---- Korsvalideringsunderlag (importeras inte som egna produktionsmått) ----

af_control_tid_sex <- function(path) {
  raw <- readxl::read_excel(path, sheet = "Kön", skip = 4)
  required <- c("PERIOD", "LÄN", "KOMMUN", "KOEN", "ARBETSLÖSA")
  missing <- setdiff(required, names(raw))
  if (length(missing) > 0) {
    stop("Kön-bladet saknar kontrollkolumner: ", paste(missing, collapse = ", "))
  }

  af_add_geo(raw, "LÄN", "KOMMUN") |>
    transmute(
      period = as.character(PERIOD),
      geo_code,
      sex = as.character(KOEN),
      expected = suppressWarnings(as.numeric(ARBETSLÖSA))
    )
}

af_control_web_sok_total_by_sex <- function(path) {
  # Ålderscachen partitionerar de arbetslösa i åldersgrupper. Summan INSAL
  # per period/geografi/kön ska därför motsvara ARBETSLÖSA i tid-filen.
  af_read_pivot_cache(
    path,
    cache_id = 3L,
    keep_fields = c("PERIOD", "KOEN", "LAN", "KOMMUN_BESKR", "ALDGR", "INSAL"),
    row_filter = function(row) {
      af_keep_geo(row[["LAN"]], row[["KOMMUN_BESKR"]])
    }
  ) |>
    af_add_geo("LAN", "KOMMUN_BESKR") |>
    mutate(INSAL = suppressWarnings(as.numeric(INSAL))) |>
    group_by(PERIOD, geo_code, KOEN) |>
    summarise(actual = sum(INSAL, na.rm = TRUE), .groups = "drop") |>
    transmute(period = PERIOD, geo_code, sex = KOEN, actual)
}

af_control_svag_samtliga <- function(path) {
  af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c(
      "PERIOD", "KOEN", "LAN_BESKR", "KOMMUN_BESKR",
      "KUA06", "KUA12", "KUA24", "SAMTLIGA"
    ),
    row_filter = function(row) {
      af_keep_geo(row[["LAN_BESKR"]], row[["KOMMUN_BESKR"]])
    }
  ) |>
    af_add_geo("LAN_BESKR", "KOMMUN_BESKR") |>
    mutate(SAMTLIGA = suppressWarnings(as.numeric(SAMTLIGA))) |>
    group_by(PERIOD, geo_code, KOEN) |>
    summarise(actual = sum(SAMTLIGA, na.rm = TRUE), .groups = "drop") |>
    transmute(period = PERIOD, geo_code, sex = KOEN, actual)
}

af_control_yrkesomrade_total <- function(path) {
  af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c("PERIOD", "KÖN", "YRKESOMRÅDE", "LÄN", "KOMMUN", "KVAR"),
    row_filter = function(row) {
      af_keep_geo(row[["LÄN"]], row[["KOMMUN"]])
    }
  ) |>
    af_add_geo("LÄN", "KOMMUN") |>
    mutate(KVAR = suppressWarnings(as.numeric(KVAR))) |>
    group_by(PERIOD, geo_code, `KÖN`) |>
    summarise(actual = sum(KVAR, na.rm = TRUE), .groups = "drop") |>
    transmute(period = PERIOD, geo_code, sex = `KÖN`, actual)
}

af_control_bas_sok <- function(path) {
  raw <- af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c("PERIOD", "LAN", "KOM", "KVISOK", "MANSOK"),
    row_filter = function(row) {
      af_keep_geo(row[["LAN"]], row[["KOM"]])
    }
  ) |>
    af_add_geo("LAN", "KOM")

  bind_rows(
    raw |>
      transmute(
        period = PERIOD, geo_code, sex = "K",
        actual = suppressWarnings(as.numeric(KVISOK))
      ),
    raw |>
      transmute(
        period = PERIOD, geo_code, sex = "M",
        actual = suppressWarnings(as.numeric(MANSOK))
      )
  )
}

af_assert_control_match <- function(actual, expected, label, tolerance = 1e-8) {
  check <- inner_join(actual, expected, by = c("period", "geo_code", "sex")) |>
    filter(!is.na(actual), !is.na(expected))

  if (nrow(check) == 0) {
    stop("Korsvalideringen gav inga jämförbara rader: ", label)
  }

  bad <- check |>
    mutate(diff = abs(actual - expected)) |>
    filter(diff > tolerance)

  if (nrow(bad) > 0) {
    example <- bad[1, , drop = FALSE]
    stop(
      label, " avviker. Första fel: period=", example$period,
      ", geo=", example$geo_code, ", kön=", example$sex,
      ", actual=", example$actual, ", expected=", example$expected
    )
  }

  message(sprintf(
    "Korsvalidering OK: %s (%s jämförda rader)",
    label,
    format(nrow(check), big.mark = " ")
  ))

  invisible(TRUE)
}
