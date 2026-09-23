# Kontrollerar om Arbetsförmedlingens fem primära månadsfiler är synkroniserade.
# Skriptet laddar inte ned Excel-filer.

source("R/etl/etl_api.R")
source("R/etl/af_common.R")

source_id <- "af-monthly"
state <- etl_get_source_state(source_id)
last_successful_period <- state$state$latest_successful_period %||% NA_character_

run_af_source_check <- function() {
  manifest <- af_discover_sources()
  common_period <- af_common_period(manifest)

  print(manifest[, c("source_key", "period", "filename")], row.names = FALSE)

  file_details <- lapply(seq_len(nrow(manifest)), function(i) {
    list(
      source_key = manifest$source_key[[i]],
      period = manifest$period[[i]],
      filename = manifest$filename[[i]],
      url = manifest$url[[i]]
    )
  })

  latest_seen <- max(manifest$period)

  if (is.na(common_period)) {
    etl_update_source_state(
      source_id = source_id,
      status = "waiting",
      latest_available_period = latest_seen,
      details = list(
        files = file_details,
        note = "Väntar tills samtliga fem primärkällor visar samma månad"
      )
    )
    message("AF: väntar tills samtliga fem källfiler visar samma månad.")
    return(invisible(FALSE))
  }

  if (
    !is.na(last_successful_period) &&
    nzchar(last_successful_period) &&
    common_period <= last_successful_period
  ) {
    etl_update_source_state(
      source_id = source_id,
      status = "no_change",
      latest_available_period = common_period,
      latest_successful_period = last_successful_period,
      details = list(files = file_details)
    )
    message(
      "AF: perioden ", common_period,
      " är redan framgångsrikt importerad."
    )
    return(invisible(FALSE))
  }

  etl_update_source_state(
    source_id = source_id,
    status = "ready",
    latest_available_period = common_period,
    details = list(
      files = file_details,
      note = "Samtliga primärkällor är synkroniserade och redo för fullimport"
    )
  )

  message(
    "AF: samtliga fem primärkällor är uppdaterade till ",
    common_period,
    " och perioden är redo för import."
  )

  invisible(TRUE)
}

tryCatch(
  run_af_source_check(),
  error = function(e) {
    try(
      etl_update_source_state(
        source_id = source_id,
        status = "failed",
        error_message = conditionMessage(e)
      ),
      silent = TRUE
    )
    stop(e)
  }
)
