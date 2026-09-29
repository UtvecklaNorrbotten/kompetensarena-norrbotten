# Markerar AF:s samlade månadsleverans som lyckad först när samtliga fem
# indikatorjobb har publicerats utan fel.

source("R/etl/etl_api.R")
source("R/etl/af_common.R")

manifest <- af_discover_sources()
common_period <- af_common_period(manifest)
if (is.na(common_period)) {
  stop("AF-filerna visar inte samma period; kan inte markera publicering lyckad")
}

details <- list(
  files = lapply(seq_len(nrow(manifest)), function(i) {
    list(
      source_key = manifest$source_key[[i]],
      period = manifest$period[[i]],
      filename = manifest$filename[[i]]
    )
  }),
  note = "Samtliga fem AF-indikatorer publicerade"
)

etl_update_source_state(
  source_id = "af-monthly",
  status = "succeeded",
  latest_available_period = common_period,
  latest_successful_period = common_period,
  details = details
)

message("AF source state markerad som succeeded för ", common_period)
