# Syntetiska exempel: samma fält och värden med omnumrerade Excel-cacher.
source("R/etl/af_pivot_cache.R")

make_workbook <- function(ids) {
  root <- tempfile("af-cache-test-")
  dir.create(file.path(root, "xl", "pivotCache"), recursive = TRUE)
  output <- tempfile(fileext = ".xlsx")
  for (i in seq_along(ids)) {
    dimension <- names(ids)[[i]]
    id <- ids[[i]]
    fields <- c("PERIOD", dimension, "INSAL")
    definition <- paste0(
      '<pivotCacheDefinition xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cacheFields count="3">',
      paste0('<cacheField name="', fields, '"><sharedItems/></cacheField>', collapse = ""),
      '</cacheFields></pivotCacheDefinition>'
    )
    writeLines(definition, file.path(root, sprintf("xl/pivotCache/pivotCacheDefinition%d.xml", id)))
    writeLines(
      '<pivotCacheRecords xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="1"><r><s v="2026-09"/><s v="Exempel"/><n v="42"/></r></pivotCacheRecords>',
      file.path(root, sprintf("xl/pivotCache/pivotCacheRecords%d.xml", id))
    )
  }
  previous <- setwd(root)
  on.exit({setwd(previous); unlink(root, recursive = TRUE)}, add = TRUE)
  utils::zip(output, list.files("xl", recursive = TRUE, full.names = TRUE), flags = "-q")
  output
}

expect_error <- function(expr, pattern) {
  error <- tryCatch({force(expr); NULL}, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}

old <- make_workbook(c(ALDGR = 3L, FODLGRP = 2L, UTBILDNING = 1L))
new <- make_workbook(c(ALDGR = 1L, FODLGRP = 2L, UTBILDNING = 3L))
ambiguous <- make_workbook(c(ALDGR = 1L, ALDGR = 4L))
for (field in c("ALDGR", "FODLGRP", "UTBILDNING")) {
  fields <- c("PERIOD", field, "INSAL")
  before <- af_read_pivot_cache(old, cache_id = NULL, keep_fields = fields)
  after <- af_read_pivot_cache(new, cache_id = NULL, keep_fields = fields)
  stopifnot(identical(before, after), nrow(after) == 1L, after$INSAL == "42")
}
expect_error(af_find_pivot_cache(new, "MISSING"), "hittade 0")
expect_error(af_find_pivot_cache(ambiguous, c("PERIOD", "ALDGR", "INSAL")), "hittade 2")
expect_error(af_read_pivot_cache(new, cache_id = 3L, keep_fields = "ALDGR"), "saknar fält")
unlink(c(old, new, ambiguous))
message("AF pivot-cache: alla tester godkända")
