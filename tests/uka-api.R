# Exempel: syntetiska källrader. Inga nätverksanrop eller publicering i dessa tester.
Sys.setenv(UKA_LOAD_ONLY = "true")
source("R/etl/uka_sync.R")
Sys.unsetenv("UKA_LOAD_ONLY")
stopifnot(nrow(uka_indicators) == 10L)
stopifnot(all(uka_indicators$retention_years == 10L))
stopifnot(all(is.na(uka_indicators$active_years)))
stopifnot(length(retained_periods(paste0("from:HT", 2026:2000), 10L)) == 20L)
stopifnot(length(retained_periods(paste0("from:", 2026:2000), 10L)) == 10L)
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
# Total över alla program har inga övriga dimensioner. Tomma listor ska ge samma nyckel.
all_programs <- raw; all_programs$Program <- ""
validate_uka_observations(build_observations(normalize_uka(all_programs, 13L, TRUE, TRUE)), 13L, TRUE)
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
expanded <- raw; expanded$Åldersgrupp[2] <- '18-20'
expanded_obs <- build_observations(normalize_uka(expanded, 13L, TRUE, TRUE))
validate_uka_observations(expanded_obs, 13L, TRUE)
stopifnot(expanded_obs[[2]]$dimensions$aldersgrupp == '18-20')
bad <- raw; bad$Åldersgrupp[2] <- NA_character_
stopifnot(inherits(try(normalize_uka(bad, 13L, TRUE, TRUE), silent=TRUE), 'try-error'))
# Null och decimaler får inte ändras när en åldersdimension läggs till.
raw$Värde <- c(72.3, 0, NA_real_, 51.8)
obs <- build_observations(normalize_uka(raw, 135L, TRUE, TRUE))
validate_uka_observations(obs, 135L, TRUE)
stopifnot(obs[[1]]$value == 72.3, obs[[2]]$value == 0, is.na(obs[[3]]$value))
message('UKÄ API: gemensamma policyer, åldersgrupper, oförändrade totaler och dubblettskydd godkända')

# Exempel: återstart använder samma importfunktioner och hoppar över redan färdiga indikatorer.
stopifnot(identical(select_uka_indicators(uka_indicators, start_from = "77")$uka_id, c(77L,134L,135L)))
stopifnot(inherits(try(select_uka_indicators(uka_indicators, start_from = "999"), silent=TRUE), "try-error"))
stopifnot(length(extract_dynamic_groups("")) == 0L)

# Exempel: tomt lyckat gruppfilter är giltigt; tomma obligatoriska filter är fel.
original_request <- uka_request
uka_request <- function(url) url
req_perform <- function(req) list()
resp_has_body <- function(response) FALSE
stopifnot(identical(uka_filter_html(77L, "group.php"), ""))
stopifnot(inherits(try(uka_filter_html(77L, "age.php"), silent=TRUE), "try-error"))
uka_request <- original_request
rm(req_perform, resp_has_body, original_request)
message("UKÄ API: tomma valfria gruppfilter och säker återstart godkända")

# Exempel: syntetisk UKÄ-export som blir tom för fler än en period.
# Reservvägen ska dela intervallet, hämta alla perioder och inte publicera något.
original_export <- uka_export
seen_ranges <- character()
uka_export <- function(uka_id, from_value, to_value, universities, genders, ages, dynamic_filters) {
  seen_ranges <<- c(seen_ranges, paste(from_value, to_value))
  if (from_value != str_replace(to_value, "^to:", "from:")) stop("Tom UKÄ-exportfil")
  tibble(Tidsperiod = str_remove(from_value, "^from:"), Lärosäte = "Luleå tekniska universitet",
         Kön = "Total", Värde = 100)
}
period_list <- paste0("from:", 2026:2023)
fallback <- uka_export_adaptive(31L, period_list, "uni:1", "gender:Total", "age:1", character())
stopifnot(nrow(fallback) == 4L,
          setequal(fallback$Tidsperiod, as.character(2026:2023)),
          length(seen_ranges) > 4L)
uka_export <- original_export
rm(original_export, seen_ranges, period_list, fallback)
message("UKÄ API: reservhämtning för tomma och avkortade periodexporter godkänd")


# Exempel: en enda period ger tom export vid fler än ett lärosäte.
# Underindelning per lärosäte ska ge ett komplett dataset.
original_export <- uka_export
uka_export <- function(uka_id, from_value, to_value, universities, genders, ages, dynamic_filters) {
  if (length(universities) > 1L) stop("Tom UKÄ-exportfil")
  tibble(Tidsperiod = str_remove(from_value, "^from:"),
         Lärosäte = universities, Kön = "Total", Värde = 100)
}
split_uni <- uka_export_adaptive(33L, "from:2024/25",
                                c("uni:1", "uni:2", "uni:3", "uni:4"),
                                "gender:Total", "age:1", character())
