# Kontrollerar om Arbetsförmedlingens sex nödvändiga månadsfiler är synkroniserade.
# Skriptet laddar inte ned Excel-filer.
#
# För schemalagda körningar används data_source_state som beständig metadata:
# - expected_period = månaden efter senaste lyckade import
# - kontrollstart = den 15:e i månaden efter expected_period, kl. 06:15 Europe/Stockholm
# - därefter kontrolleras dagligen tills expected_period har importerats

source("R/etl/etl_api.R")
source("R/etl/af_common.R")

source_id <- "af-monthly"
state <- etl_get_source_state(source_id)
last_successful_period <- state$state$latest_successful_period %||% NA_character_
last_status <- state$state$last_status %||% NA_character_
last_checked_at <- state$state$last_checked_at %||% NA_character_

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

af_add_month <- function(period, n = 1L) {
  x <- as.Date(paste0(period, "-01"))
  if (is.na(x)) stop("Ogiltig period i AF-state: ", period)
  format(seq(x, by = "month", length.out = n + 1L)[[n + 1L]], "%Y-%m")
}

af_expected_period <- function(last_successful, today_local) {
  if (!is.na(last_successful) && nzchar(last_successful)) {
    return(af_add_month(last_successful, 1L))
  }
  format(seq(as.Date(format(today_local, "%Y-%m-01")), by = "-1 month", length.out = 2L)[[2]], "%Y-%m")
}

af_expected_check_date <- function(expected_period) {
  release_month <- as.Date(paste0(af_add_month(expected_period, 1L), "-01"))
  release_month + 14
}

af_last_checked_local_date <- function(value) {
  if (is.na(value) || !nzchar(value)) return(as.Date(NA))
  parsed <- as.POSIXct(value, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
  if (is.na(parsed)) {
    parsed <- as.POSIXct(value, tz = "UTC")
  }
  if (is.na(parsed)) return(as.Date(NA))
  as.Date(format(parsed, tz = "Europe/Stockholm", usetz = FALSE))
}

now <- Sys.time()
today_local <- as.Date(format(now, tz = "Europe/Stockholm", format = "%Y-%m-%d"))
local_hour <- as.integer(format(now, tz = "Europe/Stockholm", format = "%H"))
expected_period <- af_expected_period(last_successful_period, today_local)
expected_check_date <- af_expected_check_date(expected_period)
is_scheduled <- identical(Sys.getenv("GITHUB_EVENT_NAME", unset = ""), "schedule")

af_metadata <- function(files = NULL, observed_period = NULL, note = NULL) {
  out <- list(
    expected_period = expected_period,
    expected_check_from_local = paste0(
      format(expected_check_date, "%Y-%m-%d"),
      " 06:15 Europe/Stockholm"
    ),
    latest_successful_period = if (
      is.na(last_successful_period) || !nzchar(last_successful_period)
    ) NULL else last_successful_period,
    observed_period = observed_period,
    check_policy = "Start 15:e kl. 06:15 Europe/Stockholm och fortsätt dagligen tills expected_period är importerad"
  )
  if (!is.null(files)) out$files <- files
  if (!is.null(note)) out$note <- note
  out
}

run_af_source_check <- function() {
  # Workflowet triggas både 04:15 och 05:15 UTC för att följa svensk
  # sommar-/vintertid. Endast den första körningen efter 06:00 lokal tid
  # som behöver göra en kontroll går vidare.
  if (is_scheduled) {
    if (local_hour < 6L) {
      af_set_github_output(FALSE)
      message("AF: för tidig UTC-trigger; väntar till efter 06:00 Europe/Stockholm.")
      return(invisible(FALSE))
    }

    checked_local <- af_last_checked_local_date(last_checked_at)
    already_checked_today <- (
      !is.na(checked_local) &&
      identical(checked_local, today_local) &&
      !identical(last_status, "failed")
    )

    if (already_checked_today) {
      af_set_github_output(FALSE)
      message("AF: dagens kontroll är redan genomförd.")
      return(invisible(FALSE))
    }

    if (today_local < expected_check_date) {
      af_set_github_output(FALSE)
      message(
        "AF: nästa förväntade period är ", expected_period,
        "; kontroller börjar ", format(expected_check_date, "%Y-%m-%d"),
        " kl. 06:15 Europe/Stockholm."
      )
      return(invisible(FALSE))
    }
  }

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
      latest_successful_period = last_successful_period,
      details = af_metadata(
        files = file_details,
        observed_period = latest_seen,
        note = paste0(
          "Väntar på expected_period ", expected_period,
          "; samtliga sex primärkällor visar ännu inte samma månad"
        )
      )
    )
    af_set_github_output(FALSE, latest_seen)
    message(
      "AF: väntar på ", expected_period,
      "; samtliga sex källfiler visar ännu inte samma månad."
    )
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
      details = af_metadata(
        files = file_details,
        observed_period = common_period,
        note = paste0("Väntar på expected_period ", expected_period)
      )
    )
    af_set_github_output(FALSE, common_period)
    message(
      "AF: ", common_period, " är redan importerad; väntar på ",
      expected_period, "."
    )
    return(invisible(FALSE))
  }

  if (common_period < expected_period) {
    etl_update_source_state(
      source_id = source_id,
      status = "waiting",
      latest_available_period = common_period,
      latest_successful_period = last_successful_period,
      details = af_metadata(
        files = file_details,
        observed_period = common_period,
        note = paste0("Förväntad period ", expected_period, " har ännu inte publicerats")
      )
    )
    af_set_github_output(FALSE, common_period)
    message(
      "AF: källorna visar ", common_period,
      "; väntar fortfarande på förväntad period ", expected_period, "."
    )
    return(invisible(FALSE))
  }

  if (common_period > expected_period) {
    stop(
      "AF har gått vidare till ", common_period,
      " men nästa förväntade period är ", expected_period,
      ". Automatisk import stoppas för att inte hoppa över en månad."
    )
  }

  etl_update_source_state(
    source_id = source_id,
    status = "ready",
    latest_available_period = common_period,
    latest_successful_period = last_successful_period,
    details = af_metadata(
      files = file_details,
      observed_period = common_period,
      note = paste0(
        "Förväntad period ", expected_period,
        " finns i samtliga sex primärkällor och är redo för inkrementell import"
      )
    )
  )

  has_historical_baseline <- (
    !is.na(last_successful_period) &&
    nzchar(last_successful_period)
  )

  af_set_github_output(has_historical_baseline, common_period)

  if (has_historical_baseline) {
    message(
      "AF: expected_period ", expected_period,
      " finns i samtliga sex primärkällor och är redo för import."
    )
  } else {
    message(
      "AF: källorna är synkroniserade till ", common_period,
      " men historisk backfill saknas. Automatisk månadsimport startas inte."
    )
  }

  invisible(has_historical_baseline)
}

tryCatch(
  run_af_source_check(),
  error = function(e) {
    af_set_github_output(FALSE)
    try(
      etl_update_source_state(
        source_id = source_id,
        status = "failed",
        latest_successful_period = last_successful_period,
        error_message = conditionMessage(e),
        details = af_metadata(note = conditionMessage(e))
      ),
      silent = TRUE
    )
    stop(e)
  }
)
