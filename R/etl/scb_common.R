# Gemensamma hjälpfunktioner för SCB/PxWeb2-baserade ETL-jobb.

suppressPackageStartupMessages({
  library(pxweb2r)
})

scb_prepare_run <- function(
  indicator_id,
  table_id,
  source = "SCB",
  source_state_id = NULL,
  skip_update_check = FALSE
) {
  if (!skip_update_check) {
    state <- etl_get_state(indicator_id)
    last_successful_at <- state$last_successful_at %||% NA_character_

    if (!is.na(last_successful_at) && nzchar(last_successful_at)) {
      needs_update <- pxweb2_table_needs_update(
        table = table_id,
        reference_datetime = last_successful_at
      )

      if (isFALSE(needs_update)) {
        etl_log_no_change(indicator_id, source)
        if (!is.null(source_state_id)) {
          try(
            etl_update_source_state(
              source_id = source_state_id,
              status = "no_change",
              details = list(table_id = table_id)
            ),
            silent = TRUE
          )
        }
        return(list(fetch = FALSE))
      }

      if (is.na(needs_update)) {
        warning(
          "SCB saknar användbar updated-timestamp för ", table_id,
          "; data hämtas för säkerhets skull."
        )
      }
    }
  }

  meta <- pxweb2_get_metadata(table_id)
  updated <- meta$updated %||% NA_character_

  updated_date <- if (!is.na(updated) && nzchar(updated)) {
    substr(updated, 1, 10)
  } else {
    NA_character_
  }

  if (!is.null(source_state_id)) {
    try(
      etl_update_source_state(
        source_id = source_state_id,
        status = "ready",
        latest_available_period = updated_date,
        details = list(table_id = table_id, updated = updated)
      ),
      silent = TRUE
    )
  }

  list(
    fetch = TRUE,
    meta = meta,
    updated = updated,
    updated_date = updated_date
  )
}

scb_get_codelist_codes <- function(codelist_id) {
  x <- pxweb2_get_codelist(codelist_id)
  codes <- unique(stats::na.omit(as.character(x$code)))

  if (length(codes) == 0) {
    stop("SCB-kodlistan saknar värden: ", codelist_id)
  }

  codes
}

scb_split_dimension_by_cell_limit <- function(
  values,
  cells_per_value,
  max_cells = 150000L
) {
  if (length(values) == 0) stop("Inga dimensionsvärden att dela upp")
  if (is.na(cells_per_value) || cells_per_value <= 0) {
    stop("cells_per_value måste vara större än 0")
  }

  values_per_request <- floor(max_cells / cells_per_value)

  if (values_per_request < 1) {
    stop(
      "SCB-frågan måste delas på fler dimensioner för att hålla cellgränsen"
    )
  }

  split(
    values,
    ceiling(seq_along(values) / values_per_request)
  )
}

scb_standardize_variable_names <- function(data, variables) {
  out <- data

  for (i in seq_len(nrow(variables))) {
    code <- variables$code[[i]]
    label <- variables$label[[i]]

    if (!(code %in% names(out)) && label %in% names(out)) {
      names(out)[names(out) == label] <- code
    }
  }

  out
}

scb_find_code_column <- function(data, variable_name) {
  pattern <- paste0(variable_name, ".*kod|", variable_name, "_kod")
  hit <- names(data)[grepl(pattern, names(data), ignore.case = TRUE)][1]

  if (is.na(hit) || is.null(hit)) {
    stop("Ingen kodkolumn hittades för variabeln: ", variable_name)
  }

  hit
}
