# -------------------------------------------------------------------
# Kompetensarena Norrbotten - ETL E3
# -------------------------------------------------------------------
# Indikator:
# - E3: matchning mellan utbildning och yrke
#
# Källa:
# - SCB PxWeb2 TAB6929
#
# Geografi i första versionen:
# - län via kodlistan vs_CKM02Län
#
# Publicering:
# - chunkad ETL till Lovable Cloud
# -------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(tibble)
  library(pxweb2r)
})

source("R/etl/etl_api.R")

# ---- Inställningar ----

tabell_id <- "TAB6929"
indikator_id <- "e3-matchning-utbildning"
kalla <- "SCB"

# ---- Kontrollera metadata före datahämtning ----

state <- etl_get_state(indikator_id)
senast_lyckad <- state$last_successful_at %||% NA_character_

if (!is.na(senast_lyckad) && nzchar(senast_lyckad)) {
  behov_av_uppdatering <- pxweb2_table_needs_update(
    table = tabell_id,
    reference_datetime = senast_lyckad
  )

  if (isFALSE(behov_av_uppdatering)) {
    etl_log_no_change(indikator_id, kalla)
    message("TAB6929 har inte uppdaterats sedan senaste lyckade publicering.")
    quit(save = "no", status = 0)
  }

  if (is.na(behov_av_uppdatering)) {
    warning("SCB saknar användbar updated-timestamp för TAB6929; data hämtas för säkerhets skull.")
  }
}

# Första körningen, eller när SCB är nyare än vår senaste lyckade publicering:
# hämta metadata en gång och återanvänd den i datahämtningen.
meta <- pxweb2_get_metadata(tabell_id)
kalla_uppdaterad <- pxweb2_table_updated(meta)

kalla_uppdaterad_datum <- if (!is.na(kalla_uppdaterad) && nzchar(kalla_uppdaterad)) {
  substr(kalla_uppdaterad, 1, 10)
} else {
  NA_character_
}

# ---- Hämta data från SCB ----

query_e3 <- list(
  selection = list(
    list(variableCode = "ContentsCode", valueCodes = c("*")),
    list(variableCode = "Tid", valueCodes = c("*")),
    list(variableCode = "SNI2007", valueCodes = c("*")),
    list(
      variableCode = "KonAlderFodelseland",
      valueCodes = c("*"),
      codelist = "vs_KonCKMRMI"
    ),
    list(
      variableCode = "Region",
      valueCodes = c("*"),
      codelist = "vs_CKM02Län"
    ),
    list(
      variableCode = "Utbildning",
      valueCodes = c("*"),
      codelist = "vs_UtbildningsgruppE2-3N1-2"
    )
  ),
  placement = list(
    heading = c("ContentsCode", "Tid", "KonAlderFodelseland"),
    stub = c("SNI2007", "Region")
  )
)

df_e3 <- pxweb2_get_data(
  table = meta,
  query = query_e3,
  quiet = TRUE
)

if (is.null(df_e3) || nrow(df_e3) == 0) stop("SCB returnerade inga rader för E3")

# ---- Standardisera kolumnnamn ----

variabler <- pxweb2_get_variables(meta)

for (i in seq_len(nrow(variabler))) {
  code <- variabler$code[[i]]
  label <- variabler$label[[i]]
  if (!(code %in% names(df_e3)) && label %in% names(df_e3)) {
    names(df_e3)[names(df_e3) == label] <- code
  }
}

required_cols <- c(
  "ContentsCode", "Tid", "SNI2007",
  "KonAlderFodelseland", "Region", "Utbildning", "value"
)

missing_cols <- setdiff(required_cols, names(df_e3))
if (length(missing_cols) > 0) {
  stop("Saknade kolumner efter PxWeb2-hämtning: ", paste(missing_cols, collapse = ", "))
}

region_code_col <- names(df_e3)[grepl("region.*kod|region_kod", names(df_e3), ignore.case = TRUE)][1]
if (is.na(region_code_col) || is.null(region_code_col)) {
  stop("Ingen regionkodskolumn hittades i PxWeb2-resultatet")
}

