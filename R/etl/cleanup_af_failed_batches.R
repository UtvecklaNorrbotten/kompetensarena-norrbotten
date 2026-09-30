# Städar misslyckade, osynliga AF-batchar före en ny historisk backfill.
# Rader tas bort i små begränsade steg via service-endpointen för att undvika
# långa databastransaktioner och timeout.

source("R/etl/etl_api.R")

failed <- etl_list_failed_batches()

if (length(failed) == 0L) {
  message("Inga misslyckade AF-batchar att städa.")
} else {
  # simplifyVector kan ge data.frame eller lista beroende på antal rader.
  if (is.data.frame(failed)) {
    batch_ids <- as.character(failed$id)
    indicators <- as.character(failed$indicator_id)
  } else if (is.list(failed) && !is.null(failed$id)) {
    batch_ids <- as.character(failed$id)
    indicators <- as.character(failed$indicator_id)
  } else if (is.list(failed)) {
    batch_ids <- vapply(failed, function(x) as.character(x$id), character(1))
    indicators <- vapply(failed, function(x) as.character(x$indicator_id), character(1))
  } else {
    stop("Oväntat svar från listningen av misslyckade batchar")
  }

  message("Städar ", length(batch_ids), " misslyckade AF-batchar.")

  for (i in seq_along(batch_ids)) {
    message(
      "Cleanup ", i, "/", length(batch_ids),
      ": ", indicators[[i]], " / ", batch_ids[[i]]
    )
    etl_cleanup_failed_batch_all(
      batch_ids[[i]],
      max_rows = 5000L,
      max_rounds = 2000L
    )
  }
}
