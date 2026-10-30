# -------------------------------------------------------------------
# Kompetensarena Norrbotten - ETL UKA
# -------------------------------------------------------------------
# Källa:
# - UKÄ, Högskolan i siffror
#
# Regler:
# - hela Sverige: Riket + lärosäten
# - indikatorpolicy: ursprungliga sju = fem år/aktiva lärosäten, 77/134/135 = hela historiken
# - om Kvinnor/Män finns sparas Kvinnor, Män och Total
# - om endast Total finns används det tekniskt men könsdimensionen lagras inte
# - alla erbjudna åldersgrupper hämtas; totalvärdet lagras utan åldersdimension
# - full snapshot per indikator gör att äldre perioder/lärosäten rensas
# -------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(httr2)
  library(jsonlite)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
})

source("R/etl/etl_api.R")

# ---- Inställningar ----

uka_base <- "https://statistik-www.uka.se/export"
uka_api <- "https://statistik-api.uka.se/api/totals"
source_id <- "uka-hogskolan-i-siffror"
source_name <- "UKÄ"

uka_indicators <- tribble(
  ~uka_id, ~indicator_id, ~label,
  13L,  "uka-forstahandssokande-yrkesprogram", "Förstahandssökande till yrkesexamensprogram",
  31L,  "uka-nyborjare-yrkesprogram",          "Nybörjare på yrkesexamensprogram",
  33L,  "uka-hst",                             "Helårsstudenter",
  97L,  "uka-antagna-yrkesprogram",            "Antagna till yrkesexamensprogram",
  99L,  "uka-soktryck-yrkesprogram",           "Söktryck till yrkesexamensprogram",
  108L, "uka-examinerade",                     "Examinerade",
  136L, "uka-etablering",                      "Etablering på arbetsmarknaden",
  77L,  "uka-kvarvaro-hogskolenyborjare",         "Kvarvaro termin 3 för högskolenybörjare",
  134L, "uka-kvarvaro-program",                  "Kvarvaro termin 3 på program",
  135L, "uka-examensfrekvens",                   "Examensfrekvens på program"
) |>
  mutate(
    retention_years = if_else(uka_id %in% c(77L, 134L, 135L), NA_integer_, 5L),
    active_years = if_else(uka_id %in% c(77L, 134L, 135L), NA_integer_, 3L)
  )

selected_indicator <- Sys.getenv("UKA_INDICATOR", unset = "all")
test_mode <- tolower(Sys.getenv("ETL_TEST_MODE", unset = "false")) %in% c("1", "true", "yes")

if (!selected_indicator %in% c("all", "api")) {
  uka_indicators <- uka_indicators |>
    filter(as.character(uka_id) == selected_indicator | indicator_id == selected_indicator)
  if (nrow(uka_indicators) == 0L) stop("Okänd UKÄ-indikator: ", selected_indicator)
}

# ---- HTTP-hjälpare ----

uka_request <- function(url) {
  request(url) |>
    req_user_agent("Kompetensarena-Norrbotten-UKA-ETL/1.0") |>
    req_headers("Accept" = "*/*") |>
    req_timeout(180) |>
    req_retry(
      max_tries = 5,
      retry_on_failure = TRUE,
      is_transient = function(resp) resp_status(resp) %in% c(408L, 429L, 500L, 502L, 503L, 504L)
    )
}

uka_get_text <- function(url) {
  uka_request(url) |>
    req_perform() |>
    resp_body_string()
}

uka_indicator_meta <- function(uka_id) {
  body <- uka_request(sprintf("%s/%s/", uka_api, uka_id)) |>
    req_perform() |>
    resp_body_json(simplifyVector = TRUE)

  body$indicator
}

uka_filter_html <- function(uka_id, endpoint) {
  indicator_json <- jsonlite::toJSON(as.character(uka_id), auto_unbox = FALSE)
  separator <- if (str_detect(endpoint, fixed("?"))) "&" else "?"
  url <- paste0(
    uka_base, "/filters/", endpoint, separator,
    "indicator=", URLencode(indicator_json, reserved = TRUE)
  )
  uka_get_text(url)
}

extract_values <- function(html, prefix) {
  values <- str_match_all(html, "value=[\"']([^\"']+)[\"']")[[1]][, 2]
  values[str_starts(values, prefix)]
}

extract_options <- function(html, prefix) {
  m <- str_match_all(
    html,
    "<option[^>]*value=[\"']([^\"']+)[\"'][^>]*name=[\"']([^\"']*)[\"'][^>]*>"
  )[[1]]
  if (nrow(m) == 0L) return(tibble(value = character(), name = character()))
  tibble(value = m[, 2], name = m[, 3]) |>
    filter(str_starts(value, prefix))
}

