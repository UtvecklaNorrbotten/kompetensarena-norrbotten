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

  municipality_raw <- af_clean_municipality_name(data[[municipality_col]])
  county_raw <- af_clean_county_name(data[[county_col]])
  municipality_present <- !is.na(municipality_raw) & nzchar(municipality_raw)
  county_known <- !is.na(unname(af_county_codes[county_raw]))

  municipality_non_geo <- af_is_non_geographic_municipality(municipality_raw)
  unmapped <- municipality_present & !municipality_non_geo & county_known & is.na(geo$geo_code)
  if (any(unmapped)) {
    examples <- unique(municipality_raw[unmapped])
    stop(
      "Kunde inte mappa kommunnamn till SCB-kod: ",
      paste(utils::head(examples, 10), collapse = ", "),
      if (length(examples) > 10) " ..." else ""
    )
  }

  bind_cols(data, geo) |>
    filter(!is.na(geo_code))
}


af_sum_complete <- function(x) {
  if (length(x) == 0L || any(is.na(x))) return(NA_real_)
  sum(x)
}

af_period_matches <- function(value, period = NULL) {
  if (is.null(period) || length(period) == 0L || is.na(period) || !nzchar(period)) {
    return(TRUE)
  }
  identical(as.character(value), as.character(period))
}

af_add_riket_from_counties <- function(data) {
  required <- c("geo_code", "geo_level", "value")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop("Kan inte skapa Riket; saknade kolumner: ", paste(missing, collapse = ", "))
  }

  counties <- data |>
    filter(geo_level == "län")

  if (nrow(counties) == 0) {
    stop("Kan inte skapa Riket; datasetet saknar länsrader")
  }

  group_cols <- setdiff(names(data), c("geo_code", "geo_level", "value"))

  riket <- counties |>
    group_by(across(all_of(group_cols))) |>
    summarise(
      county_count = n_distinct(geo_code),
      value = if (n_distinct(geo_code) == 21L) af_sum_complete(value) else NA_real_,
      .groups = "drop"
    ) |>
    select(-county_count) |>
    mutate(
      geo_code = "00",
      geo_level = "riket"
    ) |>
    select(all_of(names(data)))

  bind_rows(data, riket)
}

af_normalize_web_sok <- function(path, period = NULL) {
  caches <- list(
    list(id = 3L, dimension_type = "ålder", dimension_field = "ALDGR"),
    list(id = 2L, dimension_type = "födelseland", dimension_field = "FODLGRP"),
    list(id = 1L, dimension_type = "utbildningsnivå", dimension_field = "UTBILDNING")
  )

  municipality_codes <- af_get_municipality_codes()

  bind_rows(lapply(caches, function(cfg) {
    fields <- c(
      "PERIOD", "KOEN", "LAN", "KOMMUN_BESKR",
      cfg$dimension_field, "INSAL"
    )

    # Läs hela cachen. För den här källan behövs även restkategorierna
    # "Uppgift saknas" för att läns- och rikssummor ska bli exakta.
    raw <- af_read_pivot_cache(
      path,
      cache_id = cfg$id,
      keep_fields = fields,
      row_filter = function(row) {
        af_period_matches(row[["PERIOD"]], period)
      }
    ) |>
      mutate(
        county_name = af_clean_county_name(LAN),
        municipality_name = af_clean_municipality_name(KOMMUN_BESKR),
        county_code = unname(af_county_codes[county_name]),
        municipality_code = unname(municipality_codes[municipality_name]),
        value = suppressWarnings(as.numeric(INSAL)),
        dimension_value = as.character(.data[[cfg$dimension_field]])
      )

    # Verkliga kommuner publiceras som kommunnivå. Restkategorier utan
    # kommunkod publiceras inte som kommun men får ingå i läns-/rikssumman.
    municipalities <- raw |>
      filter(!is.na(county_code), !is.na(municipality_code)) |>
      group_by(PERIOD, municipality_code, KOEN, dimension_value) |>
      summarise(value = af_sum_complete(value), .groups = "drop") |>
      transmute(
        period = PERIOD,
        geo_code = municipality_code,
        geo_level = "kommun",
        sex = KOEN,
        dimension_type = cfg$dimension_type,
        dimension_value,
        measure_code = "INSAL",
        measure_label = "Inskrivna arbetslösa",
        value
      )

    # Län byggs från alla rader med känt län, inklusive kommun = Uppgift saknas.
    # Därmed tappar vi inte individer vars län är känt men kommun saknas.
    counties <- raw |>
      filter(!is.na(county_code)) |>
      group_by(PERIOD, county_code, KOEN, dimension_value) |>
      summarise(value = af_sum_complete(value), .groups = "drop") |>
      transmute(
        period = PERIOD,
        geo_code = county_code,
        geo_level = "län",
        sex = KOEN,
        dimension_type = cfg$dimension_type,
        dimension_value,
        measure_code = "INSAL",
        measure_label = "Inskrivna arbetslösa",
        value
      )

    # Riket byggs från samtliga råa rader, även LAN = Uppgift saknas.
    # Det ger exakt rikstotal utan att fördela okänd geografi på ett län.
    riket <- raw |>
      group_by(PERIOD, KOEN, dimension_value) |>
      summarise(value = af_sum_complete(value), .groups = "drop") |>
      transmute(
        period = PERIOD,
        geo_code = "00",
        geo_level = "riket",
        sex = KOEN,
        dimension_type = cfg$dimension_type,
        dimension_value,
        measure_code = "INSAL",
        measure_label = "Inskrivna arbetslösa",
        value
      )

    bind_rows(municipalities, counties, riket)
  }))
}

