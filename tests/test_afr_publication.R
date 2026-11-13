source("R/etl/afr_publication.R")
state <- function(status = "receiving", complete = TRUE) list(id = "test", status = status,
  received_je_chunks = if (complete) 1L else 0L, expected_je_chunks = 1L,
  received_ae_chunks = 1L, expected_ae_chunks = 1L, stats = list(ok = TRUE))
run_case <- function(states, replies, expected_calls, error = FALSE) {
  reads <- 0L; writes <- 0L
  afr_read_sync <<- function(...) { reads <<- reads + 1L; states[[min(reads, length(states))]] }
  afr_post <<- function(path, body, retry_safe, timeout) {
    stopifnot(!retry_safe, timeout > 600, is.null(body$stats))
    writes <<- writes + 1L
    r <- replies[[writes]]
    if (inherits(r, "condition")) stop(r)
    r
  }
  result <- tryCatch(afr_finalize_recoverable("test", attempts = 2L, pause = function(...) NULL), error = identity)
  stopifnot(writes == expected_calls, inherits(result, "condition") == error)
  if (!error) stopifnot(result$status == "succeeded")
}
# Lost HTTP response after commit: observe success without publishing twice.
run_case(list(state(), state("succeeded")), list(simpleError("lost response")), 1L)
# Busy original transaction: wait, check state, and retry under database lock.
run_case(list(state(), state()), list(list(status="busy"), list(status="succeeded")), 2L)
# Retryable database rollback can be retried; validation errors stop immediately.
run_case(list(state()), list(list(status="retryable"), list(status="succeeded")), 2L)
run_case(list(state()), list(list(status="blocked", message="balance")), 1L, TRUE)
run_case(list(state(complete=FALSE)), list(), 0L, TRUE)
run_case(list(state()), list(list(status="busy"), list(status="busy")), 2L, TRUE)
run_case(list(state("failed")), list(), 0L, TRUE)
run_case(list(state("succeeded")), list(), 0L)
stopifnot(!afr_chunks_complete(NULL), !afr_chunks_complete(list(status="receiving")))
cat("AFR publication recovery cases passed\n")
