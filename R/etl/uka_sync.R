# -------------------------------------------------------------------
# Kompetensarena Norrbotten - ETL UKA
# -------------------------------------------------------------------
# Källa:
# - UKÄ, Högskolan i siffror
#
# Regler:
# - hela Sverige: Riket + lärosäten
# - exakt senaste 5 år (10 terminer för terminsdata)
# - lärosäten måste ha förekommit under senaste 3 år
# - endast Kön = Kvinnor/Män; Total lagras aldrig
# - ålder hämtas endast som tekniskt Total-filter och lagras aldrig
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
  136L, "uka-etablering",                      "Etablering på arbetsmarknaden"
)

selected_indicator <- Sys.getenv("UKA_INDICATOR", unset = "all")
test_mode <- tolower(Sys.getenv("ETL_TEST_MODE", unset = "false")) %in% c("1", "true", "yes")

if (selected_indicator != "all") {
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
  uka_request(sprintf("%s/%s/", uka_api, uka_id)) |>
    req_perform() |>
    resp_body_json(simplifyVector = TRUE) |>
    ((x) x$indicator)()
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
  head(from_values, n)
}

uka_export <- function(uka_id, from_value, to_value, universities, genders, age_total, dynamic_filters) {
  filters <- c(
    from_value,
    to_value,
    universities,
    genders,
    age_total,
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
      `filters[]` = filters
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

clean_value <- function(x) {
  x <- as.character(x)
  x[x %in% c("", "..", ".", "-", "NA")] <- NA_character_
  readr::parse_number(x, locale = locale(decimal_mark = ",", grouping_mark = " "))
}

dimension_code <- function(x) {
  x |>
    iconv(to = "ASCII//TRANSLIT") |>
    tolower() |>
    str_replace_all("[^a-z0-9]+", "-") |>
    str_replace_all("(^-|-$)", "")
}

normalize_uka <- function(df, uka_id) {
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
      gender = as.character(Kön),
      value = clean_value(Värde)
    ) |>
    filter(gender %in% c("Kvinnor", "Män")) |>
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
    age_total = age_total,
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

# ---- Bygg observationspayload ----

build_observations <- function(df) {
  dimension_cols <- setdiff(
    names(df),
    c("period", "university_name", "gender", "value")
  )

  lapply(seq_len(nrow(df)), function(i) {
    dims <- list(
      university = df$university_name[[i]],
      gender = df$gender[[i]]
    )

    for (col in dimension_cols) {
      value <- df[[col]][[i]]
      if (!is.null(value) && !is.na(value) && nzchar(as.character(value))) {
        dims[[dimension_code(col)]] <- as.character(value)
      }
    }

    list(
      geo_code = "00",
      period = df$period[[i]],
      value = df$value[[i]],
      dimensions = dims
    )
  })
}

# ---- Kör indikator ----

run_uka_indicator <- function(uka_id, indicator_id, label) {
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

  # Kön: endast kvinnor/män. Total ska aldrig lagras.
  gender_keep <- gender_values[gender_values %in% c("gender:Kvinnor", "gender:Män")]
  if (length(gender_keep) == 0L) {
    # Om en framtida indikator saknar könsuppdelning används dess enda tekniska värde,
    # men könsdimensionen tas senare bort om CSV:n inte innehåller Kvinnor/Män.
    gender_keep <- gender_values
  }

  # Ålder: endast tekniskt Total-värde, dimensionen lagras aldrig.
  age_total <- age_values[age_values %in% c("age:1", "age:Total")]
  if (length(age_values) > 0L && length(age_total) == 0L) age_total <- tail(age_values, 1)

  periods5 <- retained_periods(from_values, 5L)
  from5 <- tail(periods5, 1)
  to5 <- str_replace(head(periods5, 1), "^from:", "to:")

  universities <- active_universities(
    uka_id = uka_id,
    from_values = from_values,
    university_html = university_html,
    gender_values = gender_keep,
    age_total = age_total,
    dynamic_groups = dynamic_groups
  )

  dynamic_filters <- unlist(
    map(dynamic_groups, ~ paste0(.x$index, .x$values)),
    use.names = FALSE
  )

  raw <- uka_export(
    uka_id = uka_id,
    from_value = from5,
    to_value = to5,
    universities = universities,
    genders = gender_keep,
    age_total = age_total,
    dynamic_filters = dynamic_filters
  )

  data <- normalize_uka(raw, uka_id)

  if (nrow(data) == 0L) stop("UKÄ ", uka_id, ": inga rader efter filtrering")

  # Kön=Total får aldrig finnas kvar.
  if (any(data$gender == "Total", na.rm = TRUE)) {
    stop("UKÄ ", uka_id, ": Kön=Total finns kvar efter normalisering")
  }
  if ("Åldersgrupp" %in% names(data)) {
    stop("UKÄ ", uka_id, ": åldersdimensionen har inte tagits bort")
  }

  # Högst fem år / tio terminer enligt faktisk UKÄ-periodtyp.
  expected_periods <- str_remove(periods5, "^from:")
  unexpected <- setdiff(unique(data$period), expected_periods)
  if (length(unexpected) > 0L) {
    stop("UKÄ ", uka_id, ": oväntade perioder: ", paste(unexpected, collapse = ", "))
  }

  observations <- build_observations(data)

  message(sprintf(
    "UKÄ %s: %s rader, %d perioder, %d aktiva lärosäten + Riket",
    uka_id,
    format(nrow(data), big.mark = " "),
    length(unique(data$period)),
    max(0L, length(unique(data$university_name)) - 1L)
  ))

  if (test_mode) {
    message("Testläge: publicerar inte UKÄ ", uka_id)
    return(invisible(list(rows = nrow(data), periods = sort(unique(data$period)))))
  }

  result <- etl_publish_batch(
    indicator_id = indicator_id,
    source = source_name,
    source_updated_date = as.character(Sys.Date()),
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

results <- pmap(
  uka_indicators,
  function(uka_id, indicator_id, label) {
    run_uka_indicator(uka_id, indicator_id, label)
  }
)

if (!test_mode) {
  latest <- max(vapply(uka_indicators$uka_id, function(id) {
    as.character(uka_indicator_meta(id)$current_year %||% "")
  }, character(1)))

  try(
    etl_update_source_state(
      source_id = source_id,
      status = "succeeded",
      latest_available_period = latest,
      latest_successful_period = latest,
      details = list(
        indicators = uka_indicators$uka_id,
        retention_years = 5,
        active_institution_years = 3,
        gender = c("Kvinnor", "Män"),
        age_stored = FALSE
      )
    ),
    silent = TRUE
  )
}
