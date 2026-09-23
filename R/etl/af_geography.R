# Geografimappning för Arbetsförmedlingens källfiler.
# Vi behåller alla län som jämförelse och kommuner i Norrbotten.

af_county_codes <- c(
  "Stockholm" = "01", "Uppsala" = "03", "Södermanland" = "04",
  "Östergötland" = "05", "Jönköping" = "06", "Kronoberg" = "07",
  "Kalmar" = "08", "Gotland" = "09", "Blekinge" = "10",
  "Skåne" = "12", "Halland" = "13", "Västra Götaland" = "14",
  "Värmland" = "17", "Örebro" = "18", "Västmanland" = "19",
  "Dalarna" = "20", "Gävleborg" = "21", "Västernorrland" = "22",
  "Jämtland" = "23", "Västerbotten" = "24", "Norrbotten" = "25"
)

af_norrbotten_municipality_codes <- c(
  "Arvidsjaur" = "2505", "Arjeplog" = "2506", "Jokkmokk" = "2510",
  "Överkalix" = "2513", "Kalix" = "2514", "Övertorneå" = "2518",
  "Pajala" = "2521", "Gällivare" = "2523", "Älvsbyn" = "2560",
  "Luleå" = "2580", "Piteå" = "2581", "Boden" = "2582",
  "Haparanda" = "2583", "Kiruna" = "2584"
)

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
  municipality_code <- unname(af_norrbotten_municipality_codes[municipality_clean])

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
  geo <- af_geo_from_names(county, municipality)
  !is.na(geo$geo_code)
}