af_find_column <- function(data, candidates, required = TRUE) {
  hit <- candidates[candidates %in% names(data)][1]
  if (length(hit) == 0 || is.na(hit)) {
    if (required) {
      stop("Hittade ingen av kolumnerna: ", paste(candidates, collapse = ", "))
    }
    return(NULL)
  }
  hit
}

af_tid_sheet_specs <- list(
  list(sheet = "Total", dimension_type = "totalt", dimension_candidates = NULL),
  list(sheet = "Kön", dimension_type = "kön", dimension_candidates = c("KOEN", "KÖN")),
  list(sheet = "Ålder", dimension_type = "ålder", dimension_candidates = c("ALDER", "ÅLDER")),
  list(
    sheet = "Utbildningsnivå",
    dimension_type = "utbildningsnivå",
    dimension_candidates = c("UTBILDNINGSNIVÅ", "UTBILDNING")
  ),
  list(
    sheet = "Födelseland",
    dimension_type = "födelseland",
    dimension_candidates = c("FÖDELSELAND", "FODLGRP")
  )
)

af_tid_value_fields <- c(
  "Utan arbete mer än 6 månader",
  "Utan arbete mer än 12 månader",
  "Utan arbete mer än 24 månader"
)

af_normalize_tid_riket <- function(path, period = NULL) {
  raw <- af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c(
      "PERIOD", "KOEN", "ALDGR", "FH", "FLAND", "UTBILDNING",
      "INSAL", "UA06", "UA12", "UA24"
    ),
    row_filter = function(row) {
      af_period_matches(row[["PERIOD"]], period)
    }
  ) |>
    mutate(
      INSAL = suppressWarnings(as.numeric(INSAL)),
      UA06 = suppressWarnings(as.numeric(UA06)),
      UA12 = suppressWarnings(as.numeric(UA12)),
      UA24 = suppressWarnings(as.numeric(UA24))
    )

  measure_map <- c(
    UA06 = "Utan arbete mer än 6 månader",
    UA12 = "Utan arbete mer än 12 månader",
    UA24 = "Utan arbete mer än 24 månader"
  )

  make_rows <- function(data, dimension_type, dimension_field = NULL) {
    group_fields <- c("PERIOD", dimension_field)
    group_fields <- group_fields[!is.na(group_fields) & nzchar(group_fields)]

    grouped <- data |>
      group_by(across(all_of(group_fields))) |>
      summarise(
        UA06 = sum(UA06, na.rm = TRUE),
        UA12 = sum(UA12, na.rm = TRUE),
        UA24 = sum(UA24, na.rm = TRUE),
        .groups = "drop"
      )

    if (is.null(dimension_field)) {
      grouped$dimension_value <- "Totalt"
    } else {
      grouped$dimension_value <- as.character(grouped[[dimension_field]])
    }

    grouped |>
      select(PERIOD, dimension_value, UA06, UA12, UA24) |>
      pivot_longer(
        cols = c(UA06, UA12, UA24),
        names_to = "measure_code",
        values_to = "value"
      ) |>
      mutate(
        measure_label = unname(measure_map[measure_code])
      ) |>
      transmute(
        period = as.character(PERIOD),
        geo_code = "00",
        geo_level = "riket",
        sex = if (dimension_type == "kön") dimension_value else NA_character_,
        dimension_type,
        dimension_value,
        measure_code,
        measure_label,
        value = as.numeric(value)
      )
  }

  bind_rows(
    make_rows(raw, "totalt"),
    make_rows(raw, "kön", "KOEN"),
    make_rows(raw, "ålder", "ALDGR"),
    make_rows(raw, "utbildningsnivå", "UTBILDNING"),
    make_rows(raw, "födelseland", "FLAND")
  )
}