extract_dynamic_groups <- function(html) {
  marks <- str_locate_all(html, "dynamic-filter-index[\"']>\\s*([^<]+)")[[1]]
  if (nrow(marks) == 0L) return(list())

  matches <- str_match_all(html, "dynamic-filter-index[\"']>\\s*([^<]+)")[[1]]
  out <- vector("list", nrow(marks))

  for (i in seq_len(nrow(marks))) {
    marker_start <- marks[i, "start"]
    block_start <- str_locate_all(str_sub(html, 1, marker_start), "<div class=[\"']groupTitles")[[1]]
    block_start <- if (nrow(block_start)) tail(block_start[, "start"], 1) else marker_start

    if (i < nrow(marks)) {
      next_marker <- marks[i + 1L, "start"]
      next_block <- str_locate_all(str_sub(html, 1, next_marker), "<div class=[\"']groupTitles")[[1]]
      block_end <- if (nrow(next_block)) tail(next_block[, "start"], 1) - 1L else next_marker - 1L
    } else {
      block_end <- str_length(html)
    }

    block <- str_sub(html, block_start, block_end)
    index <- str_trim(matches[i, 2])
    title_match <- str_match(
      block,
      "dynamic-filter-index[\"']>\\s*[^<]+</span>\\s*([^<]+)"
    )
    title <- if (!is.na(title_match[1, 2])) str_trim(title_match[1, 2]) else ""
    values <- extract_values(block, "dynamic:")

    out[[i]] <- list(index = index, title = title, values = values)
  }

  out
}

period_type <- function(period_value) {
  p <- str_remove(period_value, "^from:")
  if (str_starts(p, "HT") || str_starts(p, "VT")) return("semester")
  if (str_detect(p, fixed("/"))) return("academic_year")
  "calendar_year"
}

retained_periods <- function(from_values, years) {
  n <- if (period_type(from_values[[1]]) == "semester") years * 2L else years
  if (is.na(years)) return(from_values)
  head(from_values, n)
}

uka_export <- function(uka_id, from_value, to_value, universities, genders, ages, dynamic_filters) {
  filters <- c(
    from_value,
    to_value,
    universities,
    genders,
    ages,
    dynamic_filters
  )

  response <- request(paste0(uka_base, "/api/index.php")) |>
    req_user_agent("Kompetensarena-Norrbotten-UKA-ETL/1.0") |>
    req_headers(
      "Accept" = "application/json",
      "X-Requested-With" = "XMLHttpRequest"
    ) |>
    req_body_form(
      indicator = as.character(uka_id),
      `filters[]` = filters,
      .multi = "explode"
    ) |>
    req_timeout(300) |>
    req_retry(
      max_tries = 5,
      retry_on_failure = TRUE,
      is_transient = function(resp) resp_status(resp) %in% c(408L, 429L, 500L, 502L, 503L, 504L)
    ) |>
    req_perform() |>
    resp_body_json(simplifyVector = TRUE)

  if (is.null(response$fileUrl) || !nzchar(response$fileUrl)) {
    stop("UKÄ-exporten returnerade ingen fileUrl för indikator ", uka_id)
  }

  raw <- uka_request(response$fileUrl) |>
    req_timeout(600) |>
    req_perform() |>
    resp_body_raw()

  read_delim(
    I(raw),
    delim = ";",
    locale = locale(decimal_mark = ",", encoding = "UTF-8"),
    show_col_types = FALSE,
    name_repair = "minimal",
    trim_ws = TRUE
  )
}

# ---- Normalisering ----

clean_period <- function(x) {
  x |>
    as.character() |>
    str_remove('^="') |>
    str_remove('"$')
}

source("R/etl/uka_values.R")

dimension_code <- function(x) {
  x |>
    iconv(to = "ASCII//TRANSLIT") |>
    tolower() |>
    str_replace_all("[^a-z0-9]+", "-") |>
    str_replace_all("(^-|-$)", "")
}

