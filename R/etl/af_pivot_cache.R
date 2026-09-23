# Strömmande läsning av Excel pivot-cache.
# Stora AF-filer kan innehålla hundratals MB okomprimerad XML; därför används
# SAX-parsern i XML-paketet i stället för att läsa hela cachefilen i minnet.

suppressPackageStartupMessages({
  library(xml2)
  library(XML)
})

af_pivot_paths <- function(xlsx_path, cache_id = 1L) {
  list(
    definition = sprintf("xl/pivotCache/pivotCacheDefinition%d.xml", cache_id),
    records = sprintf("xl/pivotCache/pivotCacheRecords%d.xml", cache_id)
  )
}

af_read_pivot_definition <- function(xlsx_path, cache_id = 1L) {
  paths <- af_pivot_paths(xlsx_path, cache_id)
  tmp <- tempfile("af-pivot-def-")
  dir.create(tmp)

  extracted <- utils::unzip(
    xlsx_path,
    files = paths$definition,
    exdir = tmp
  )
  if (length(extracted) != 1 || !file.exists(extracted[[1]])) {
    stop("Pivot-cache-definition saknas: ", paths$definition)
  }

  doc <- xml2::read_xml(extracted[[1]])
  xml2::xml_ns_strip(doc)
  fields <- xml2::xml_find_all(doc, ".//cacheFields/cacheField")

  field_names <- xml2::xml_attr(fields, "name")
  shared <- lapply(fields, function(field) {
    items <- xml2::xml_find_all(field, "./sharedItems/*")
    if (length(items) == 0) return(character())

    vapply(items, function(item) {
      if (xml2::xml_name(item) == "m") return(NA_character_)
      value <- xml2::xml_attr(item, "v")
      if (is.na(value)) NA_character_ else value
    }, character(1))
  })

  unlink(tmp, recursive = TRUE, force = TRUE)

  list(field_names = field_names, shared = shared)
}

af_read_pivot_cache <- function(
  xlsx_path,
  cache_id = 1L,
  keep_fields = NULL,
  row_filter = NULL,
  chunk_size = 10000L
) {
  definition <- af_read_pivot_definition(xlsx_path, cache_id)
  field_names <- definition$field_names
  shared <- definition$shared

  if (is.null(keep_fields)) keep_fields <- field_names
  missing_fields <- setdiff(keep_fields, field_names)
  if (length(missing_fields) > 0) {
    stop("Pivot-cachen saknar fält: ", paste(missing_fields, collapse = ", "))
  }
  keep_index <- match(keep_fields, field_names)

  paths <- af_pivot_paths(xlsx_path, cache_id)
  tmp <- tempfile("af-pivot-rec-")
  dir.create(tmp)
  extracted <- utils::unzip(xlsx_path, files = paths$records, exdir = tmp)
  if (length(extracted) != 1 || !file.exists(extracted[[1]])) {
    stop("Pivot-cache-records saknas: ", paths$records)
  }

  current <- rep(NA_character_, length(field_names))
  field_index <- 0L
  buffer <- vector("list", chunk_size)
  buffer_n <- 0L
  chunks <- list()

  flush_buffer <- function() {
    if (buffer_n == 0L) return(invisible(NULL))
    block <- do.call(rbind, buffer[seq_len(buffer_n)])
    block <- as.data.frame(block, stringsAsFactors = FALSE)
    names(block) <- keep_fields
    chunks[[length(chunks) + 1L]] <<- block
    buffer_n <<- 0L
    invisible(NULL)
  }

  start_element <- function(name, attrs) {
    if (name == "r") {
      current <<- rep(NA_character_, length(field_names))
      field_index <<- 0L
      return(invisible(NULL))
    }

    if (name %in% c("x", "n", "s", "d", "b", "e", "m")) {
      field_index <<- field_index + 1L
      if (field_index > length(field_names)) {
        stop("Pivot-record innehåller fler fält än cache-definitionen")
      }

      value <- if (name == "m") NA_character_ else unname(attrs[["v"]])
      if (name == "x") {
        idx <- suppressWarnings(as.integer(value))
        values <- shared[[field_index]]
        value <- if (
          is.na(idx) || length(values) == 0L ||
          idx + 1L < 1L || idx + 1L > length(values)
        ) NA_character_ else values[[idx + 1L]]
      }

      current[[field_index]] <<- value
    }

    invisible(NULL)
  }

  end_element <- function(name) {
    if (name != "r") return(invisible(NULL))

    names(current) <<- field_names
    keep <- if (is.null(row_filter)) TRUE else isTRUE(row_filter(current))

    if (keep) {
      buffer_n <<- buffer_n + 1L
      buffer[[buffer_n]] <<- unname(current[keep_index])
      if (buffer_n >= chunk_size) flush_buffer()
    }

    invisible(NULL)
  }

  XML::xmlEventParse(
    extracted[[1]],
    handlers = list(
      startElement = start_element,
      endElement = end_element
    ),
    useTagName = FALSE,
    addContext = FALSE,
    trim = TRUE
  )

  flush_buffer()
  unlink(tmp, recursive = TRUE, force = TRUE)

  if (length(chunks) == 0L) {
    out <- as.data.frame(
      setNames(replicate(length(keep_fields), character(), simplify = FALSE), keep_fields),
      stringsAsFactors = FALSE
    )
    return(out)
  }

  do.call(rbind, chunks)
}