af_normalize_tid_utan_arbete <- function(path, riket_path = NULL, period = NULL) {
  municipality_codes <- af_get_municipality_codes()

  regional <- bind_rows(lapply(af_tid_sheet_specs, function(cfg) {
    raw <- readxl::read_excel(path, sheet = cfg$sheet, skip = 4)

    period_col <- af_find_column(raw, c("PERIOD", "Period"))
    county_col <- af_find_column(raw, c("LÄN", "LAN"))
    municipality_col <- af_find_column(raw, c("KOMMUN", "KOM"))
    dimension_col <- if (is.null(cfg$dimension_candidates)) {
      NULL
    } else {
      af_find_column(raw, cfg$dimension_candidates)
    }

    if (!is.null(period)) {
      raw <- raw[as.character(raw[[period_col]]) == as.character(period), , drop = FALSE]
    }

    missing_values <- setdiff(af_tid_value_fields, names(raw))
    if (length(missing_values) > 0) {
      stop(
        cfg$sheet, " saknar kolumner: ",
        paste(missing_values, collapse = ", ")
      )
    }

    county_name <- af_clean_county_name(raw[[county_col]])
    municipality_name <- af_clean_municipality_name(raw[[municipality_col]])
    county_code <- unname(af_county_codes[county_name])
    municipality_code <- unname(municipality_codes[municipality_name])

    municipality_non_geo <- af_is_non_geographic_municipality(municipality_name)
    municipality_present <- !is.na(municipality_name) & nzchar(municipality_name)
    real_unmapped <- (
      !is.na(county_code) &
      municipality_present &
      !municipality_non_geo &
      is.na(municipality_code)
    )

    if (any(real_unmapped)) {
      examples <- unique(municipality_name[real_unmapped])
      stop(
        cfg$sheet, ": kunde inte mappa kommunnamn till SCB-kod: ",
        paste(utils::head(examples, 10), collapse = ", "),
        if (length(examples) > 10) " ..." else ""
      )
    }

    raw$county_code_internal <- county_code
    raw$municipality_code_internal <- municipality_code
    raw$is_county_residual_internal <- (
      !is.na(county_code) & municipality_non_geo
    )
    raw$dimension_value <- if (is.null(dimension_col)) {
      "Totalt"
    } else {
      as.character(raw[[dimension_col]])
    }

    long <- raw |>
      filter(
        !is.na(county_code_internal) &
          (!is.na(municipality_code_internal) | is_county_residual_internal)
      ) |>
      transmute(
        period = as.character(.data[[period_col]]),
        county_code = county_code_internal,
        municipality_code = municipality_code_internal,
        is_county_residual = is_county_residual_internal,
        dimension_value,
        across(all_of(af_tid_value_fields))
      ) |>
      pivot_longer(
        cols = all_of(af_tid_value_fields),
        names_to = "measure_label",
        values_to = "value_raw"
      ) |>
      mutate(
        dimension_type = cfg$dimension_type,
        sex = if (cfg$dimension_type == "kön") dimension_value else NA_character_,
        measure_code = case_when(
          measure_label == af_tid_value_fields[[1]] ~ "KUA06",
          measure_label == af_tid_value_fields[[2]] ~ "KUA12",
          measure_label == af_tid_value_fields[[3]] ~ "KUA24",
          TRUE ~ NA_character_
        ),
        value = suppressWarnings(as.numeric(value_raw))
      )

    municipalities <- long |>
      filter(!is.na(municipality_code)) |>
      group_by(
        period, municipality_code, sex, dimension_type, dimension_value,
        measure_code, measure_label
      ) |>
      summarise(value = af_sum_complete(value), .groups = "drop") |>
      transmute(
        period,
        geo_code = municipality_code,
        geo_level = "kommun",
        sex,
        dimension_type,
        dimension_value,
        measure_code,
        measure_label,
        value
      )

    counties <- long |>
      group_by(
        period, county_code, sex, dimension_type, dimension_value,
        measure_code, measure_label
      ) |>
      summarise(
        value = af_sum_complete(value),
        .groups = "drop"
      ) |>
      transmute(
        period,
        geo_code = county_code,
        geo_level = "län",
        sex,
        dimension_type,
        dimension_value,
        measure_code,
        measure_label,
        value
      )

    bind_rows(municipalities, counties)
  }))

  if (is.null(riket_path)) {
    return(regional)
  }

  bind_rows(regional, af_normalize_tid_riket(riket_path, period = period))
}