stopifnot(nrow(split_uni) == 4L, setequal(split_uni$Lärosäte, c("uni:1", "uni:2", "uni:3", "uni:4")))
uka_export <- original_export
rm(original_export, split_uni)
message("UKÄ API: uppdelning per lärosäte godkänd")

# Exempel: UKÄ 33 ger en tom fil om alla kön kombineras, men kompletta
# källrader när varje kön begärs separat. Total får inte räknas fram.
original_export <- uka_export
requested_genders <- character()
uka_export <- function(uka_id, from_value, to_value, universities, genders, ages, dynamic_filters) {
  requested_genders <<- c(requested_genders, genders)
  if (length(genders) > 1L) stop("Tom UKÄ-exportfil")
  value <- switch(genders, "gender:Kvinnor" = 41, "gender:Män" = 59,
                  "gender:Total" = 103, stop("Okänt kön"))
  tibble(Tidsperiod = str_remove(from_value, "^from:"),
         Lärosäte = "Luleå tekniska universitet", Kön = str_remove(genders, "^gender:"),
         Åldersgrupp = "Total", Värde = value)
}
separated <- uka_export_adaptive(33L, "from:2025/26", "uni:1",
                                c("gender:Kvinnor", "gender:Män", "gender:Total"),
                                "age:1", character())
stopifnot(nrow(separated) == 3L,
          identical(separated$Värde, c(41, 59, 103)),
          identical(requested_genders, c("gender:Kvinnor", "gender:Män", "gender:Total")))
normalized <- normalize_uka(separated, 33L, TRUE, TRUE)
validate_uka_observations(build_observations(normalized), 33L, FALSE)
uka_export <- original_export
rm(original_export, requested_genders, separated, normalized)
message("UKÄ API: varje källkön hämtas separat, källans Total bevaras")

# Exempel: om en enskild period/lärosäte/kön är för stor ska ålder
# delas upp sist, men ingen källrad får dupliceras.
original_export <- uka_export
uka_export <- function(uka_id, from_value, to_value, universities, genders, ages, dynamic_filters) {
  if (length(ages) > 1L) stop("Tom UKÄ-exportfil")
  tibble(Tidsperiod = str_remove(from_value, "^from:"), Lärosäte = "Luleå tekniska universitet",
         Kön = "Total", Åldersgrupp = if (ages == "age:1") "Total" else "25-34",
         Värde = if (ages == "age:1") 100 else 60)
}
age_split <- uka_export_adaptive(33L, "from:2025/26", "uni:1",
                                 "gender:Total", c("age:1", "age:9"), character())
stopifnot(nrow(age_split) == 2L, setequal(age_split$Åldersgrupp, c("Total", "25-34")))
uka_export <- original_export
rm(original_export, age_split)
message("UKÄ API: reservuppdelning per ålder godkänd")

# Exempel: syntetiska ämnesval där full export är för stor, men två
# disjunkta delmängder fungerar. Studieformsfiltret ska följa med båda.
original_export <- uka_export
selected_subjects <- character()
uka_export <- function(uka_id, from_value, to_value, universities, genders, ages, dynamic_filters) {
  stopifnot("6.dynamic:TOTAL" %in% dynamic_filters)
  subjects <- dynamic_filters[startsWith(dynamic_filters, "7.")]
  if (length(subjects) > 2L) stop("Tom UKÄ-exportfil")
  selected_subjects <<- c(selected_subjects, subjects)
  tibble(Tidsperiod = rep(str_remove(from_value, "^from:"), length(subjects)),
         Lärosäte = "Luleå tekniska universitet", Kön = "Total",
         Ämnesgrupp = subjects, Värde = seq_along(subjects))
}
dynamic_values <- paste0("7.dynamic:", c("TOTAL", "A", "B", "C"))
dynamic_rows <- uka_export_adaptive(33L, "from:2025/26", "uni:1",
                                     "gender:Total", "age:1",
                                     c("6.dynamic:TOTAL", dynamic_values))
stopifnot(nrow(dynamic_rows) == 4L,
          setequal(selected_subjects, dynamic_values),
          !anyDuplicated(dynamic_rows$Ämnesgrupp))
uka_export <- original_export
rm(original_export,selected_subjects,dynamic_values,dynamic_rows)
message("UKÄ API: disjunkt uppdelning av ämnesfilter godkänd")
