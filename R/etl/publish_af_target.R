# Publicerar en av Arbetsförmedlingens fem normaliserade produktionskällor.
# AF_PUBLISH_MODE: history | current
# AF_PUBLISH_TARGET: sok | tid | svag | yrke | bas
#
# history = full versionsstyrd backfill
# current = atomisk ersättning av endast senaste gemensamma månadsperioden

suppressPackageStartupMessages({
  library(dplyr)
})

source("R/etl/etl_api.R")
source("R/etl/af_common.R")
source("R/etl/af_normalize.R")

publicera_af <- function() {
mode <- Sys.getenv("AF_PUBLISH_MODE", unset = "")
target <- Sys.getenv("AF_PUBLISH_TARGET", unset = "")
report_dir <- Sys.getenv("AF_PUBLISH_REPORT_DIR", unset = "artifacts/af-publish")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

if (!mode %in% c("history", "current")) {
  stop("AF_PUBLISH_MODE måste vara history eller current")
}
if (!target %in% c("sok", "tid", "svag", "yrke", "bas")) {
  stop("AF_PUBLISH_TARGET måste vara sok, tid, svag, yrke eller bas")
}

indicator_id <- switch(
  target,
  sok = "af-arbetssokande",
  tid = "af-tid-utan-arbete",
  svag = "af-svag-konkurrensformaga",
  yrke = "af-yrkesomrade",
  bas = "af-arbetskraft-bas"
)

source_keys <- switch(
  target,
  sok = "arbetssokande",
  tid = c("tid_utan_arbete", "tid_utan_arbete_riket"),
  svag = "svag_konkurrensformaga",
  yrke = "yrkesomrade",
  bas = "arbetskraft_bas"
)

manifest_all <- af_discover_sources()
common_period <- af_common_period(manifest_all)
if (is.na(common_period)) {
  stop("AF-filerna visar inte samma period; publicering avbryts")
}

if (mode == "current") {
  source_state <- etl_get_source_state("af-monthly")
  latest_successful <- source_state$state$latest_successful_period %||% NA_character_

  if (
    !is.na(latest_successful) &&
    nzchar(latest_successful) &&
    common_period <= latest_successful
  ) {
    message(
      "AF-period ", common_period,
      " är redan framgångsrikt publicerad; ", target, " hoppas över."
    )
    return(invisible(list(skipped = TRUE, period = common_period, target = target)))
  }
}

manifest <- manifest_all |>
  filter(source_key %in% source_keys)

tmp <- tempfile(paste0("af-publish-", target, "-"))
dir.create(tmp)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

files <- af_download_sources(manifest, tmp)
path_for <- function(key) files$path[match(key, files$source_key)][[1]]
period_filter <- if (mode == "current") common_period else NULL

data <- switch(
  target,
  sok = af_normalize_web_sok(
    path_for("arbetssokande"),
    period = period_filter
  ),
  tid = af_normalize_tid_utan_arbete(
    path_for("tid_utan_arbete"),
    riket_path = path_for("tid_utan_arbete_riket"),
    period = period_filter
  ),
  svag = af_normalize_svag_konkurrensformaga(
    path_for("svag_konkurrensformaga"),
    period = period_filter
  ),
  yrke = af_normalize_yrkesomrade(
    path_for("yrkesomrade"),
    period = period_filter
  ),
  bas = af_normalize_bas(
    path_for("arbetskraft_bas"),
    period = period_filter
  )
)

if (nrow(data) == 0L) stop(target, ": 0 normaliserade rader")
if (any(is.na(data$period) | !nzchar(data$period))) stop(target, ": saknad period")
if (any(is.na(data$geo_code) | !nzchar(data$geo_code))) stop(target, ": saknad geokod")
if (all(is.na(data$value))) stop(target, ": samtliga värden är NA")

if (mode == "current" && any(data$period != common_period)) {
  stop(target, ": current-läget innehåller perioder utanför ", common_period)
}

key_cols <- c(
  "period", "geo_code", "geo_level", "sex",
  "dimension_type", "dimension_value", "measure_code"
)
duplicates <- data |>
  group_by(across(all_of(key_cols))) |>
  summarise(n = n(), .groups = "drop") |>
  filter(n > 1)

if (nrow(duplicates) > 0L) {
  utils::write.csv(
    duplicates,
    file.path(report_dir, paste0("duplicates-", target, ".csv")),
    row.names = FALSE,
    na = ""
  )
  stop(target, ": dubbletter på observationsnyckeln")
}

latest <- data |>
  filter(period == common_period)

geo_latest <- latest |>
  distinct(geo_code, geo_level) |>
  count(geo_level, name = "n")

geo_count <- function(level) {
  hit <- geo_latest$n[geo_latest$geo_level == level]
  if (length(hit) == 0L) 0L else as.integer(hit[[1]])
}

if (geo_count("kommun") != 290L) stop(target, ": senaste period saknar 290 kommuner")
if (geo_count("län") != 21L) stop(target, ": senaste period saknar 21 län")
if (geo_count("riket") != 1L) stop(target, ": senaste period saknar Riket")

build_observations <- function(chunk) {
  has_bound <- "value_is_lower_bound" %in% names(chunk)

  lapply(seq_len(nrow(chunk)), function(i) {
    dims <- list(
      geo_level = as.character(chunk$geo_level[[i]]),
      dimension_type = as.character(chunk$dimension_type[[i]]),
      dimension_value = as.character(chunk$dimension_value[[i]]),
      measure_code = as.character(chunk$measure_code[[i]]),
      measure_label = as.character(chunk$measure_label[[i]])
    )

    sex <- chunk$sex[[i]]
    if (!is.na(sex) && nzchar(as.character(sex))) {
      dims$sex <- as.character(sex)
    }

    if (has_bound && isTRUE(chunk$value_is_lower_bound[[i]])) {
      dims$value_is_lower_bound <- TRUE
    }

    list(
      geo_code = as.character(chunk$geo_code[[i]]),
      period = as.character(chunk$period[[i]]),
      value = as.numeric(chunk$value[[i]]),
      dimensions = dims
    )
  })
}

rows_per_chunk <- 5000L
chunk_starts <- seq.int(1L, nrow(data), by = rows_per_chunk)

if (length(chunk_starts) > ETL_MAX_CHUNKS) {
  stop(
    target, ": kräver ", length(chunk_starts),
    " chunkar; max är ", ETL_MAX_CHUNKS
  )
}

batch_mode <- if (mode == "current") "replace_period" else "full"
batch <- etl_start_batch(
  indicator_id = indicator_id,
  source = "Arbetsförmedlingen",
  source_updated_date = NULL,
  expected_chunks = length(chunk_starts),
  expected_rows = nrow(data),
  mode = batch_mode,
  replace_period = if (mode == "current") common_period else NULL
)

batch_id <- batch$batch_id
ok <- FALSE
on.exit({
  if (!ok) {
    try(
      etl_abort_batch(
        batch_id,
        reason = paste0("AF ", mode, "/", target, " avbruten före finalisering")
      ),
      silent = TRUE
    )
  }
}, add = TRUE)

for (i in seq_along(chunk_starts)) {
  row_start <- chunk_starts[[i]]
  row_end <- min(row_start + rows_per_chunk - 1L, nrow(data))
  observations <- build_observations(data[row_start:row_end, , drop = FALSE])

  etl_publish_batch_chunk(
    batch_id = batch_id,
    indicator_id = indicator_id,
    chunk_index = i - 1L,
    observations = observations
  )
  message(
    target, ": chunk ", i, "/", length(chunk_starts),
    " (", length(observations), " rader)"
  )
}

result <- etl_finalize_batch(batch_id)
ok <- TRUE

utils::write.csv(
  files |>
    select(source_key, period, filename, sha256, bytes),
  file.path(report_dir, paste0("source-manifest-", target, ".csv")),
  row.names = FALSE,
  na = ""
)

summary <- data.frame(
  target = target,
  indicator_id = indicator_id,
  mode = mode,
  period = common_period,
  rows_sent = nrow(data),
  batch_id = result$batch_id %||% batch_id,
  stringsAsFactors = FALSE
)
utils::write.csv(
  summary,
  file.path(report_dir, paste0("publish-summary-", target, ".csv")),
  row.names = FALSE,
  na = ""
)

message(
  "AF ", target, " publicerad i ", mode, "-läge: ",
  format(nrow(data), big.mark = " "),
  " rader; period=", common_period,
  "; batch=", result$batch_id %||% batch_id
)

}

publicera_af()