af_normalize_svag_konkurrensformaga <- function(path, period = NULL) {
  municipality_codes <- af_get_municipality_codes()

  raw <- af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c(
      "PERIOD", "KOEN", "LAN_BESKR", "KOMMUN_BESKR",
      "KUA06", "KUA12", "KUA24", "UTSATTA"
    ),
    row_filter = function(row) {
      af_period_matches(row[["PERIOD"]], period)
    }
  ) |>
    mutate(
      county_name = af_clean_county_name(LAN_BESKR),
      municipality_name = af_clean_municipality_name(KOMMUN_BESKR),
      county_code = unname(af_county_codes[county_name]),
      municipality_code = unname(municipality_codes[municipality_name]),
      UTSATTA = suppressWarnings(as.numeric(UTSATTA))
    )

  add_measure <- function(data, measure_code, measure_label) {
    municipalities <- data |>
      filter(!is.na(county_code), !is.na(municipality_code)) |>
      group_by(PERIOD, municipality_code, KOEN) |>
      summarise(value = af_sum_complete(UTSATTA), .groups = "drop") |>
      transmute(
        period = PERIOD,
        geo_code = municipality_code,
        geo_level = "kommun",
        sex = KOEN,
        dimension_type = "kön",
        dimension_value = KOEN,
        measure_code = measure_code,
        measure_label = measure_label,
        value
      )

    counties <- data |>
      filter(!is.na(county_code)) |>
      group_by(PERIOD, county_code, KOEN) |>
      summarise(value = af_sum_complete(UTSATTA), .groups = "drop") |>
      transmute(
        period = PERIOD,
        geo_code = county_code,
        geo_level = "län",
        sex = KOEN,
        dimension_type = "kön",
        dimension_value = KOEN,
        measure_code = measure_code,
        measure_label = measure_label,
        value
      )

    riket <- data |>
      group_by(PERIOD, KOEN) |>
      summarise(value = af_sum_complete(UTSATTA), .groups = "drop") |>
      transmute(
        period = PERIOD,
        geo_code = "00",
        geo_level = "riket",
        sex = KOEN,
        dimension_type = "kön",
        dimension_value = KOEN,
        measure_code = measure_code,
        measure_label = measure_label,
        value
      )

    bind_rows(municipalities, counties, riket)
  }

  bind_rows(
    add_measure(raw, "UTSATTA_TOTAL", "Svag konkurrensförmåga"),
    add_measure(
      raw |> filter(KUA06 == "Ja"),
      "UTSATTA_KUA06",
      "Svag konkurrensförmåga, utan arbete >6 månader"
    ),
    add_measure(
      raw |> filter(KUA12 == "Ja"),
      "UTSATTA_KUA12",
      "Svag konkurrensförmåga, utan arbete >12 månader"
    ),
    add_measure(
      raw |> filter(KUA24 == "Ja"),
      "UTSATTA_KUA24",
      "Svag konkurrensförmåga, utan arbete >24 månader"
    )
  )
}

