# UKÄ – genomförd produktionsimport 2026-11-10

Alla tio avsedda indikatorer är aktiva: **1 639 839 observationer i 135 indikatorperioder**.
Detta räknar statistikrader inklusive UKÄ:s egna totaler, inte unika personer.
Den gemensamma publiceringsvägen, fel- och återstartstester, pilot 13,
de sju följande publiceringarna och återläsningen är genomförda.

| API-ID | Statistik | Perioder | Aktiva observationer | Publiceringsväg |
|---|---|---|---:|---|
| 13 | Förstahandssökande till yrkesexamensprogram | VT2017–HT2026 | 73 268 | Gemensam snapshot, pilot |
| 31 | Nybörjare på yrkesexamensprogram | HT2016–VT2026 | 73 716 | Gemensam snapshot |
| 33 | Helårsstudenter | 2016/17–2025/26 | 1 151 372 | Tidigare verifierad HST-import |
| 97 | Antagna till yrkesexamensprogram | VT2017–HT2026 | 71 394 | Gemensam snapshot |
| 99 | Söktryck till yrkesexamensprogram | VT2017–HT2026 | 19 595 | Tidigare verifierad 99-import |
| 108 | Examinerade | 2015/16–2024/25 | 119 840 | Gemensam snapshot |
| 136 | Etablering på arbetsmarknaden | 2020–2024 | 9 899 | Gemensam snapshot |
| 77 | Kvarvaro termin 3 för högskolenybörjare | 2015/16–2024/25 | 14 812 | Gemensam snapshot |
| 134 | Kvarvaro termin 3 på program | 2014/15–2023/24 | 56 525 | Gemensam snapshot |
| 135 | Examensfrekvens på program | 2012/13–2021/22 | 49 418 | Gemensam snapshot |

## Källutredning och verifieringens gränser

[UKA_COVERAGE.md](UKA_COVERAGE.md) och
[uka-source-options-2026-11-10.json](uka-source-options-2026-11-10.json)
innehåller dimensionsinventeringen, samtliga erbjudna värden, hierarkiska relationer,
lärosätes- och periodavgränsningar samt källhänvisningar för alla tio indikatorer.
Datapaketets periodvisa rapporter skiljer observerade värden från erbjudna alternativ.
De fem statusarna är verifierad data, verifierat saknad kombination,
undertryckt/ej redovisat värde, tekniskt fel och oklart. Varken HTTP-fel, tom fil
eller en teoretiskt möjlig kombination skapar en nollobservation.

De åtta CSV-indikatorerna har 315 lyckade breda/partitionerade CSV-uttag,
1 125 köns-/åldersrotsvar, 4 154 exakt matchande äldre JSON-referensobservationer
och 38 riktade detaljkontroller. HST och 99 behåller sina egna tidigare verifieringar.
Källans totaler, hela ämneshierarkin för 33 och Inriktning för 108 bevaras.
För 135 upptäcks program per period; senaste årets lista styr aldrig äldre data.
Det tidigare metadatafelet för 13 är ett historiskt tekniskt fel.

**Antagandet som fortfarande kan vara fel:** CSV och JSON kan dela samma källfel.
Partitioner och stickprov bevisar därför inte varje historisk detaljcell oberoende.
`full_source_coverage_verified` och `source_release_verified` är fortsatt **false**
för de åtta snapshotimporterna. Saknade oannonserade detaljer med otillräckliga
bevis förblir oklara. Ingen generell sekretessgräns för alla tio har verifierats.

## Gemensam publiceringsväg och lösta kodproblem

`uka_snapshot_*` ersätter den äldre publiceringsvägen för de åtta CSV-indikatorerna.
Servern binder stabil importnyckel, periodhashar, täckningsceller och chunkplan till
manifestet. Ändrade manifest, värden, källbatchar, dubblettidentiteter,
aggregatnyckelkollisioner och ofullständiga resultat stoppar publiceringen.
Status och idempotenta chunkar tillåter återstart utan att radera staging.
Äldre store/finalize/abort vägras för verifierade indikatorer.

Startkontrollen visade att de befintliga databasraderna redan motsvarade det
oberoende lokala stagingpaketet **exakt: 105/105 periodhashar, 468 872 rader**.
Därför användes serverns kontrollerade kopieringsläge för den slutliga publiceringen.
Inga rådataarkiv behövde överföras externt. Kopieringen gör högst 5 000 rader per
hashkontrollerad chunk. Slutkontrollen verifierar källa och mål igen och aktiverar
batch samt uppdaterar aggregat i samma transaktion. Varje tidigare batch finns kvar.
Sju indikatorer publicerades en i taget efter piloten.

Den installerade definitionen är versionssparad i
`drizzle/uka_snapshot_verified_import.applied.sql`; filen är en tillämpad
katalogbild utanför migrationsjournalen och **ska inte köras igen**.
Alla 12 installerade funktionsdefinitioners SHA-256 överensstämmer med filen.
Tabellerna har RLS och inga snapshotfunktioner kan köras av anon/authenticated.

