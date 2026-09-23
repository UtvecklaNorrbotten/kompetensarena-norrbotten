# Dry-run för de fem primära AF-filerna.
# Hämtar, normaliserar och gör centrala korsvalideringar. Publicerar inget.

source("R/etl/af_common.R")
source("R/etl/af_normalize.R")

run_af_normalization_validation <- function() {
  manifest <- af_discover_sources()
  common_period <- af_common_period(manifest)
  if (is.na(common_period)) {
    stop("AF-filerna visar inte samma period; validering avbryts.")
  }

  tmp <- tempfile("af-validation-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

  files <- af_download_sources(manifest, tmp)
  path_for <- function(key) files$path[match(key, files$source_key)][[1]]

  message("Normaliserar web-sok-lan-kom ...")
  sok <- af_normalize_web_sok(path_for("arbetssokande"))

  message("Normaliserar tid utan arbete ...")
  tid <- af_normalize_tid_utan_arbete(path_for("tid_utan_arbete"))

  message("Normaliserar svag konkurrensförmåga ...")
  svag <- af_normalize_svag_konkurrensformaga(path_for("svag_konkurrensformaga"))

  message("Normaliserar yrkesområde ...")
  yrke <- af_normalize_yrkesomrade(path_for("yrkesomrade"))

  message("Normaliserar BAS ...")
  bas <- af_normalize_bas(path_for("arbetskraft_bas"))

  datasets <- list(sok = sok, tid = tid, svag = svag, yrke = yrke, bas = bas)

  for (nm in names(datasets)) {
    x <- datasets[[nm]]
    if (nrow(x) == 0) stop("Normaliseringen gav 0 rader för ", nm)
    if (any(is.na(x$period) | !nzchar(x$period))) stop(nm, " har saknad period")
    if (any(is.na(x$geo_code) | !nzchar(x$geo_code))) stop(nm, " har saknad geokod")
    if (all(is.na(x$value))) stop(nm, " har bara NA-värden")
    message(sprintf("%s: %s rader", nm, format(nrow(x), big.mark = " ")))
  }

  # Kontroll 1: senaste periodens INSAL från web-sok ska överensstämma med
  # ARBETSLÖSA i tid-filen för jämförbara totaler. Tid-normaliseringen lagrar
  # inte ARBETSLÖSA som produktionsmått, så denna kontroll görs separat vid
  # filnivå i nästa steg.

  # Kontroll 2: yrkesområden får inte tappa blank kategori.
  if (!any(yrke$dimension_value == "Uppgift saknas")) {
    stop("Yrkesområdesfilen saknar förväntad kategori 'Uppgift saknas'")
  }

  # Kontroll 3: BAS ska innehålla total arbetskraft.
  if (!any(bas$measure_code == "TOTAK")) {
    stop("BAS-normaliseringen saknar TOTAK")
  }

  message("AF-normalisering godkänd för period ", common_period, ". Ingen data publicerades.")
  invisible(datasets)
}

run_af_normalization_validation()
