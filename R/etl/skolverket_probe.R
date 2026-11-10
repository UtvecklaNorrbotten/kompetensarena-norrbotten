# ---- Skolverket data probe ----
# Testar aktuella öppna Skolverket-källor utan att skriva till Kompetensarenas databas.
# Fokus: 10 års historik för
# - åk 9 behörighet till gymnasieskolans nationella program
# - grundläggande högskolebehörighet
# - gymnasieexamen
# - genomströmning inom 3, 4 och 5 år

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})

out_dir <- "artifacts/skolverket_probe"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

write_json_pretty <- function(x, path) {
  writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null"), path)
}

get_safe <- function(url, accept = NULL) {
  tryCatch({
    req <- request(url) |> req_timeout(60)
    if (!is.null(accept)) req <- req_headers(req, Accept = accept)
    resp <- req_perform(req)
    list(
      ok = TRUE,
      url = url,
      status = resp_status(resp),
      text = resp_body_string(resp)
    )
  }, error = function(e) {
    list(ok = FALSE, url = url, status = NA_integer_, error = conditionMessage(e))
  })
}

parse_json_safe <- function(x) {
  if (!isTRUE(x$ok) || is.null(x$text)) return(NULL)
  tryCatch(fromJSON(x$text, simplifyVector = FALSE), error = function(e) NULL)
}

message("---- Planned Educations v4 ----")

base_pe <- "https://api.skolverket.se/planned-educations/v4"
accept_v4 <- "application/vnd.skolverket.plannededucations.api.v4.hal+json"

# Känt gymnasium från tidigare lyckat v3-test.
sample_gy <- "69040241"

gy <- get_safe(paste0(base_pe, "/school-units/", sample_gy, "/statistics/gy"), accept_v4)
gy_json <- parse_json_safe(gy)
write_json_pretty(gy_json, file.path(out_dir, "planned_v4_gy_stats_sample.json"))

# API-specifikationen behövs för att verifiera om 4/5-årsmåtten finns i v4
# även om de inte syns i ett enskilt skolresultat.
openapi <- get_safe("https://api.skolverket.se/planned-educations/v3/api-docs/--v4-active")
if (isTRUE(openapi$ok)) {
  writeLines(openapi$text, file.path(out_dir, "planned_v4_openapi.json"))
}

# Hämta stödlistan kommun/län/skolor för att hitta en grundskola och
# verifiera grundskolans statistikfält.
schools <- get_safe(paste0(base_pe, "/support/municipality-schoolunit"), accept_v4)
schools_json <- parse_json_safe(schools)
write_json_pretty(schools_json, file.path(out_dir, "planned_v4_municipality_schoolunit.json"))

# Sök efter åttasiffriga skolenhetskoder i svaret och prova /statistics/gr.
# Vi testar högst 100 kandidater och slutar vid första fungerande grundskola.
school_codes <- unique(unlist(regmatches(
  if (isTRUE(schools$ok)) schools$text else "",
  gregexpr("\\b[0-9]{8}\\b", if (isTRUE(schools$ok)) schools$text else "")
)))

gr_probe <- NULL
gr_code <- NA_character_

if (length(school_codes) > 0) {
  for (code in head(school_codes, 100)) {
    candidate <- get_safe(paste0(base_pe, "/school-units/", code, "/statistics/gr"), accept_v4)
    candidate_json <- parse_json_safe(candidate)

    if (isTRUE(candidate$ok) &&
        identical(candidate$status, 200L) &&
        !is.null(candidate_json)) {
      gr_probe <- candidate_json
      gr_code <- code
      break
    }
  }
}

if (!is.null(gr_probe)) {
  write_json_pretty(gr_probe, file.path(out_dir, "planned_v4_gr_stats_sample.json"))
}

# Inventera historiklängd och fältnamn i båda statistikobjekten.
collect_time_periods <- function(x) {
  periods <- character()

  walk <- function(obj) {
    if (is.list(obj)) {
      if (!is.null(obj$timePeriod) && is.character(obj$timePeriod)) {
        periods <<- c(periods, obj$timePeriod)
      }
      invisible(lapply(obj, walk))
    }
  }

  walk(x)
  sort(unique(periods))
}

collect_names <- function(x) {
  out <- character()
  walk <- function(obj) {
    if (is.list(obj)) {
      out <<- c(out, names(obj))
      invisible(lapply(obj, walk))
    }
  }
  walk(x)
  sort(unique(out[nzchar(out)]))
}

gy_periods <- collect_time_periods(gy_json)
gr_periods <- collect_time_periods(gr_probe)
gy_fields <- collect_names(gy_json)
gr_fields <- collect_names(gr_probe)

writeLines(gy_fields, file.path(out_dir, "planned_v4_gy_fields.txt"))
writeLines(gr_fields, file.path(out_dir, "planned_v4_gr_fields.txt"))
writeLines(gy_periods, file.path(out_dir, "planned_v4_gy_periods.txt"))
writeLines(gr_periods, file.path(out_dir, "planned_v4_gr_periods.txt"))

target_patterns <- c(
  "eligible", "undergraduate", "exam", "3year", "4year", "5year",
  "3Years", "4Years", "5Years", "upperSecondary", "nationalProgram"
)

schema_hits <- character()
if (isTRUE(openapi$ok)) {
  spec_lines <- strsplit(openapi$text, "\n", fixed = TRUE)[[1]]
  keep <- Reduce(
    `|`,
    lapply(target_patterns, function(p) grepl(p, spec_lines, ignore.case = TRUE))
  )
  schema_hits <- spec_lines[keep]
  writeLines(schema_hits, file.path(out_dir, "planned_v4_openapi_target_hits.txt"))
}

summary_lines <- c(
  paste0("v4_gy_status=", gy$status),
  paste0("v4_gr_sample_school=", gr_code),
  paste0("v4_gr_found=", !is.null(gr_probe)),
  paste0("v4_gy_period_count=", length(gy_periods)),
  paste0("v4_gy_periods=", paste(gy_periods, collapse = ",")),
  paste0("v4_gr_period_count=", length(gr_periods)),
  paste0("v4_gr_periods=", paste(gr_periods, collapse = ",")),
  paste0("v4_gy_has_eligible_undergraduate=", any(grepl("eligible.*undergraduate|undergraduate.*eligible", gy_fields, ignore.case = TRUE))),
  paste0("v4_gy_has_exam_3y=", any(grepl("exam.*3|3.*exam", gy_fields, ignore.case = TRUE))),
  paste0("v4_gy_has_exam_4y=", any(grepl("exam.*4|4.*exam", gy_fields, ignore.case = TRUE))),
  paste0("v4_gy_has_exam_5y=", any(grepl("exam.*5|5.*exam", gy_fields, ignore.case = TRUE))),
  paste0("v4_gr_eligibility_fields=", paste(gr_fields[grepl("eligib|beh|upperSecondary|nationalProgram", gr_fields, ignore.case = TRUE)], collapse = ",")),
  paste0("openapi_target_hits_n=", length(schema_hits))
)

writeLines(summary_lines, file.path(out_dir, "probe_summary.txt"))
message(paste(summary_lines, collapse = "\n"))
message("Probe klar: ", out_dir)