# ---- Koder och etiketter för dimensioner ----

kodlistor <- pxweb2_get_values(
  meta,
  include_aggregations = c(
    KonAlderFodelseland = "vs_KonCKMRMI",
    Region = "vs_CKM02Län",
    Utbildning = "vs_UtbildningsgruppE2-3N1-2"
  ),
  quiet = TRUE
)

lookup_code <- function(variable, label, aggregation = FALSE) {
  x <- kodlistor[[variable]]
  if (is.null(x) || nrow(x) == 0) return(rep(NA_character_, length(label)))

  if (aggregation && "type" %in% names(x)) {
    x_agg <- x[tolower(x$type) == "aggregation", , drop = FALSE]
    if (nrow(x_agg) > 0) x <- x_agg
  } else if ("type" %in% names(x)) {
    x_var <- x[tolower(x$type) == "variable", , drop = FALSE]
    if (nrow(x_var) > 0) x <- x_var
  }

  map <- setNames(as.character(x$code), as.character(x$label))
  unname(map[as.character(label)])
}

df_e3 <- df_e3 |>
  mutate(
    geo_code = as.character(.data[[region_code_col]]),
    period = as.character(Tid),
    value = as.numeric(value),
    contents_code = lookup_code("ContentsCode", ContentsCode),
    sni2007_code = lookup_code("SNI2007", SNI2007),
    kon_alder_fodelseland_code = lookup_code(
      "KonAlderFodelseland",
      KonAlderFodelseland,
      aggregation = TRUE
    ),
    utbildning_code = lookup_code("Utbildning", Utbildning, aggregation = TRUE)
  )

# ---- Teknisk validering ----

if (any(is.na(df_e3$geo_code) | !nzchar(df_e3$geo_code))) {
  stop("E3 innehåller rader utan regionkod")
}

if (any(is.na(df_e3$period) | !nzchar(df_e3$period))) {
  stop("E3 innehåller rader utan period")
}

if (all(is.na(df_e3$value))) {
  stop("Alla E3-värden är NA")
}

dimension_code_cols <- c(
  "contents_code",
  "sni2007_code",
  "kon_alder_fodelseland_code",
  "utbildning_code"
)

for (col in dimension_code_cols) {
  if (any(is.na(df_e3[[col]]) | !nzchar(df_e3[[col]]))) {
    stop("Kunde inte mappa alla etiketter till stabila koder för dimensionen: ", col)
  }
}

key_df <- df_e3 |>
  transmute(
    geo_code,
    period,
    contents_code,
    sni2007_code,
    kon_alder_fodelseland_code,
    utbildning_code
  )

if (any(duplicated(key_df))) {
  stop("E3 innehåller dubbletter på observationsnyckeln")
}

# ---- Bygg observationspayload ----

observations <- map(seq_len(nrow(df_e3)), function(i) {
  row <- df_e3[i, , drop = FALSE]

  list(
    geo_code = row$geo_code[[1]],
    period = row$period[[1]],
    value = if (is.na(row$value[[1]])) NA_real_ else row$value[[1]],
    dimensions = list(
      contents_code = row$contents_code[[1]] %||% "",
      contents_label = as.character(row$ContentsCode[[1]]),
      sni2007_code = row$sni2007_code[[1]] %||% "",
      sni2007_label = as.character(row$SNI2007[[1]]),
      kon_alder_fodelseland_code = row$kon_alder_fodelseland_code[[1]] %||% "",
      kon_alder_fodelseland_label = as.character(row$KonAlderFodelseland[[1]]),
      utbildning_code = row$utbildning_code[[1]] %||% "",
      utbildning_label = as.character(row$Utbildning[[1]])
    )
  )
})

# ---- Publicera atomiskt ----

resultat <- etl_publish_batch(
  indicator_id = indikator_id,
  source = kalla,
  source_updated_date = kalla_uppdaterad_datum,
  observations = observations
)

message(
  sprintf(
    "E3 publicerad: %s rader (batch %s)",
    resultat$rows %||% length(observations),
    resultat$batch_id %||% "okänd"
  )
)