normalize_uka <- function(df, uka_id, store_gender, store_age = FALSE) {
  names(df) <- names(df) |>
    str_replace_all("\\[0\\]$", "") |>
    str_replace_all("\\[1\\]$", "") |>
    str_replace_all("\\[2\\]$", "")

  if (!all(c("Tidsperiod", "Lärosäte", "Kön", "Värde") %in% names(df))) {
    stop("UKÄ ", uka_id, ": oväntade CSV-kolumner: ", paste(names(df), collapse = ", "))
  }

  df <- df |>
    mutate(
      period = clean_period(Tidsperiod),
      university_name = if_else(is.na(Lärosäte) | Lärosäte == "", "Riket", Lärosäte),
      gender = if (store_gender) as.character(Kön) else NA_character_,
      value = clean_value(Värde)
    )

  if (store_gender) {
    df <- df |>
      filter(gender %in% c("Kvinnor", "Män", "Total"))
  }

  if (store_age) {
    if (!"Åldersgrupp" %in% names(df)) stop("UKÄ ", uka_id, ": ålderskolumn saknas")
    age <- trimws(as.character(df$Åldersgrupp))
    if (anyNA(age) || any(!age %in% c("", "Total", "Totalt", "Totala värdet", "-24", "25-34", "35-"))) {
      stop("UKÄ ", uka_id, ": oväntad åldersgrupp")
    }
    # Totalraden bevaras som en egen observation utan ålder, aldrig som summa av grupper.
    df$aldersgrupp <- ifelse(age %in% c("", "Total", "Totalt", "Totala värdet"), NA_character_, age)
  }
  df <- df |>
    select(-any_of(c("Tidsperiod", "Lärosäte", "Kön", "Värde", "Åldersgrupp")))

  # Dimensionskolumner från UKÄ utöver period/lärosäte/kön/värde.
  dimension_cols <- setdiff(
    names(df),
    c("period", "university_name", "gender", "value")
  )

  df |>
    mutate(across(all_of(dimension_cols), ~ na_if(as.character(.x), "")))
}

# ---- Aktivt lärosätesurval ----

active_universities <- function(uka_id, from_values, university_html, gender_values, age_total, dynamic_groups) {
  recent <- retained_periods(from_values, 3L)
  from3 <- tail(recent, 1)
  to3 <- str_replace(head(recent, 1), "^from:", "to:")

  university_values <- extract_values(university_html, "uni:")
  total_dynamic <- unlist(map(dynamic_groups, function(g) {
    total <- g$values[g$values == "dynamic:TOTAL"]
    if (length(total) == 0L) total <- head(g$values, 1)
    paste0(g$index, total)
  }), use.names = FALSE)

  probe <- uka_export(
    uka_id = uka_id,
    from_value = from3,
    to_value = to3,
    universities = university_values,
    genders = gender_values,
    ages = age_total,
    dynamic_filters = total_dynamic
  )

  active_names <- probe |>
    transmute(name = if_else(is.na(Lärosäte) | Lärosäte == "", "Riket", as.character(Lärosäte))) |>
    distinct() |>
    pull(name)

  options <- extract_options(university_html, "uni:")
  active_values <- options |>
    filter(name %in% active_names) |>
    pull(value)

  # Riket ska alltid följa med.
  unique(c("uni:1", active_values))
}

# Kontroller före start av en ersättande snapshot.
validate_uka_observations <- function(observations, uka_id, has_age_breakdown) {
  if (!length(observations)) stop("Tom UKÄ-källa")
  keys <- vapply(observations, function(o) {
    dims <- o$dimensions %||% list()
    jsonlite::toJSON(list(o$period, o$university, o$gender, dims[sort(names(dims))]), auto_unbox = TRUE)
  }, character(1))
  if (anyDuplicated(keys)) stop("Dubblett i UKÄ-observationer")
  if (!any(vapply(observations, function(o) o$university == "Luleå tekniska universitet", logical(1)))) stop("LTU saknas")
  ages <- vapply(observations, function(o) o$dimensions$aldersgrupp %||% "Total", character(1))
  if (has_age_breakdown && !all(c("Total", "-24", "25-34", "35-") %in% ages)) stop("Åldersgrupper eller total saknas")
  if (!has_age_breakdown && any(ages != "Total")) stop("Oväntad åldersuppdelning")
  # Varje kombination av period/lärosäte/kön/övriga dimensioner måste ha en källtotal.
  age_keys <- vapply(observations, function(o) {
    dims <- o$dimensions %||% list(); dims$aldersgrupp <- NULL
    if (!length(dims)) dims <- list()  # samma JSON-form som en total utan dimensionsnycklar
    jsonlite::toJSON(list(o$period, o$university, o$gender, dims[sort(names(dims))]), auto_unbox = TRUE)
  }, character(1))
  if (length(setdiff(age_keys, age_keys[ages == "Total"]))) stop("Ålderstotal saknas för en observationsgrupp")
  for (o in observations) {
    if (!is.null(o$value) && !is.na(o$value) && (!is.finite(o$value) || o$value < 0 ||
        (uka_id %in% c(77L, 134L, 135L, 136L) && o$value > 100))) stop("Orimligt UKÄ-värde")
  }
  invisible(TRUE)
}

