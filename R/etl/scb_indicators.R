# Register över SCB-indikatorer som kan köras av det gemensamma workflowet.
# Lägg till nya indikatorer här först när deras egna R-skript är verifierade.

scb_indicators <- list(
  e3 = list(
    indicator_id = "e3-matchning-utbildning",
    table_id = "TAB6929",
    script = "R/etl/e3_tab6929.R",
    label = "E3 - matchning efter utbildningsgrupp och utbildningsnivå"
  )
)

get_scb_indicator <- function(key) {
  config <- scb_indicators[[key]]

  if (is.null(config)) {
    stop(
      "Okänd SCB-indikator: ", key,
      ". Tillgängliga: ", paste(names(scb_indicators), collapse = ", ")
    )
  }

  config
}
