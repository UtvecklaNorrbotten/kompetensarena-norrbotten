# Kvartalsvis revisionskontroll för Arbetsförmedlingens historik.
# AF_REVISION_MODE: baseline | check
# AF_REVISION_TARGET: sok | tid | svag | yrke | bas
#
# baseline lagrar fingerprints för redan publicerad historik utan att skriva om data.
# check jämför aktuell AF-historik mot lagrade fingerprints och ersätter endast
# perioder som faktiskt har förändrats.

suppressPackageStartupMessages({
  library(dplyr)
})

source("R/etl/etl_api.R")
source("R/etl/af_common.R")
source("R/etl/af_normalize.R")
source("R/etl/af_fingerprints.R")

run_af_revision <- function() {
mode <- Sys.getenv("AF_REVISION_MODE", unset = "")
target <- Sys.getenv("AF_REVISION_TARGET", unset = "")
report_dir <- Sys.getenv("AF_REVISION_REPORT_DIR", unset = "artifacts/af-revisions")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

if (!mode %in% c("baseline", "check")) {
  stop("AF_REVISION_MODE måste vara baseline eller check")
}
if (!target %in% c("sok", "tid", "svag", "yrke", "bas")) {
  stop("AF_REVISION_TARGET måste vara sok, tid, svag, yrke eller bas")
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
  stop("AF-filerna visar inte samma period; revisionskontroll avbryts")
}

source_state <- etl_get_source_state("af-monthly")
latest_successful <- source_state$state$latest_successful_period %||% NA_character_
if (is.na(latest_successful) || !nzchar(latest_successful)) {
  stop("AF saknar latest_successful_period; historisk baseline måste vara publicerad först")
}

manifest <- manifest_all |>
  filter(source_key %in% source_keys)

tmp <- tempfile(paste0("af-revision-", target, "-"))
dir.create(tmp)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

files <- af_download_sources(manifest, tmp)
path_for <- function(key) files$path[match(key, files$source_key)][[1]]

data <- switch(
  target,
  sok = af_normalize_web_sok(path_for("arbetssokande")),
  tid = af_normalize_tid_utan_arbete(
    path_for("tid_utan_arbete"),
    riket_path = path_for("tid_utan_arbete_riket")
  ),
  svag = af_normalize_svag_konkurrensformaga(
    path_for("svag_konkurrensformaga")
  ),
  yrke = af_normalize_yrkesomrade(
    path_for("yrkesomrade")
  ),
  bas = af_normalize_bas(
    path_for("arbetskraft_bas")
  )
)

# Kontrollera endast perioder som redan ska finnas i vår publicerade historik.
# En nyare AF-release kan alltså finnas i källfilen utan att kvartalskontrollen
# springer före den ordinarie månadsimporten.
data <- data |>
  filter(as.character(period) <= latest_successful)

if (nrow(data) == 0L) {
  stop(target, ": inga historiska rader t.o.m. ", latest_successful)
}

current <- af_period_fingerprints(data)
manifest_payload <- list(files = af_source_manifest_list(files))

remote_to_df <- function(x) {
  empty <- data.frame(
    period = character(),
    checksum = character(),
    row_count = integer(),
    stringsAsFactors = FALSE
  )

  if (is.null(x) || length(x) == 0L) return(empty)

  if (is.data.frame(x)) {
    return(x |>
      transmute(
        period = as.character(period),
        checksum = as.character(checksum),
        row_count = as.integer(row_count)
      ))
  }

  if (is.list(x) && !is.null(x$period)) {
    return(data.frame(
      period = as.character(x$period),
      checksum = as.character(x$checksum),
      row_count = as.integer(x$row_count),
      stringsAsFactors = FALSE
    ))
  }

  if (is.list(x)) {
    return(bind_rows(lapply(x, function(row) {
      data.frame(
        period = as.character(row$period),
        checksum = as.character(row$checksum),
        row_count = as.integer(row$row_count),
        stringsAsFactors = FALSE
      )
    })))
  }

  stop("Oväntat svar från AF revisions-API")
}

stored <- remote_to_df(etl_get_af_revision_fingerprints(target))

utils::write.csv(
  current,
  file.path(report_dir, paste0("current-fingerprints-", target, ".csv")),
  row.names = FALSE,
  na = ""
)

if (mode == "baseline") {
  etl_upsert_af_revision_fingerprints(
    target = target,
    fingerprints = current,
    source_release_period = common_period,
    source_manifest = manifest_payload
  )

  message(
    target, ": revisionsbaseline sparad för ",
    nrow(current), " perioder t.o.m. ", latest_successful
  )
  return(invisible(list(mode = "baseline", target = target, periods = nrow(current))))
}

if (nrow(stored) == 0L) {
  stop(
    target,
    ": ingen revisionsbaseline finns. Kör workflowet i baseline-läge en gång först."
  )
}

missing_source <- anti_join(stored, current, by = "period")
if (nrow(missing_source) > 0L) {
  utils::write.csv(
    missing_source,
    file.path(report_dir, paste0("missing-source-periods-", target, ".csv")),
    row.names = FALSE,
    na = ""
  )
  stop(
    target, ": ", nrow(missing_source),
    " tidigare publicerade perioder saknas nu i källfilen. Ingen automatisk radering görs."
  )
}

comparison <- full_join(
  stored |> rename(checksum_stored = checksum, row_count_stored = row_count),
  current |> rename(checksum_current = checksum, row_count_current = row_count),
  by = "period"
) |>
  mutate(
    status = case_when(
      is.na(checksum_stored) ~ "ny_historisk_period",
      checksum_stored != checksum_current ~ "andrad",
      row_count_stored != row_count_current ~ "andrad",
      TRUE ~ "oforandrad"
    )
  ) |>
  arrange(period)

utils::write.csv(
  comparison,
  file.path(report_dir, paste0("revision-diff-", target, ".csv")),
  row.names = FALSE,
  na = ""
)

changed_periods <- comparison |>
  filter(status %in% c("andrad", "ny_historisk_period")) |>
  pull(period)

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

publish_period <- function(period_value) {
  period_data <- data |>
    filter(as.character(period) == period_value)

  if (nrow(period_data) == 0L) {
    stop(target, "/", period_value, ": inga rader att publicera")
  }

  rows_per_chunk <- 5000L
  starts <- seq.int(1L, nrow(period_data), by = rows_per_chunk)

  batch <- etl_start_batch(
    indicator_id = indicator_id,
    source = paste("Arbetsförmedlingen revision", common_period),
    source_updated_date = NULL,
    expected_chunks = length(starts),
    expected_rows = nrow(period_data),
    mode = "replace_period",
    replace_period = period_value
  )

  batch_id <- batch$batch_id
  ok <- FALSE
  on.exit({
    if (!ok) {
      try(
        etl_abort_batch(
          batch_id,
          reason = paste0(
            "AF revision ", target, "/", period_value,
            " avbruten före finalisering"
          )
        ),
        silent = TRUE
      )
    }
  }, add = TRUE)

  for (i in seq_along(starts)) {
    row_start <- starts[[i]]
    row_end <- min(row_start + rows_per_chunk - 1L, nrow(period_data))
    observations <- build_observations(
      period_data[row_start:row_end, , drop = FALSE]
    )

    etl_publish_batch_chunk(
      batch_id = batch_id,
      indicator_id = indicator_id,
      chunk_index = i - 1L,
      observations = observations
    )
  }

  etl_finalize_batch(batch_id)
  ok <- TRUE

  fp <- current |>
    filter(period == period_value)

  etl_upsert_af_revision_fingerprints(
    target = target,
    fingerprints = fp,
    source_release_period = common_period,
    source_manifest = manifest_payload
  )

  message(
    target, ": reviderad period ", period_value,
    " publicerad (", format(nrow(period_data), big.mark = " "), " rader)."
  )
}

if (length(changed_periods) > 0L) {
  message(
    target, ": ", length(changed_periods),
    " period(er) har ändrats: ",
    paste(changed_periods, collapse = ", ")
  )

  for (p in changed_periods) {
    publish_period(p)
  }
} else {
  message(target, ": inga historiska revisioner upptäcktes.")
}

# Uppdatera checked_at och källmanifest även för oförändrade perioder.
etl_upsert_af_revision_fingerprints(
  target = target,
  fingerprints = current,
  source_release_period = common_period,
  source_manifest = manifest_payload
)

summary <- data.frame(
  target = target,
  source_release_period = common_period,
  latest_successful_period = latest_successful,
  checked_periods = nrow(current),
  changed_periods = length(changed_periods),
  changed = paste(changed_periods, collapse = ";"),
  stringsAsFactors = FALSE
)

utils::write.csv(
  summary,
  file.path(report_dir, paste0("revision-summary-", target, ".csv")),
  row.names = FALSE,
  na = ""
)

}

run_af_revision()
