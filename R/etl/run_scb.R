# Gemensam entrypoint för SCB-indikatorer.

source("R/etl/scb_indicators.R")

indicator_key <- Sys.getenv("ETL_INDICATOR", unset = "e3")
config <- get_scb_indicator(indicator_key)

message(
  sprintf(
    "Startar SCB-ETL: %s (%s)",
    config$label,
    config$table_id
  )
)

source(config$script)
