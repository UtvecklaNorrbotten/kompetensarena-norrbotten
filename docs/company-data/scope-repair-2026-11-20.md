# Återställd urvalsuppdatering 2026-11-20

## Bekräftade orsaker

Bolagsverkets API-körning stannade när urvalscachen behövde förnyas efter AFR.
Den använde `DELETE FROM company_account_scope_members` utan villkor.
API-sessionens safeupdate-skydd avvisade operationen med SQLSTATE 21000,
medan direkt databaskörning fungerade. Avgränsade, tillfälliga felkoder
identifierade DELETE-steget och feltexten DELETE/WHERE (`P21W6`). Diagnostiken
är borttagen; inga fel omvandlas till tomma eller lyckade urval.

GLEIF hade dessutom ett separat stopp: dess urvalsfunktion krävde en redan
uppdaterad cache och kunde inte själv förnya den efter AFR-publicering.

## Rättning

Migration `0057_company_scope_shared_refresh.sql` är manuellt applicerad,
inte tillagd i Drizzle-journalen för automatisk återapplicering.

Båda funktionerna använder nu `company_data_refresh_scope()`. Den jämför
publicerad AFR-synk, tar samma transaktionslås och läser om senaste synken
efter väntan. Medlemskapet beräknas från samma säte-/verksamt-arbetsställeurval.
Endast bortfall tas bort med ett avgränsat NOT EXISTS-villkor; enbart nya
medlemmar läggs till. Cachemarkören skrivs atomiskt med medlemskapet.
Ändrad AFR-publicering under uttaget ger 40001 för återförsök. Tomt förväntat
urval ger fortsatt fel, aldrig en tom lyckad import.

Källdokument, bokslut, fördelningar, reservationer och historik skrivs inte om.
Den nya hjälpfunktionen är endast tillgänglig för service_role.

## Kontroller och återstart

- Utökat `tests/company-data-scope-recovery.sql` passerar i en transaktion
  som alltid rullas tillbaka: tom cache återställs med GLEIF först, exakt
  medlemskap kontrolleras mot AFR, boksluts-/GLEIF-versioner bevaras,
  upprepat anrop behåller medlemskapet och obehöriga roller saknar åtkomst.
- Biblioteket safeupdate får inte laddas manuellt via databaskopplingen.
  Därför verifieras just den skyddade API-miljön med riktiga Actions-körningar.
- 34 bokslutstester och 11 GLEIF-tester passerar lokalt. PR-kontrollen kör
  även API-/reservations-/karantän- och Node-tester.
- GLEIF [44715151152](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/44715151152)
  har återstartats och passerat: 26 269 kontroller, 0 återstående och 0 externa
  GLEIF-anrop. 1 758 entydiga LEI, 203 med moderrelation och 1 566 med undantag.
- Bokslut [44694850967](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/44694850967)
  har också passerat efter återstart från befintliga arkiv-/företagskontrollpunkter.
  Slutkontroll: 47 889 företag, 10 417 verifierade senaste bokslut, 192 strikt
  karantänmarkerade kandidater, 0 väntande och 0 viktsummefel.

Inga scheman behöver ändras: cacheförnyelsen utförs automatiskt vid nästa
urvalsläsning efter AFR. Tidigare manuella scope-anrop krävs inte längre.

## Slutkontroll

PR #105 är mergad som `f83cf96a6523cf6f8cd52a5c11787014faef1614`.
CI 44763732773 passerade: 67 Python- och 7 Node-tester. Båda riktiga
API-körningarna ovan avslutades med success. Datakällestatus är `succeeded`
för bokslut och `no_change` för GLEIF. Cachen pekar på senaste publicerade
AFR-synk. GLEIF-versionerna är fortsatt 52 538; samtliga tidigare bokslut,
reservationer och källdokument är bevarade.

Rättningen är aktiv i produktionsdatabasen. API-gränssnittet är oförändrat
och ingen frontendpublicering eller Lovable AI-körning behövdes.
