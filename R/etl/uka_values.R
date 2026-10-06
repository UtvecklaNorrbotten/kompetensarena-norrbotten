# ---- UKÄ: bevara decimaler från numeriska och textbaserade CSV-kolumner ----
clean_value <- function(x) {
  # read_delim kan redan ha tolkat svensk decimalcomma som double.
  # Gör inte numeric -> text -> parse_number med svensk locale:
  # as.character(3.3) använder punkt och skulle då bli 3.
  if (is.numeric(x)) return(as.numeric(x))

  value <- trimws(as.character(x))
  value[value %in% c("", "..", ".", "-", "NA")] <- NA_character_
  value <- gsub("[[:space:]\u00A0\u202F]", "", value)
  value <- sub(",", ".", value, fixed = TRUE)
  parsed <- suppressWarnings(as.numeric(value))

  if (any(!is.na(value) & (is.na(parsed) | !is.finite(parsed)))) {
    stop("UKÄ-exporten innehåller ett värde som inte kan tolkas som ett fullständigt tal")
  }
  parsed
}
