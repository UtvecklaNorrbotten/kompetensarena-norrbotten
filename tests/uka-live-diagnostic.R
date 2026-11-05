# UKÄ/HST: läsbaserad diagnostik. Körs enbart som PR-test, aldrig mot publicerings-API.
Sys.setenv(UKA_LOAD_ONLY = "true")
source("R/etl/uka_sync.R")
Sys.unsetenv("UKA_LOAD_ONLY")
id <- 33L
from_html <- uka_filter_html(id, "academic_term.php?direction=from")
to_html <- uka_filter_html(id, "academic_term.php?direction=to")
uni_html <- uka_filter_html(id, "university.php")
gender_html <- uka_filter_html(id, "gender.php")
age_html <- uka_filter_html(id, "age.php")
group_html <- uka_filter_html(id, "group.php")
from <- extract_values(from_html, "from:")
to <- extract_values(to_html, "to:")
unis <- extract_values(uni_html, "uni:")
genders <- extract_values(gender_html, "gender:")
ages <- extract_values(age_html, "age:")
groups <- extract_dynamic_groups(group_html)
message("Perioder: ", paste(head(from, 12), collapse = ", "))
message("Antal universitetfilter: ", length(unis), "; kön: ", paste(genders, collapse = ", "),
        "; ålder: ", paste(ages, collapse = ", "))
for (g in groups) message("Grupp ", g$index, " / ", g$title, ": ", length(g$values), " val; ",
                         paste(head(g$values, 12), collapse = ", "))
totals <- unlist(lapply(groups, function(g) {
  x <- g$values[g$values == "dynamic:TOTAL"]
  if (!length(x)) x <- head(g$values, 1)
  paste0(g$index, x)
}), use.names = FALSE)
all_group_values <- unlist(lapply(groups, function(g) paste0(g$index, g$values)), use.names = FALSE)
message("Dynamiska filter: totalval ", length(totals), ", alla val ", length(all_group_values))
stopifnot("from:2025/26" %in% from, "to:2025/26" %in% to)
stopifnot("uni:1" %in% unis)
g <- if ("gender:Total" %in% genders) "gender:Total" else head(genders, 1)
a <- ages[ages %in% c("age:1", "age:Total")]
stopifnot(length(a) == 1L)
run_probe <- function(label, year, dynamic) {
  message("--- PROBE ", label, " / ", year, " ---")
  t <- Sys.time()
  ans <- tryCatch({
    dat <- uka_export(id, paste0("from:", year), paste0("to:", year),
                      "uni:1", g, a, dynamic)
    list(success = TRUE, rows = nrow(dat), columns = paste(names(dat), collapse = ", "),
         periods = paste(unique(clean_period(dat$Tidsperiod)), collapse = ", "))
  }, error = function(e) list(success = FALSE, error = conditionMessage(e)))
  message("RESULT ", label, " ", jsonlite::toJSON(ans, auto_unbox = TRUE),
          " elapsed_seconds=", round(as.numeric(difftime(Sys.time(), t, units="secs")), 1))
}
run_probe("2025-26_total_dimensions", "2025/26", totals)
run_probe("2024-25_total_dimensions", "2024/25", totals)
run_probe("2025-26_all_dimensions", "2025/26", all_group_values)
