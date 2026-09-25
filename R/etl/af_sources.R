# Källregister för Arbetsförmedlingens månadsfiler.
# Primära produktionskällor samt nödvändiga stödkällor ligger här.
# Redundanta derivatfiler importeras inte som egna dataset.

af_source_page <- "https://arbetsformedlingen.se/statistik/sok-statistik/tidigare-statistik-tidsserier"

af_sources <- list(
  arbetssokande = list(
    label = "Arbetssökande län och kommun",
    filename_prefix = "web-sok-lan-kom",
    role = "Grundtal och bakgrundsdimensioner"
  ),
  tid_utan_arbete = list(
    label = "Inskrivna arbetslösa, tid utan arbete per län och kommun",
    filename_prefix = "web-inskrivna-arbetslosa-tid-utan-arbete-lan-kom",
    role = "Tid utan arbete >6, >12 och >24 månader per kommun; län härleds där det är exakt möjligt"
  ),
  tid_utan_arbete_riket = list(
    label = "Inskrivna arbetslösa, tid utan arbete, riket",
    filename_prefix = "web-tid-riket",
    role = "Exakta riksvärden för tid utan arbete; stödkälla eftersom kommunfilen innehåller sekretessmarkeringar <5"
  ),
  svag_konkurrensformaga = list(
    label = "Inskrivna arbetslösa, svag konkurrensförmåga",
    filename_prefix = "web-inskrivna-arbetslosa-svag-konkurrensformaga",
    role = "Svag konkurrensförmåga; överlappande totaler används som kontroll"
  ),
  yrkesomrade = list(
    label = "Inskrivna arbetslösa, yrkesområde",
    filename_prefix = "web-arbetslosa-yrkesomrade",
    role = "Yrkesområdesdimension"
  ),
  arbetskraft_bas = list(
    label = "Andel inskrivna arbetslösa av arbetskraften, BAS",
    filename_prefix = "web-inskrivna-arbetslosa-andel-av-bas",
    role = "BAS-arbetskraftens nämnare; SOK-tal används som kontroll"
  )
)
