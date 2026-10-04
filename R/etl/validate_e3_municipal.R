# Syntetiska regressionsexempel: plan, cellgräns, query, normalisering och NA.
Sys.setenv(ETL_E3_FUNCTIONS_ONLY = "true")
source("R/etl/e3_municipal.R")
plan <- e3_municipal_plan(sprintf("%04d", 1:290), as.character(2019:2024),
                          as.character(1:87), as.character(1:17), as.character(1:7))
stopifnot(plan$rows == 18014220, plan$chunks == 3654, length(plan$parts) == 522)
stopifnot(all(vapply(plan$parts, function(p) p$rows <= 150000, logical(1))))
expanded <- e3_municipal_plan(sprintf("%04d", 1:290), "2024", "00S",
                              as.character(1:1000), as.character(1:7))
stopifnot(all(vapply(expanded$parts, function(p) p$rows <= 150000, logical(1))))
stopifnot(sum(vapply(expanded$parts, function(p) length(p$regions), integer(1))) == 290L)
part <- list(regions = c("0114", "0115"), year = "2024", education = "00S", rows = 4)
query <- e3_municipal_query(part, c("A-U", "A"), "000008QS")
select <- setNames(query$selection, vapply(query$selection, function(s) s$variableCode, character(1)))
stopifnot(identical(select$KonAlderFodelseland$valueCodes, list("totalt")),
          select$Region$codelist == "vs_CKM03Kommun",
          select$Utbildning$codelist == "vs_UtbildningsgruppE2-3N1-2")
# Stubs för pxweb2r; data är ett märkt syntetiskt Exempel.
pxweb2_get_variables <- function(meta) data.frame(code = character(), label = character())
scb_standardize_variable_names <- function(data, variables) data
scb_find_code_column <- function(data, variable_name) {
  if (variable_name == "region") "Region_kod" else "Utbildning_kod"
}
meta <- list(dimension = list(
  ContentsCode = list(category = list(label = c("000008QS" = "D"))),
  SNI2007 = list(category = list(label = c("A-U" = "Alla", "A" = "Jordbruk"))),
  Utbildning = list(category = list(label = c("00S" = "Alla utbildningsgrupper")))
))
data <- data.frame(ContentsCode = "D", Tid = "2024", SNI2007 = rep(c("Alla","Jordbruk"),2),
                   Region = rep(c("Kommun A","Kommun B"),each=2), Utbildning = "Alla utbildningsgrupper",
                   Region_kod = rep(c("0114","0115"),each=2), Utbildning_kod = "00S",
                   value = c(1, NA, 0, 2))
out <- e3_municipal_normalize(data, meta, part, c("A-U","A"), "000008QS")
stopifnot(nrow(out) == 4L, sum(is.na(out$value)) == 1L)
stopifnot(identical(out, e3_municipal_normalize(data[4:1,], meta, part, c("A-U","A"), "000008QS")))
observations <- e3_municipal_observations(out, meta)
stopifnot(length(observations) == 4, any(vapply(observations, function(x) is.na(x$value), logical(1))))
must_fail <- function(expr) stopifnot(inherits(tryCatch(force(expr), error = identity), "error"))
must_fail(e3_municipal_normalize(data[c(1,1,3,4),], meta, part, c("A-U","A"), "000008QS"))
must_fail(e3_municipal_normalize(data[-1,], meta, part, c("A-U","A"), "000008QS"))
data$Region_kod[1] <- "9999"
must_fail(e3_municipal_normalize(data, meta, part, c("A-U","A"), "000008QS"))
message("E3 kommun: syntetiska regressionsexempel godkända")
