# Normalisering och deterministisk hash för AFR.
# Kanonisk form MÅSTE vara identisk med databasfunktionerna
# afr_je_canonical / afr_ae_canonical / afr_canonical_sni (migration 0019).
#  - fasta fält i fast ordning, separerade med "|", prefix "je1|"/"ae1|"
#  - saknat värde = tom sträng; tomma strängar normaliseras till NA före hash
#  - datum = YYYY-MM-DD, heltal utan decimaler
#  - SNI = "rang:kod:andel" sorterat på rangordning och kod (bytevis), skilda med ";"
#  - klartexter ingår aldrig
# Telefon, e-post, adresser, namn och spärrar läses aldrig in.

suppressPackageStartupMessages(library(openssl))

.pick <- function(recs, ...) {
  keys <- c(...)
  vapply(recs, function(r) {
    v <- r
    for (k in keys) {
      if (is.null(v)) break
      v <- v[[k]]
    }
    if (is.null(v) || length(v) == 0) NA_character_ else as.character(v[[1]])
  }, character(1))
}

.chr <- function(x) {
  x <- trimws(as.character(x))
  x[!is.na(x) & x == ""] <- NA_character_
  x
}
.int <- function(x) suppressWarnings(as.integer(.chr(x)))
.date <- function(x) {
  x <- .chr(x)
  out <- substr(x, 1, 10)
  out[!is.na(out) & !grepl("^\\d{4}-\\d{2}-\\d{2}$", out)] <- NA_character_
  out
}

.sni <- function(recs) {
  lapply(recs, function(r) {
    ng <- r$naringsgrenar %||% list()
    if (!length(ng)) return(data.frame(r = integer(), kod = character(), andel = integer(), avd = character()))
    df <- data.frame(
      r = as.integer(vapply(ng, function(e) as.character(e$rangordning %||% NA), character(1))),
      kod = .chr(vapply(ng, function(e) as.character(e$naringsgren %||% NA), character(1))),
      andel = as.integer(vapply(ng, function(e) as.character(e$andelProcent %||% NA), character(1))),
      avd = .chr(vapply(ng, function(e) as.character(e$avdelningsKod %||% NA), character(1))),
      stringsAsFactors = FALSE
    )
    df <- df[!is.na(df$r) & !is.na(df$kod), , drop = FALSE]
    df <- df[!duplicated(df[, c("r", "kod")]), , drop = FALSE]
    df[order(df$r, df$kod, method = "radix"), , drop = FALSE]
  })
}

afr_normalize_je_page <- function(recs) {
  list(
    key = .chr(.pick(recs, "peOrgNr")),
    org_nr = .chr(.pick(recs, "orgNr")),
    kommun_sate = .chr(.pick(recs, "kommunSate")),
    lan_sate = .chr(.pick(recs, "lanSate")),
    ae_ant = .int(.pick(recs, "aeAnt")),
    anst_kl = .chr(.pick(recs, "anstKl")),
    ftg_stat = .chr(.pick(recs, "ftgStat")),
    jurform = .chr(.pick(recs, "jurform")),
    start_dat = .date(.pick(recs, "startDat")),
    slut_dat = .date(.pick(recs, "slutDat")),
    reg_dat = .date(.pick(recs, "regDat")),
    oms_ar = .int(.pick(recs, "omsAr")),
    oms_kl = .chr(.pick(recs, "omsKl")),
    ag_kat = .chr(.pick(recs, "agKat")),
    arb_giv_stat = .chr(.pick(recs, "arbGivStat")),
    moms_stat = .chr(.pick(recs, "momsStat")),
    f_skatt_stat = .chr(.pick(recs, "fSkattStat")),
    bol_stat = .chr(.pick(recs, "bolStat")),
    priv_publ = .chr(.pick(recs, "privPubl")),
    sektor = .chr(.pick(recs, "sektor")),
    sni = .sni(recs)
  )
}

