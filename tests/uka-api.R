# Exempel: syntetiska källrader. Inga nätverksanrop eller publicering i dessa tester.
Sys.setenv(UKA_LOAD_ONLY = "true")
source("R/etl/uka_sync.R")
Sys.unsetenv("UKA_LOAD_ONLY")
stopifnot(nrow(uka_indicators) == 10L)
stopifnot(all(is.na(uka_indicators$retention_years[uka_indicators$uka_id %in% c(77,134,135)])))
stopifnot(all(uka_indicators$retention_years[!uka_indicators$uka_id %in% c(77,134,135)] == 5L))
stopifnot(length(retained_periods(paste0("from:HT", 2026:2000), 5L)) == 10L)
stopifnot(length(retained_periods(paste0("from:", 2026:2000), NA_integer_)) == 27L)

raw <- tibble(
  Tidsperiod = rep('HT2026', 4), Lärosäte = rep('Luleå tekniska universitet', 4),
  Kön = rep('Total', 4), Åldersgrupp = c('Total', '-24', '25-34', '35-'),
  Program = rep('Sjuksköterskeexamen', 4), Värde = c(120, 60, 40, 20)
)
data <- normalize_uka(raw, 13L, store_gender = TRUE, store_age = TRUE)
obs <- build_observations(data)
validate_uka_observations(obs, 13L, TRUE)
stopifnot(length(obs) == 4L, is.null(obs[[1]]$dimensions$aldersgrupp), obs[[1]]$value == 120)
stopifnot(identical(vapply(obs[-1], function(o) o$dimensions$aldersgrupp, character(1)), c('-24','25-34','35-')))
# Oförändrad total jämfört med den tidigare importen utan ålder.
old <- build_observations(normalize_uka(raw[1,], 13L, store_gender = TRUE))
stopifnot(identical(obs[[1]], old[[1]]))
# Total-only indikatorer får ingen konstruerad ålders- eller könsdimension.
only <- build_observations(normalize_uka(raw[1,], 99L, store_gender = FALSE, store_age = FALSE))
stopifnot(is.null(only[[1]]$dimensions$aldersgrupp), is.null(only[[1]]$gender))
validate_uka_observations(only, 99L, FALSE)
# Fler åldersgrupper med samma övriga nyckel är tillåtna, dubbletter och saknad total stoppas.
stopifnot(inherits(try(validate_uka_observations(c(obs, obs[1]), 13L, TRUE), silent=TRUE), 'try-error'))
stopifnot(inherits(try(validate_uka_observations(obs[-1], 13L, TRUE), silent=TRUE), 'try-error'))
bad <- raw; bad$Åldersgrupp[2] <- 'okänd'
stopifnot(inherits(try(normalize_uka(bad, 13L, TRUE, TRUE), silent=TRUE), 'try-error'))
# Null och decimaler får inte ändras när en åldersdimension läggs till.
raw$Värde <- c(72.3, 0, NA_real_, 51.8)
obs <- build_observations(normalize_uka(raw, 135L, TRUE, TRUE))
validate_uka_observations(obs, 135L, TRUE)
stopifnot(obs[[1]]$value == 72.3, obs[[2]]$value == 0, is.na(obs[[3]]$value))
message('UKÄ API: gemensamma policyer, åldersgrupper, oförändrade totaler och dubblettskydd godkända')
