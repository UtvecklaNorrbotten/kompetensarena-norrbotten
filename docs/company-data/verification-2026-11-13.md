# Verifieringsprotokoll 2026-11-13

Status vid kontrollpunkten 12:54 UTC: **första produktionsimporten pågår; inte slutförd**. Slutliga antal ska hämtas med `company_data_coverage()` efter avslutade körningar.

## Källor och verkliga filer
- AFR-kontrakt verifierat mot 5 000 JE + 5 000 AE; kodtabeller och datatyper finns i `source-contract-2026-11-13.json`.
- Bolagsverkets katalog: 1 469 veckofiler; historisk metadata katalogiserad, bara senaste tillgängliga företagspaket väljs.
- Verkligt formatprov: 182 företagspaket. Version 3 gav 17 saknade omsättningar, 0 saknade rörelseresultat, 7 saknade årsresultat, 1 konflikt i eget kapital, 0 saknade tillgångar och 113 saknade medelantal anställda. Frånvaro är inte noll.
- 64 avrundade omsättningsdubbletter, en rörelseresultatdubblett, två tillgångsdubbletter och en kapitaldubblett kunde förenas via angiven noggrannhet. En verklig kapitalkonflikt kvarstår som NULL.
- Kompletterande formatprov: 25 årsredovisningar bland 45 XHTML-handlingar, inklusive K3; övriga 20 handlingar användes inte.
- Provet med 182 paket är **inte** ett slumpmässigt Norrbottensurval.

## Urval efter verksamhetsstatus
| Mått | Antal |
|---|---:|
| Företag med säte i län 25 eller verksamt arbetsställe i län 25 | 47 900 |
| Ett verksamt svenskt arbetsställe | 36 900 |
| Flera verksamma svenska arbetsställen | 894 |
| Inget verksamt svenskt arbetsställe | 10 106 |
| Digital rapportkandidat | 10 607 |
| Ingen digital rapportkandidat | 37 293 |

Kandidattäckning cirka 22,1 %. Det är inte samma sak som slutlig andel tolkade rapporter. Populationen omfattar även företagsformer som inte lämnar digital årsredovisning i detta material. Urval och antal kan ändras när den pågående AFR-synken publiceras.

## Kontroll av faktisk lagring
Vid kontrollpunkten fanns 1 320 företag med lagrat bokslut. Läsbar SQL-kontroll `tests/company-data-production-audit.sql` gav:
- 0 saknade komprimerade källpaket för sparade senaste bokslut.
- 0 fel i viktsummor och fördelade omsättningssummor.
- 0 omärkta omsättningsskattningar.
- 0 koncernposter använda som företagsbokslut.
- 0 avvikelser i beräknade kvoter.
- Profilbaslinjen hade ännu 0 poster; rikstäckande AFR-traversering pågick. Inget slutgodkännande av profilimporten ges vid denna kontrollpunkt.

Samtliga 32 Python-regressionstester passerade. Befintliga R-tester och syntaxkontroller passerade tidigare under implementationen. Rollback-testet av profilernas ändringshistorik, kontaktöverskrivning och åtkomst samt lästestet av verksam struktur passerade i projektets databas.

## Antaganden och begränsningar
Personalintervallens mittpunkter är relativa vikter, inte uppskattat bokslutsmedelantal. Saknat intervall imputeras med företagets positiva median (annars 1); samtliga nollor ger lika vikter; öppen högsta klass använder 12 499,5. Fiktiva/rörliga CFAR markeras. Inaktiva CFAR är kvar i AFR men ingår inte i fördelningsnämnaren.

Aktuell struktur för ett äldre bokslut märks uttryckligen. Personalstorlek kan vara en dålig omsättningsfördelare för exempelvis huvudkontor och kapitalintensiva anläggningar. Soliditet är ojusterad, utan obeskattade reserver. Okända taxonomier, koncernavgränsningar och tvetydiga rapporter sätts i karantän.

Inga nya åtkomstuppgifter har behövts. Databasmigrationerna 0048–0051 och API-publiceringen är genomförda i projektmiljön. Ingen Lovable AI-utredning eller ny publik analysvy har beställts.
