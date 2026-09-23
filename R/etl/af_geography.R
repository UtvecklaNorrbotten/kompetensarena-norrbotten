# Geografimappning för Arbetsförmedlingens källfiler.
#
# Produktionsurval:
# - Riket (beräknas senare från de 21 länsvärdena)
# - samtliga 21 län
# - samtliga 290 kommuner
#
# Länskoder hålls statiskt eftersom de är få och stabila.
# Kommunkoder hämtas från SCB:s aktuella officiella kodlista och cacheas
# i minnet under körningen. Då slipper AF-flödet en hårdkodad lista med
# 290 kommuner samtidigt som geo_code blir SCB:s stabila fyrsiffriga kod.

suppressPackageStartupMessages({
  library(xml2)
})

af_scb_geography_url <- paste0(
  "https://www.scb.se/hitta-statistik/regional-statistik-och-kartor/",
  "regionala-indelningar/lan-och-kommuner/",
  "lan-och-kommuner-i-kodnummerordning/"
)

af_county_codes <- c(
  "Stockholm" = "01", "Uppsala" = "03", "Södermanland" = "04",
  "Östergötland" = "05", "Jönköping" = "06", "Kronoberg" = "07",
  "Kalmar" = "08", "Gotland" = "09", "Blekinge" = "10",
  "Skåne" = "12", "Halland" = "13", "Västra Götaland" = "14",
  "Värmland" = "17", "Örebro" = "18", "Västmanland" = "19",
  "Dalarna" = "20", "Gävleborg" = "21", "Västernorrland" = "22",
  "Jämtland" = "23", "Västerbotten" = "24", "Norrbotten" = "25"
)

.af_geo_cache <- new.env(parent = emptyenv())

af_get_municipality_codes <- function(force_refresh = FALSE) {
  if (!force_refresh && exists("municipality_codes", envir = .af_geo_cache, inherits = FALSE)) {
    return(get("municipality_codes", envir = .af_geo_cache, inherits = FALSE))
  }

  doc <- xml2::read_html(af_scb_geography_url)
  text_nodes <- trimws(xml2::xml_text(xml2::xml_find_all(doc, "//text()")))
  municipality_rows <- unique(text_nodes[grepl("^[0-9]{4}[[:space:]]+[^[:space:]]", text_nodes)])

  codes <- sub("^([0-9]{4}).*$", "\\1", municipality_rows)
  names <- trimws(sub("^[0-9]{4}[[:space:]]+", "", municipality_rows))

  keep <- grepl("^[0-9]{4}$", codes) & nzchar(names)
  lookup <- stats::setNames(codes[keep], names[keep])

  # SCB redovisar 290 kommuner. Ett avvikande antal betyder normalt att
  # sidstrukturen har ändrats och då ska importen stoppas i stället för
  # att ge kommuner fel kod.
  lookup <- lookup[!duplicated(names(lookup))]

  if (length(lookup) != 290L || length(unique(unname(lookup))) != 290L) {
    stop(
      "Kunde inte läsa SCB:s kommunlista säkert: förväntade 290 kommuner men fick ",
      length(lookup),
      ". Kontrollera ", af_scb_geography_url
    )
  }

  assign("municipality_codes", lookup, envir = .af_geo_cache)
  lookup
}

af_clean_county_name <- function(x) {
  x <- trimws(as.character(x))
  x <- sub("^[0-9]{2}[[:space:]]+", "", x)
  x <- sub("s län$", "", x)
  x <- sub(" län$", "", x)
  x
}

af_clean_municipality_name <- function(x) {
  x <- trimws(as.character(x))
  x <- sub("^[0-9]{4}[[:space:]]+", "", x)
  x
}

af_geo_from_names <- function(county, municipality) {
  county_clean <- af_clean_county_name(county)
  municipality_clean <- af_clean_municipality_name(municipality)

  municipality_missing <- is.na(municipality_clean) | !nzchar(municipality_clean)
  county_code <- unname(af_county_codes[county_clean])

  municipality_codes <- af_get_municipality_codes()
  municipality_code <- unname(municipality_codes[municipality_clean])

  geo_level <- ifelse(
    !municipality_missing & !is.na(municipality_code),
    "kommun",
    ifelse(municipality_missing & !is.na(county_code), "län", NA_character_)
  )
  geo_code <- ifelse(geo_level == "kommun", municipality_code, county_code)

  data.frame(
    geo_code = geo_code,
    geo_level = geo_level,
    county_name = county_clean,
    municipality_name = municipality_clean,
    stringsAsFactors = FALSE
  )
}

af_keep_geo <- function(county, municipality) {
  # Pivotläsaren filtrerar endast bort rader som inte hör till något av Sveriges
  # 21 län. Själva kommunmappningen görs vektoriserat efter läsningen, så att
  # en okänd kommun aldrig försvinner tyst.
  county_clean <- af_clean_county_name(county)
  !is.na(unname(af_county_codes[county_clean]))
}