# ---- Bygg observationspayload ----

build_observations <- function(df) {
  dimension_cols <- setdiff(
    names(df),
    c("period", "university_name", "gender", "value")
  )

  lapply(seq_len(nrow(df)), function(i) {
    dims <- list()

    for (col in dimension_cols) {
      value <- df[[col]][[i]]
      if (!is.null(value) && !is.na(value) && nzchar(as.character(value))) {
        dims[[dimension_code(col)]] <- as.character(value)
      }
    }

    observation <- list(
      period = df$period[[i]],
      university = df$university_name[[i]],
      value = df$value[[i]]
    )

    if (!is.na(df$gender[[i]]) && nzchar(df$gender[[i]])) {
      observation$gender <- df$gender[[i]]
    }

    if (length(dims) > 0L) {
      observation$dimensions <- dims
    }

    observation
  })
}

uka_etl_request <- function(path) {
  etl_request(paste0("/api/public/jobs/uka/", path))
}

uka_publish_batch <- function(indicator_id, source, source_updated_date, observations) {
  chunks <- etl_split_observations(observations, max_rows = 5000L)
  if (length(chunks) == 0L) stop("Inga UKÄ-observationer att publicera")

  start <- uka_etl_request("start") |>
    req_method("POST") |>
    req_body_json(
      c(list(
        indicator_id = indicator_id,
        source = source,
        expected_chunks = length(chunks),
        expected_rows = length(observations)
      ), if (!is.null(source_updated_date)) list(kalla_uppdaterad_datum = source_updated_date)),
      auto_unbox = TRUE,
      null = "null"
    ) |>
    etl_perform_json()

  batch_id <- start$batch_id
  if (is.null(batch_id) || !nzchar(batch_id)) stop("UKÄ-start returnerade inget batch_id")

  ok <- FALSE
  on.exit({
    if (!ok) {
      try(
        uka_etl_request("abort") |>
          req_method("POST") |>
          req_body_json(
            list(batch_id = batch_id, reason = "R-jobbet avbröts före lyckad finalisering"),
            auto_unbox = TRUE
          ) |>
          etl_perform_json(retry_safe = TRUE),
        silent = TRUE
      )
    }
  }, add = TRUE)

  for (i in seq_along(chunks)) {
    uka_etl_request("chunk") |>
      req_method("POST") |>
      req_body_json(
        list(
          batch_id = batch_id,
          indicator_id = indicator_id,
          chunk_index = i - 1L,
          observations = chunks[[i]]
        ),
        auto_unbox = TRUE,
        null = "null",
        na = "null",
        digits = NA
      ) |>
      etl_perform_json(retry_safe = TRUE, timeout = 180)

    message(sprintf("UKÄ %s: publicerade chunk %d/%d", indicator_id, i, length(chunks)))
  }

  result <- uka_etl_request("finalize") |>
    req_method("POST") |>
    req_body_json(list(batch_id = batch_id), auto_unbox = TRUE) |>
    etl_perform_json(retry_safe = TRUE, timeout = 180)

  if (!identical(as.numeric(result$rows), as.numeric(length(observations)))) stop("UKÄ: publicerat radantal avviker")
  ok <- TRUE
  result
}

# ---- Kör indikator ----