af_normalize_yrkesomrade <- function(path, period = NULL) {
  municipality_codes <- af_get_municipality_codes()

  raw <- af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c("PERIOD", "KÖN", "YRKESOMRÅDE", "LÄN", "KOMMUN", "KVAR"),
    row_filter = function(row) {
      af_period_matches(row[["PERIOD"]], period)
    }
  ) |>
    mutate(
      county_name = af_clean_county_name(LÄN),
      municipality_name = af_clean_municipality_name(KOMMUN),
      county_code = unname(af_county_codes[county_name]),
      municipality_code = unname(municipality_codes[municipality_name]),
      dimension_value = ifelse(
        is.na(YRKESOMRÅDE) | !nzchar(YRKESOMRÅDE),
        "Uppgift saknas",
        YRKESOMRÅDE
      ),
      value = suppressWarnings(as.numeric(KVAR))
    )

  municipalities <- raw |>
    filter(!is.na(county_code), !is.na(municipality_code)) |>
    group_by(PERIOD, municipality_code, KÖN, dimension_value) |>
    summarise(value = af_sum_complete(value), .groups = "drop") |>
    transmute(
      period = PERIOD,
      geo_code = municipality_code,
      geo_level = "kommun",
      sex = KÖN,
      dimension_type = "yrkesområde",
      dimension_value,
      measure_code = "KVAR",
      measure_label = "Inskrivna arbetslösa",
      value
    )

  # Blanka kommuner i yrkesfilen är restposter, inte länstotaler.
  # De ska ingå i länssumman när länet är känt men aldrig publiceras som kommun.
  counties <- raw |>
    filter(!is.na(county_code)) |>
    group_by(PERIOD, county_code, KÖN, dimension_value) |>
    summarise(value = af_sum_complete(value), .groups = "drop") |>
    transmute(
      period = PERIOD,
      geo_code = source_county_code,
      geo_level = "län",
      sex = KÖN,
      dimension_type = "yrkesområde",
      dimension_value,
      measure_code = "KVAR",
      measure_label = "Inskrivna arbetslösa",
      value
    )

  riket <- raw |>
    group_by(PERIOD, KÖN, dimension_value) |>
    summarise(value = af_sum_complete(value), .groups = "drop") |>
    transmute(
      period = PERIOD,
      geo_code = "00",
      geo_level = "riket",
      sex = KÖN,
      dimension_type = "yrkesområde",
      dimension_value,
      measure_code = "KVAR",
      measure_label = "Inskrivna arbetslösa",
      value
    )

  bind_rows(municipalities, counties, riket)
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

af_normalize_bas <- function(path, period = NULL) {
  fields <- c("PERIOD", "LAN", "KOM", af_bas_measure_map$measure_code)

  raw <- af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = fields,
    row_filter = function(row) {
      af_period_matches(row[["PERIOD"]], period) &&
        af_keep_geo(row[["LAN"]], row[["KOM"]])
    }
  ) |>
    af_add_geo("LAN", "KOM") |>
    filter(geo_level == "kommun") |>
    mutate(
      source_county_code = unname(af_county_codes[af_clean_county_name(LAN)])
    )

  long <- raw |>
    select(
      PERIOD, geo_code, source_county_code,
      all_of(af_bas_measure_map$measure_code)
    ) |>
    pivot_longer(
      cols = all_of(af_bas_measure_map$measure_code),
      names_to = "measure_code",
      values_to = "value"
    ) |>
    left_join(af_bas_measure_map, by = "measure_code") |>
    transmute(
      period = PERIOD,
      geo_code,
      source_county_code,
      sex,
      dimension_type,
      dimension_value,
      measure_code,
      measure_label = "Arbetskraft BAS",
      value = suppressWarnings(as.numeric(value))
    )

  # Kommun-ID är stabilt över tid. Om samma kommun förekommer under två län
  # i en historisk övergång (t.ex. Heby) kollapsas delraderna till en kommunrad.
  # Om någon del är sekretessmarkerad/NA blir kommunvärdet NA i stället för att
  # vi låtsas känna den exakta summan.
  municipalities <- long |>
    group_by(
      period, geo_code, sex, dimension_type, dimension_value,
      measure_code, measure_label
    ) |>
    summarise(value = af_sum_complete(value), .groups = "drop") |>
    mutate(geo_level = "kommun") |>
    select(
      period, geo_code, geo_level, sex, dimension_type, dimension_value,
      measure_code, measure_label, value
    )

  # Län följer källans länstillhörighet för respektive historisk period.
  counties <- long |>
    filter(!is.na(source_county_code)) |>
    group_by(
      period, source_county_code, sex, dimension_type, dimension_value,
      measure_code, measure_label
    ) |>
    summarise(value = af_sum_complete(value), .groups = "drop") |>
    transmute(
      period,
      geo_code = source_county_code,
      geo_level = "län",
      sex,
      dimension_type,
      dimension_value,
      measure_code,
      measure_label,
      value
    )

  bind_rows(municipalities, counties) |>
    af_add_riket_from_counties()
}

