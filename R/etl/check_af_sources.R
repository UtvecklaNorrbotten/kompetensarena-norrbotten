# Kontrollerar om Arbetsförmedlingens fem primära månadsfiler är synkroniserade.
# Skriptet laddar inte ned Excel-filer.

source("R/etl/af_common.R")

manifest <- af_discover_sources()
common_period <- af_common_period(manifest)

print(manifest[, c("source_key", "period", "filename")], row.names = FALSE)

if (is.na(common_period)) {
  message("AF: väntar tills samtliga fem källfiler visar samma månad.")
  quit(save = "no", status = 0)
}

message("AF: samtliga fem primärkällor är uppdaterade till ", common_period, ".")