run_uka_indicator <- function(uka_id, indicator_id, label, retention_years, active_years) {
  message("\n--- UKÄ ", uka_id, ": ", label, " ---")

  meta <- uka_indicator_meta(uka_id)
  from_html <- uka_filter_html(uka_id, "academic_term.php?direction=from")
  to_html <- uka_filter_html(uka_id, "academic_term.php?direction=to")
  university_html <- uka_filter_html(uka_id, "university.php")
  gender_html <- uka_filter_html(uka_id, "gender.php")
  age_html <- uka_filter_html(uka_id, "age.php")
  group_html <- uka_filter_html(uka_id, "group.php")

  from_values <- extract_values(from_html, "from:")
  to_values <- extract_values(to_html, "to:")
  gender_values <- extract_values(gender_html, "gender:")
  age_values <- extract_values(age_html, "age:")
  dynamic_groups <- extract_dynamic_groups(group_html)

  if (length(from_values) == 0L || length(to_values) == 0L) {
    stop("UKÄ ", uka_id, ": saknar periodfilter")
  }

  # Kön:
  # - finns Kvinnor och Män sparas Kvinnor, Män och Total (om Total finns)
  # - finns bara Total används den tekniskt i hämtningen men lagras inte som dimension
  has_gender_breakdown <- all(c("gender:Kvinnor", "gender:Män") %in% gender_values)

  if (has_gender_breakdown) {
    gender_keep <- gender_values[
      gender_values %in% c("gender:Kvinnor", "gender:Män", "gender:Total")
    ]
  } else {
    gender_keep <- gender_values[gender_values == "gender:Total"]
    if (length(gender_keep) == 0L) gender_keep <- gender_values
  }

  # Samma åldersregel för alla API-indikatorer. Total ingår alltid i begäran.
  age_total <- age_values[age_values %in% c("age:1", "age:Total")]
  if (length(age_total) != 1L) stop("UKÄ ", uka_id, ": verifierbart ålderstotalfilter saknas")
  has_age_breakdown <- any(!age_values %in% age_total)
  periods_keep <- retained_periods(from_values, retention_years)
  from_keep <- tail(periods_keep, 1)
  to_keep <- str_replace(head(periods_keep, 1), "^from:", "to:")

  universities <- if (is.na(active_years)) {
    extract_values(university_html, "uni:")
  } else {
    active_universities(uka_id, from_values, university_html, gender_keep, age_total, dynamic_groups)
  }

  dynamic_filters <- unlist(
    map(dynamic_groups, ~ paste0(.x$index, .x$values)),
    use.names = FALSE
  )

  raw <- uka_export(
    uka_id = uka_id,
    from_value = from_keep,
    to_value = to_keep,
    universities = universities,
    genders = gender_keep,
    ages = age_values,
    dynamic_filters = dynamic_filters
  )

  data <- normalize_uka(raw, uka_id, store_gender = has_gender_breakdown, store_age = has_age_breakdown)

  if (nrow(data) == 0L) stop("UKÄ ", uka_id, ": inga rader efter filtrering")

  if (has_gender_breakdown) {
    invalid_gender <- setdiff(unique(stats::na.omit(data$gender)), c("Kvinnor", "Män", "Total"))
    if (length(invalid_gender) > 0L) {
      stop("UKÄ ", uka_id, ": oväntade könsvärden: ", paste(invalid_gender, collapse = ", "))
    }
  } else if (any(!is.na(data$gender))) {
    stop("UKÄ ", uka_id, ": könsdimension lagrades trots att endast Total finns")
  }
  if ("Åldersgrupp" %in% names(data)) {
    stop("UKÄ ", uka_id, ": ålderskolumnen har inte normaliserats")
  }

  expected_periods <- str_remove(periods_keep, "^from:")
  unexpected <- setdiff(unique(data$period), expected_periods)
  if (length(unexpected) > 0L) stop("UKÄ ", uka_id, ": oväntade perioder: ", paste(unexpected, collapse = ", "))
  observations <- build_observations(data)
  validate_uka_observations(observations, uka_id, has_age_breakdown)

  message(sprintf(
    "UKÄ %s: %s rader, %d perioder, %d lärosäten + Riket",
    uka_id,
    format(nrow(data), big.mark = " "),
    length(unique(data$period)),
    max(0L, length(unique(data$university_name)) - 1L)
  ))

  if (test_mode) {
    message("Testläge: publicerar inte UKÄ ", uka_id)
    return(invisible(list(rows = nrow(data), periods = sort(unique(data$period)))))
  }

  result <- uka_publish_batch(
    indicator_id = indicator_id,
    source = source_name,
    source_updated_date = NULL,
    observations = observations
  )

  message(sprintf(
    "UKÄ %s publicerad: %s rader",
    uka_id,
    format(result$rows %||% nrow(data), big.mark = " ")
  ))

  invisible(result)
}

# ---- Kör alla valda indikatorer ----
run_uka_sync <- function() {
  results <- pmap(uka_indicators, run_uka_indicator)
  if (!test_mode) {
    latest <- max(vapply(uka_indicators$uka_id, function(id) {
      as.character(uka_indicator_meta(id)$current_year %||% "")
    }, character(1)))
    etl_update_source_state(
      source_id = source_id, status = "succeeded",
      latest_available_period = latest, latest_successful_period = latest,
      details = list(
        indicators = uka_indicators$uka_id,
        policies = uka_indicators |> select(uka_id, retention_years, active_years),
        gender_rule = "Kvinnor/Män/Total om uppdelning finns; annars ingen könsdimension",
        age_rule = "Alla erbjudna grupper; källans ålderstotal lagras utan åldersdimension",
        age_stored = TRUE
      )
    )
  }
  invisible(results)
}

if (Sys.getenv("UKA_LOAD_ONLY") != "true") run_uka_sync()