SQL-klientens tvåminutersgräns var kortare än vissa aggregatomräkningar.
Slutkontrollerna kördes därför som tillfälliga serverjobb med 20 minuters SQL-gräns.
De tog bort sig själva efter körning; **inga `uka-finalize-%`-jobb återstår**.
`scripts/uka_snapshot_finalize_job.py` genererar en motsvarande avgränsad SQL-sats
för den befintliga privilegierade anslutningen. Den skapar bara jobb för en färdig,
opublicerad snapshotimport och kontrollerar att inget annat slutkontrolljobb finns.
Hanterade fel loggas och lämnar tidigare aktiv batch kvar. En serverkrasch kan kräva
manuell kontroll av jobb/status före återstart; hjälpverktyget är inte en ny schemalagd ETL.

## Tester och återläsning

- **168 lokala UKÄ-tester passerar**, inklusive återstart, hashbindning, dubbletter,
  tekniska fel och SQL-genereringens avvisning av exekverbart indata.
- Databastesterna i `tests/uka-snapshot-import.sql` verifierades före piloten och
  rullades tillbaka. Se [pilotrapporten](uka-pilot-13-publication-2026-11-10.md)
  för samtliga negativa fall, full finalisering, omvänd chunkordning och återstart.
- Efter varje aktivering återlästes samtliga periodhashar: **105/105 identiska** med
  de lokalt beräknade paketfingeravtrycken. Alla förväntade rader/chunkar finns.
- Alla åtta indikatorers fullständiga aggregat för Riket och LTU matchar lokala
  källidentiteter och värden: **16/16 grupper, 69 471 aggregatrader**.
- Publika `uka_education_slice` gav **16/16 lyckade urval, 630/630 exakta totalvärden**
  för Riket/LTU över de åtta indikatorernas perioder och kön. Största svar: 4 091 byte.
- HST, 99 och sex övriga regionala/prestationsindikatorer behöll sina aktiva batch-ID:n.
  Tidigare batchars faktiska radantal är kontrollerade för alla tio målindikatorer.

Aggregatkontrollen gäller exakta identiteter/värden, inte summering av delgrupper.
Servern avvisar kolliderande aggregatnycklar så att UKÄ:s nettoräknade totaler inte
rekonstrueras med summor. Testworkflowet kör hela UKÄ-sviten utan nya källanrop.

## Revisioner och framtida uppdatering

En avslutande färsk källkontroll av nationell Total kön/Total ålder för samtliga
105 perioder gav oförändrade kanoniska svarshashar mot det sparade underlaget.
[Revisionskvittot](uka-source-revision-2026-11-10.json) listar URL, tidpunkt och båda
hasharna. Originalsvaret kan hämtas ur det hashbundna stagingpaketet.
Detta är en avgränsad revisionskontroll, inte bevis för en oföränderlig UKÄ-release
eller för att varje underliggande detaljcell är oförändrad.

Det frysta paketets SHA-256 är
`1be12b057d06285fa97b9eaa314d31e0898de57130f7c4d99c3a4093e2eb4170`.
Framtida nya källdata kräver en ny avgränsad insamling, jämförelse av samma
observationsidentiteter, dokumenterad revision och ett nytt fryst manifest.
Återanvänd oförändrade källsvar och staging vid avbrott. Återanvänd inte detta
pakets importnyckel för nya källvärden. Automatisk löpande publicering är inte
nyaktiverad genom denna kontrollpunkt.

Den aktuella produktionsimporten är färdig. Kvarvarande förvaltningsarbete är
fördjupad förklaring av oklara detaljluckor, oberoende bladkontroller där det behövs
och beslut om återkommande revisioner. Det är inte saknade importchunkar.

## Drift och bevisfiler

Ordinarie uppladdare: `scripts/uka_snapshot_publish_verified.py`.
Exempel för det redan publicerade underlaget (kräver befintlig serviceanslutning):

```bash
python scripts/uka_snapshot_publish_verified.py \
  --frozen docs/uka-expected-publication-2026-11-10.json --api-id 31 --copy
```

Samma manifest/nyckel återupptar importen eller ger redan publicerad status.
Avbryt inte genom att radera batchar. Vid misstänkt avbrott: läs status, låt ett
pågående slutkontrolljobb slutföras och återuppta därefter samma import.
Rollback kräver en privilegierad transaktion med indikatorlås, kontroll av aktuell
batch, byte till `previous_batch_id` och aggregatuppdatering innan commit.
Ingen rollback behövdes i denna publicering.

Maskinläsbara kvitton (fullständiga batch-ID:n och hashar):

- [Publicerade batchar och tidigare radantal](data/uka-production-batches-2026-11-10.json).
- [Aktiva batchar, inklusive oförändrade indikatorer](data/uka-active-batches-2026-11-10.json).
- [Fryst oberoende publiceringsunderlag](uka-expected-publication-2026-11-10.json).
- [105 återlästa periodhashar](data/uka-period-readback-2026-11-10.json).
- [Publika urval och aggregathashar](data/uka-public-readback-2026-11-10.json).
- [Installerade funktionshashar](data/uka-installed-functions-2026-11-10.json).
- [Inga återstående slutkontrolljobb](data/uka-finalization-jobs-2026-11-10.json).
