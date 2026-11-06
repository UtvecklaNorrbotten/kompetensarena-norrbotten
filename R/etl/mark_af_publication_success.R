# Markerar AF:s samlade månadsleverans som lyckad först när samtliga fem
# indikatorjobb har publicerats utan fel.

source("R/etl/etl_api.R")
source("R/etl/af_common.R")

manifest <- af_discover_sources()
common_period <- af_common_period(manifest)
if (is.na(common_period)) {
  stop("AF-filerna visar inte samma period; kan inte markera publicering lyckad")
}

next_period_date <- seq(
  as.Date(paste0(common_period, "-01")),
  by = "month",
  length.out = 2L
)[[2]]
next_expected_period <- format(next_period_date, "%Y-%m")
next_check_date <- seq(next_period_date, by = "month", length.out = 2L)[[2]] + 14

details <- list(
  files = lapply(seq_len(nrow(manifest)), function(i) {
    list(
      source_key = manifest$source_key[[i]],
      period = manifest$period[[i]],
      filename = manifest$filename[[i]]
    )
  }),
  imported_period = common_period,
  expected_period = next_expected_period,
  expected_check_from_local = paste0(
    format(next_check_date, "%Y-%m-%d"),
    " 06:15 Europe/Stockholm"
  ),
  check_policy = "Start 15:e kl. 06:15 Europe/Stockholm och fortsätt dagligen tills expected_period är importerad",
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