afr_normalize_ae_page <- function(recs) {
  cfar <- .pick(recs, "cfarNr")
  list(
    key = ifelse(is.na(cfar), NA_character_, sprintf("%.0f", as.numeric(cfar))),
    pe_org_nr = .chr(.pick(recs, "peOrgNr")),
    ae_stat = .int(.pick(recs, "aeStat")),
    anst_kl = .int(.pick(recs, "anstKl")),
    hj_verks_je = .int(.pick(recs, "hjVerksJE")),
    ae_typ = .int(.pick(recs, "aeTyp")),
    start_dat = .date(.pick(recs, "startDat")),
    slut_dat = .date(.pick(recs, "slutDat")),
    lan = .chr(.pick(recs, "belagenhetsadress", "lan")),
    kommun = .chr(.pick(recs, "belagenhetsadress", "kommun")),
    nord_sw = .int(.pick(recs, "geografiskInformation", "nordKoordinatSW")),
    ost_sw = .int(.pick(recs, "geografiskInformation", "ostKoordinatSW")),
    tat_sma_typ_kod = .chr(.pick(recs, "geografiskInformation", "tatSmaTypKod")),
    tat_ort_sma_ort_kod = .chr(.pick(recs, "geografiskInformation", "tatOrtSmaOrtKod")),
    tat_ort_sma_ort_ben = .chr(.pick(recs, "geografiskInformation", "tatOrtSmaOrtBen")),
    sni = .sni(recs)
  )
}

# Slår ihop sidor till en data.frame (sni som list-kolumn).
afr_combine_pages <- function(pages) {
  cols <- setdiff(names(pages[[1]]), "sni")
  df <- as.data.frame(
    setNames(lapply(cols, function(c) unlist(lapply(pages, `[[`, c), use.names = FALSE)), cols),
    stringsAsFactors = FALSE
  )
  df$sni <- do.call(c, lapply(pages, `[[`, "sni"))
  df
}

.e <- function(x) ifelse(is.na(x), "", as.character(x))

afr_canonical_sni <- function(sni_list) {
  vapply(sni_list, function(d) {
    if (!nrow(d)) return("")
    o <- order(d$r, d$kod, method = "radix")
    paste0(d$r[o], ":", d$kod[o], ":", .e(d$andel[o]), collapse = ";")
  }, character(1))
}

afr_hash_je <- function(df) {
  canon <- paste0(
    "je1|", .e(df$kommun_sate), "|", .e(df$lan_sate), "|", .e(df$ae_ant), "|", .e(df$anst_kl), "|",
    .e(df$ftg_stat), "|", .e(df$jurform), "|", .e(df$start_dat), "|", .e(df$slut_dat), "|",
    .e(df$reg_dat), "|", .e(df$oms_ar), "|", .e(df$oms_kl), "|", .e(df$ag_kat), "|",
    .e(df$arb_giv_stat), "|", .e(df$moms_stat), "|", .e(df$f_skatt_stat), "|", .e(df$bol_stat), "|",
    .e(df$priv_publ), "|", .e(df$sektor), "|", afr_canonical_sni(df$sni)
  )
  as.character(sha256(enc2utf8(canon)))
}

afr_hash_ae <- function(df) {
  canon <- paste0(
    "ae1|", .e(df$pe_org_nr), "|", .e(df$ae_stat), "|", .e(df$anst_kl), "|", .e(df$hj_verks_je), "|",
    .e(df$ae_typ), "|", .e(df$start_dat), "|", .e(df$slut_dat), "|", .e(df$lan), "|", .e(df$kommun), "|",
    .e(df$nord_sw), "|", .e(df$ost_sw), "|", .e(df$tat_sma_typ_kod), "|", .e(df$tat_ort_sma_ort_kod), "|",
    .e(df$tat_ort_sma_ort_ben), "|", afr_canonical_sni(df$sni)
  )
  as.character(sha256(enc2utf8(canon)))
}
