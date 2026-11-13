# Publication recovery is separate from fetching so it can be tested without SCB.
afr_read_sync <- function(sync_id = NULL, mode = "daily") {
  req <- etl_request("/api/public/jobs/afr/resume")
  req <- if (is.null(sync_id)) req |> req_url_query(mode = mode) else req |> req_url_query(sync_id = sync_id)
  etl_perform_json(req, retry_safe = TRUE)
}

afr_chunks_complete <- function(state) {
  fields <- c("received_je_chunks", "expected_je_chunks", "received_ae_chunks", "expected_ae_chunks")
  !is.null(state) && length(state) > 0L &&
    all(vapply(fields, function(k) length(state[[k]]) == 1L && !is.na(state[[k]]), logical(1))) &&
    identical(as.integer(state$received_je_chunks), as.integer(state$expected_je_chunks)) &&
    identical(as.integer(state$received_ae_chunks), as.integer(state$expected_ae_chunks))
}

afr_finalize_recoverable <- function(sync_id, stats = list(), attempts = 6L, pause = Sys.sleep) {
  for (attempt in seq_len(attempts)) {
    state <- afr_read_sync(sync_id)
    if (is.null(state) || !length(state)) stop("AFR-synken saknas: ", sync_id)
    if (identical(state$status, "succeeded")) return(list(status = "succeeded", stats = state$stats))
    if (!identical(state$status, "receiving")) stop("AFR-synken har status ", state$status)
    if (!afr_chunks_complete(state)) stop("AFR-synken saknar datapaket; publicering stoppad")
    message(sprintf("AFR publicering %s, försök %d/%d", sync_id, attempt, attempts))
    # No automatic HTTP retry. Read committed status before each explicit attempt.
    body <- list(sync_id = sync_id)
    if (length(stats)) body$stats <- stats # list() serializes as [], not a JSON object.
    result <- tryCatch(afr_post("/api/public/jobs/afr/finalize", body,
      retry_safe = FALSE, timeout = 660), error = function(e) {
        message("AFR publiceringssvar osäkert: ", conditionMessage(e))
        list(status = "unknown")
      })
    if (identical(result$status, "succeeded")) return(result)
    if (identical(result$status, "blocked")) stop("AFR publicering kräver åtgärd: ", result$message)
    message("AFR publiceringsstatus: ", result$status, " ", if (is.null(result$code)) "" else result$code, " ", if (is.null(result$message)) "" else result$message)
    if (!is.null(result$activity)) message("AFR låsdiagnostik: ", jsonlite::toJSON(result$activity, auto_unbox = TRUE))
    if (attempt < attempts) pause(min(60, 10 * attempt))
  }
  # A last response may have been lost after commit.
  state <- afr_read_sync(sync_id)
  if (identical(state$status, "succeeded")) return(list(status = "succeeded", stats = state$stats))
  stop("AFR publicering ej bekräftad; datapaketen behålls för nästa körning")
}