# ---- Korsvalideringsunderlag (importeras inte som egna produktionsmått) ----

af_control_tid_sex <- function(path, period = NULL) {
  raw <- readxl::read_excel(path, sheet = "Kön", skip = 4)
  required <- c("PERIOD", "LÄN", "KOMMUN", "KOEN", "ARBETSLÖSA")
  missing <- setdiff(required, names(raw))
  if (length(missing) > 0) {
    stop("Kön-bladet saknar kontrollkolumner: ", paste(missing, collapse = ", "))
  }

  if (!is.null(period)) {
    raw <- raw[as.character(raw$PERIOD) == as.character(period), , drop = FALSE]
  }

  af_add_geo(raw, "LÄN", "KOMMUN") |>
    transmute(
      period = as.character(PERIOD),
      geo_code,
      sex = as.character(KOEN),
      expected = suppressWarnings(as.numeric(ARBETSLÖSA))
    ) |>
    group_by(period, geo_code, sex) |>
    summarise(expected = af_sum_complete(expected), .groups = "drop")
}

af_control_web_sok_total_by_sex <- function(path, period = NULL) {
  # Ålderscachen partitionerar de arbetslösa i åldersgrupper. Summan INSAL
  # per period/geografi/kön ska därför motsvara ARBETSLÖSA i tid-filen.
  af_read_pivot_cache(
    path,
    cache_id = 3L,
    keep_fields = c("PERIOD", "KOEN", "LAN", "KOMMUN_BESKR", "ALDGR", "INSAL"),
    row_filter = function(row) {
      af_period_matches(row[["PERIOD"]], period) &&
        af_keep_geo(row[["LAN"]], row[["KOMMUN_BESKR"]])
    }
  ) |>
    af_add_geo("LAN", "KOMMUN_BESKR") |>
    mutate(INSAL = suppressWarnings(as.numeric(INSAL))) |>
    group_by(PERIOD, geo_code, KOEN) |>
    summarise(actual = af_sum_complete(INSAL), .groups = "drop") |>
    transmute(period = PERIOD, geo_code, sex = KOEN, actual)
}

af_control_svag_samtliga <- function(path, period = NULL) {
  af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c(
      "PERIOD", "KOEN", "LAN_BESKR", "KOMMUN_BESKR",
      "KUA06", "KUA12", "KUA24", "SAMTLIGA"
    ),
    row_filter = function(row) {
      af_period_matches(row[["PERIOD"]], period) &&
        af_keep_geo(row[["LAN_BESKR"]], row[["KOMMUN_BESKR"]])
    }
  ) |>
    af_add_geo("LAN_BESKR", "KOMMUN_BESKR") |>
    mutate(SAMTLIGA = suppressWarnings(as.numeric(SAMTLIGA))) |>
    group_by(PERIOD, geo_code, KOEN) |>
    summarise(actual = af_sum_complete(SAMTLIGA), .groups = "drop") |>
    transmute(period = PERIOD, geo_code, sex = KOEN, actual)
}

af_control_yrkesomrade_total <- function(path, period = NULL) {
  af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c("PERIOD", "KÖN", "YRKESOMRÅDE", "LÄN", "KOMMUN", "KVAR"),
    row_filter = function(row) {
      af_period_matches(row[["PERIOD"]], period) &&
        af_keep_geo(row[["LÄN"]], row[["KOMMUN"]])
    }
  ) |>
    af_add_geo("LÄN", "KOMMUN") |>
    mutate(KVAR = suppressWarnings(as.numeric(KVAR))) |>
    group_by(PERIOD, geo_code, `KÖN`) |>
    summarise(actual = af_sum_complete(KVAR), .groups = "drop") |>
    transmute(period = PERIOD, geo_code, sex = `KÖN`, actual)
}

af_control_bas_sok <- function(path, period = NULL) {
  raw <- af_read_pivot_cache(
    path,
    cache_id = 1L,
    keep_fields = c("PERIOD", "LAN", "KOM", "KVISOK", "MANSOK"),
    row_filter = function(row) {
      af_period_matches(row[["PERIOD"]], period) &&
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
  ) |>
    group_by(period, geo_code, sex) |>
    summarise(actual = af_sum_complete(actual), .groups = "drop")
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
