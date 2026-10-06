source("R/etl/uka_values.R")

# Exempel: syntetiska värden med olika talformat och sekretessmarkeringar.
stopifnot(identical(clean_value(c(3.3, 2.8, NA_real_)), c(3.3, 2.8, NA_real_)))
stopifnot(identical(clean_value(c("3,30", "2.80", "1 234,5", "0")), c(3.3, 2.8, 1234.5, 0)))
stopifnot(all(is.na(clean_value(c("", "..", ".", "-", "NA", NA_character_)))))
stopifnot(inherits(try(clean_value("3,3fel"), silent = TRUE), "try-error"))
message("UKÄ: numeriska decimaler, decimalcomma, decimalpunkt och saknade värden godkända")
