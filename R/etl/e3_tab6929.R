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
source("R/etl/scb_common.R")

# ---- Inställningar ----

tabell_id <- "TAB6929"
indikator_id <- "e3-matchning-utbildning"
test_indikator_id <- "e3-matchning-utbildning-etl-test"
kalla <- "SCB"
test_mode <- tolower(Sys.getenv("ETL_TEST_MODE", unset = "false")) %in% c("1", "true", "yes")
finalize_test_mode <- tolower(Sys.getenv("ETL_TEST_FINALIZE", unset = "false")) %in% c("1", "true", "yes")

if (test_mode && finalize_test_mode) {
  stop("Välj antingen ETL_TEST_MODE eller ETL_TEST_FINALIZE, inte båda.")
}

# En finaliseringstest använder en separat admin-indikator. Därmed kan den
# pröva hela versionsväxlingen utan att blockera den efterföljande fullimporten.
target_indikator_id <- if (finalize_test_mode) test_indikator_id else indikator_id

# ---- Kontrollera metadata före datahämtning ----

run_state <- scb_prepare_run(
  indicator_id = target_indikator_id,
  table_id = tabell_id,
  source = kalla,
  skip_update_check = finalize_test_mode
)

if (!isTRUE(run_state$fetch)) {
  message("TAB6929 har inte uppdaterats sedan senaste lyckade publicering.")
  quit(save = "no", status = 0)
}

meta <- run_state$meta
kalla_uppdaterad_datum <- run_state$updated_date

# ---- Hämta data från SCB ----

# PxWeb2-kodlistorna är Valueset-listor. Läs ut deras faktiska koder innan
# dataanropet så att pxweb2r kan validera och dela upp den stora frågan korrekt.
kon_codes <- scb_get_codelist_codes("vs_KonCKMRMI")
region_codes <- scb_get_codelist_codes("vs_CKM02Län")
utbildning_codes <- scb_get_codelist_codes("vs_UtbildningsgruppE2-3N1-2")

contents_codes <- list("*")
tid_codes <- list("*")
sni_codes <- list("*")

if (test_mode) {
  kon_codes <- if ("totalt" %in% kon_codes) "totalt" else kon_codes[[1]]
  utbildning_codes <- head(utbildning_codes, 2)
  contents_codes <- list("000008QV")
  tid_codes <- list(tail(names(meta$dimension$Tid$category$index), 1))
  sni_codes <- list("A-U")

  message("ETL-testläge: 21 län, 2 utbildningsgrupper, 1 näringsgren, 1 mått och senaste år.")
} else if (finalize_test_mode) {
  # Begränsa bara utbildningsdimensionen. Övriga dimensioner är riktiga
  # TAB6929-data så testet omfattar flera chunkar och den nya finaliseringen.
  utbildning_codes <- head(utbildning_codes, 2)
  message("ETL-finaliseringstest: 2 utbildningsgrupper med samtliga övriga TAB6929-dimensioner.")
}

message(
  sprintf(
    "SCB-urval: %d län, %d utbildningsgrupper och %d könskategorier",
    length(region_codes),
    length(utbildning_codes),
    length(kon_codes)
  )
)

variabler <- pxweb2_get_variables(meta)
variable_sizes <- stats::setNames(variabler$size, variabler$code)

cells_per_utbildning <- (
  length(region_codes) *
    variable_sizes[["SNI2007"]] *
    length(kon_codes) *
    variable_sizes[["ContentsCode"]] *
    variable_sizes[["Tid"]]
)

utbildning_batches <- scb_split_dimension_by_cell_limit(
  values = utbildning_codes,
  cells_per_value = cells_per_utbildning
)

bygg_query_e3 <- function(utbildning_batch) {
  list(
    selection = list(
      list(variableCode = "ContentsCode", valueCodes = contents_codes),
      list(variableCode = "Tid", valueCodes = tid_codes),
      list(variableCode = "SNI2007", valueCodes = sni_codes),
      list(
        variableCode = "KonAlderFodelseland",
        valueCodes = as.list(kon_codes)
      ),
      list(
        variableCode = "Region",
        valueCodes = as.list(region_codes)
      ),
      list(
        variableCode = "Utbildning",
        valueCodes = as.list(utbildning_batch)
      )
    ),
    placement = list(
      heading = c("ContentsCode", "Tid", "KonAlderFodelseland"),
      stub = c("SNI2007", "Region")
    )
  )
}

