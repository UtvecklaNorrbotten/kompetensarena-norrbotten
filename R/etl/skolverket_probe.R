# ---- Skolverket data probe ----
# Testar öppna Skolverket-källor utan att skriva till Kompetensarenas databas.
# Syfte:
# 1) Planned Educations v3: skolenheter + gymnasiestatistik/programMetrics
# 2) Skolverkets PxWeb: hitta fungerande API-väg och läsa metadata
# Resultat sparas i artifacts/skolverket_probe/

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})

out_dir <- "artifacts/skolverket_probe"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

write_json_pretty <- function(x, path) {
  writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null"), path)
}

message("---- Planned Educations v3 ----")

accept_v3 <- "application/vnd.skolverket.plannededucations.api.v3.hal+json"
base_pe <- "https://api.skolverket.se/planned-educations/v3"

# Ett känt gymnasium från Skolverkets API-index, används bara som strukturtest.
sample_school <- "69040241"

get_json <- function(url, accept = NULL) {
  req <- request(url)
  if (!is.null(accept)) req <- req_headers(req, Accept = accept)
  resp <- req_perform(req)
  list(
    status = resp_status(resp),
    headers = as.list(resp_headers(resp)),
    body = resp_body_json(resp, simplifyVector = FALSE)
  )
}

school <- get_json(paste0(base_pe, "/school-units/", sample_school), accept_v3)
write_json_pretty(school$body, file.path(out_dir, "planned_school_sample.json"))
message("School endpoint status: ", school$status)

stats <- get_json(paste0(base_pe, "/school-units/", sample_school, "/statistics/gy"), accept_v3)
write_json_pretty(stats$body, file.path(out_dir, "planned_gy_stats_sample.json"))
message("GY statistics endpoint status: ", stats$status)

# Summera strukturen i gymnasiestatistiken.
body <- stats$body$body
summary_lines <- c(
  paste0("sample_school=", sample_school),
  paste0("top_level_fields=", paste(names(body), collapse = ",")),
  paste0("has_programMetrics=", "programMetrics" %in% names(body)),
  paste0("programMetrics_n=", if (!is.null(body$programMetrics)) length(body$programMetrics) else 0)
)
writeLines(summary_lines, file.path(out_dir, "planned_summary.txt"))

if (!is.null(body$programMetrics) && length(body$programMetrics) > 0) {
  pm <- body$programMetrics
  pm_fields <- unique(unlist(lapply(pm, names)))
  writeLines(pm_fields, file.path(out_dir, "planned_program_metric_fields.txt"))

  # En enkel, lång tabell över vilka programkoder som finns och vilka måttfält som förekommer.
  program_rows <- lapply(pm, function(x) {
    data.frame(
      programCode = if (!is.null(x$programCode)) as.character(x$programCode) else NA_character_,
      fields = paste(names(x), collapse = "|"),
      stringsAsFactors = FALSE
    )
  })
  write.csv(do.call(rbind, program_rows),
            file.path(out_dir, "planned_program_metrics_index.csv"),
            row.names = FALSE, fileEncoding = "UTF-8")
}

message("---- Skolverket PxWeb ----")

px_paths <- c(
  "https://statistikdatabasen.skolverket.se/PxWeb/api/v1/sv/Skolverkets_statistikdatabas/Skolverkets_statistikdatabas__Underlag_for_analys_inom_det_nationella_kvalitetssystemet__Gymnasieskola/Gymnasieskola.px",
  "https://statistikdatabasen.skolverket.se/api/v1/sv/Skolverkets_statistikdatabas/Skolverkets_statistikdatabas__Underlag_for_analys_inom_det_nationella_kvalitetssystemet__Gymnasieskola/Gymnasieskola.px"
)

px_results <- lapply(px_paths, function(url) {
  tryCatch({
    resp <- request(url) |> req_perform()
    txt <- resp_body_string(resp)
    list(url = url, status = resp_status(resp), body_prefix = substr(txt, 1, 1000))
  }, error = function(e) {
    list(url = url, status = NA_integer_, error = conditionMessage(e))
  })
})

write_json_pretty(px_results, file.path(out_dir, "pxweb_probe.json"))

working <- Filter(function(x) identical(x$status, 200L), px_results)

if (length(working) > 0) {
  px_url <- working[[1]]$url
  meta_resp <- request(px_url) |> req_perform()
  meta_txt <- resp_body_string(meta_resp)
  writeLines(meta_txt, file.path(out_dir, "pxweb_gymnasium_metadata.json"))

  meta <- fromJSON(meta_txt, simplifyVector = FALSE)
  meta_summary <- c(
    paste0("working_url=", px_url),
    paste0("title=", if (!is.null(meta$title)) meta$title else ""),
    paste0("variables=", paste(vapply(meta$variables, function(v) v$code, character(1)), collapse = ","))
  )
  writeLines(meta_summary, file.path(out_dir, "pxweb_summary.txt"))
} else {
  writeLines("Ingen av de två vanliga PxWeb-API-vägarna svarade 200. Kontrollera API-URL via PxWeb-gränssnittets 'Gör denna tabell tillgänglig i din applikation'.",
             file.path(out_dir, "pxweb_summary.txt"))
}

message("Probe klar. Filer finns i ", out_dir)
