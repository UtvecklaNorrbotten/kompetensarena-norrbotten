# Kontrollerar om Arbetsförmedlingens sex nödvändiga månadsfiler är synkroniserade.
# Skriptet laddar inte ned Excel-filer.

source("R/etl/etl_api.R")
source("R/etl/af_common.R")

source_id <- "af-monthly"
state <- etl_get_source_state(source_id)
last_successful_period <- state$state$latest_successful_period %||% NA_character_

af_set_github_output <- function(ready, period = NA_character_) {
  output_path <- Sys.getenv("GITHUB_OUTPUT", unset = "")
  if (!nzchar(output_path)) return(invisible(NULL))

  cat(
    paste0("ready=", if (isTRUE(ready)) "true" else "false", "\n"),
    file = output_path,
    append = TRUE
  )
  if (!is.na(period) && nzchar(period)) {
    cat(
      paste0("period=", period, "\n"),
      file = output_path,
      append = TRUE
    )
  }
  invisible(NULL)
}

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
        note = "Väntar tills samtliga sex primärkällor visar samma månad"
      )
    )
    af_set_github_output(FALSE, latest_seen)
    message("AF: väntar tills samtliga sex källfiler visar samma månad.")
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
    af_set_github_output(FALSE, common_period)
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

  af_set_github_output(TRUE, common_period)
  message(
    "AF: samtliga sex primärkällor är uppdaterade till ",
    common_period,
    " och perioden är redo för import."
  )

  invisible(TRUE)
}

tryCatch(
  run_af_source_check(),
  error = function(e) {
    af_set_github_output(FALSE)
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