df_e3 <- map2_dfr(
  utbildning_batches,
  seq_along(utbildning_batches),
  function(utbildning_batch, i) {
    message(sprintf("Hämtar SCB-del %d/%d", i, length(utbildning_batches)))

    pxweb2_get_data(
      table = meta,
      query = bygg_query_e3(utbildning_batch),
      quiet = TRUE
    )
  }
)

if (is.null(df_e3) || nrow(df_e3) == 0) stop("SCB returnerade inga rader för E3")
message(sprintf("SCB returnerade %s rader för E3", format(nrow(df_e3), big.mark = " ")))

# ---- Standardisera kolumnnamn ----

df_e3 <- scb_standardize_variable_names(df_e3, variabler)

required_cols <- c(
  "ContentsCode", "Tid", "SNI2007",
  "KonAlderFodelseland", "Region", "Utbildning", "value"
)

missing_cols <- setdiff(required_cols, names(df_e3))
if (length(missing_cols) > 0) {
  stop("Saknade kolumner efter PxWeb2-hämtning: ", paste(missing_cols, collapse = ", "))
}

region_code_col <- scb_find_code_column(df_e3, "region")
utbildning_code_col <- scb_find_code_column(df_e3, "utbildning")

# ---- Koder och etiketter för dimensioner ----

kodlistor <- pxweb2_get_values(meta, quiet = TRUE)

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
    utbildning_code = as.character(.data[[utbildning_code_col]])
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

# ---- Bygg observationspayload och publicera atomiskt ----

bygg_observationer <- function(data) {
  map(seq_len(nrow(data)), function(i) {
    row <- data[i, , drop = FALSE]

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
}

# Funktionsram krävs för att on.exit säkert ska avbryta batchen vid fel
# även när workflowet kör skriptet med source().
publicera_e3 <- function() {
  if (test_mode) {
    observations <- bygg_observationer(df_e3)
    test_batch <- etl_start_batch(
      indicator_id = target_indikator_id,
      source = kalla,
      source_updated_date = kalla_uppdaterad_datum,
      expected_chunks = 1L,
      expected_rows = length(observations)
    )

    test_batch_id <- test_batch$batch_id
    message(sprintf("ETL-batch startad: %s", test_batch_id))
    test_ok <- FALSE
    on.exit({
      if (!test_ok) try(etl_abort_batch(test_batch_id), silent = TRUE)
    }, add = TRUE)

    etl_publish_batch_chunk(
      batch_id = test_batch_id,
      indicator_id = target_indikator_id,
      chunk_index = 0L,
      observations = observations
    )
    etl_abort_batch(
      test_batch_id,
      reason = "Kontrollerad ETL-testkörning utan publicering"
    )

    test_ok <- TRUE
    message(sprintf("ETL-test klart: %d rader validerade, staged och avbrutna utan publicering.", length(observations)))
  } else {
    rows_per_chunk <- 5000L
    chunk_starts <- seq.int(1L, nrow(df_e3), by = rows_per_chunk)

    if (length(chunk_starts) > 1000L) {
      stop("E3 överskrider maximalt antal chunkar för en batch")
    }

    batch <- etl_start_batch(
      indicator_id = target_indikator_id,
      source = kalla,
      source_updated_date = kalla_uppdaterad_datum,
      expected_chunks = length(chunk_starts),
      expected_rows = nrow(df_e3)
    )

    batch_id <- batch$batch_id
    message(sprintf("ETL-batch startad: %s", batch_id))
    ok <- FALSE
    on.exit({
      if (!ok) try(etl_abort_batch(batch_id), silent = TRUE)
    }, add = TRUE)

    for (i in seq_along(chunk_starts)) {
      start <- chunk_starts[[i]]
      end <- min(start + rows_per_chunk - 1L, nrow(df_e3))
      payload_started <- proc.time()[["elapsed"]]
      observations <- bygg_observationer(df_e3[start:end, , drop = FALSE])
      message(sprintf(
        "Chunk %d/%d: byggde %d observationer på %.2f s",
        i, length(chunk_starts), length(observations),
        proc.time()[["elapsed"]] - payload_started
      ))

      etl_publish_batch_chunk(
        batch_id = batch_id,
        indicator_id = target_indikator_id,
        chunk_index = i - 1L,
        observations = observations
      )
      message(sprintf("Sparade chunk %d/%d", i, length(chunk_starts)))
    }

    resultat <- etl_finalize_batch(batch_id)
    ok <- TRUE
    message(
      sprintf(
        "%s publicerad: %s rader (batch %s)",
        target_indikator_id,
        resultat$rows %||% nrow(df_e3),
        resultat$batch_id %||% "okänd"
      )
    )
  }
}

publicera_e3()
