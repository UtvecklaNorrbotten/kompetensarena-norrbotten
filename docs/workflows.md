# GitHub Actions – översikt

Workflow-namnen grupperas med prefix: **10 · Data**, **20 · Kontroll** och
**90 · Test**. Namnen anger källa, innehåll och SCB-tabell där det är relevant.
För kvarvarande workflows är filnamn, scheman, inputs, concurrency-grupper och
körlogik oförändrade vid rensningen 2026-10-14.

| Workflow | Fil | Syfte | Automatisk körning |
| --- | --- | --- | --- |
| 10 · Data · AF – arbetsmarknadsstatistik | [etl-af-monthly-check.yml](../.github/workflows/etl-af-monthly-check.yml) | Kontrollera nya AF-data och publicera när de är redo; även manuella validerings- och historiklägen. | Den 1–15 och 23 varje månad, 04:15 UTC. |
| 10 · Data · SCB AFR – företagsregister | [etl-scb-afr-daily.yml](../.github/workflows/etl-scb-afr-daily.yml) | Synka SCB:s företagsregister; även manuell räkning, initial import och städning. | Dagligen 04:00 UTC. |
| 10 · Data · SCB BAS – sysselsatta (TAB3784, TAB2597) | [etl-scb-bas-monthly-check.yml](../.github/workflows/etl-scb-bas-monthly-check.yml) | Kontrollera metadata från den 22:a; fortsätt tills ny period hämtats och publicerats. Första importen är full; därefter endast nya månader. | Daglig kontroll 08:45 UTC; SCB-anrop bara i aktivt fönster eller vid fortsatt väntan/avbrott. |
| 10 · Data · SCB E3 – matchning, län och Riket (TAB6929) | [etl-scb-indicators.yml](../.github/workflows/etl-scb-indicators.yml) | SCB E3 för län, med utbildningsgrupper och utbildningsnivåer. Rikets antal beräknas i aggregaten från länens antal; Rikets procenttal lämnas tomma när korrekt riksvärde saknas. | Dagligen omkring 05:00 svensk tid. |
| 10 · Data · SCB E3 – matchning, kommuner (TAB6929) | [etl-e3-municipal.yml](../.github/workflows/etl-e3-municipal.yml) | Hämta eller återuppta kommunimporten och publicera först när den är komplett. | Dagligen omkring 05:30 svensk tid; även push till main som ändrar importskriptet eller workflow-filen. |
| 10 · Data · AF – Yrkesbarometern | [etl-af-yrkesbarometer-db.yml](../.github/workflows/etl-af-yrkesbarometer-db.yml) | Kontrollera och publicera samtliga omgångar från 2024, med alla frågor och källfält. Kvartalsläget kontrollerar även ändringar i historiken. | Dagligen i juni och december, 05:45 UTC; historikgranskning den 1 januari, april, juli och oktober, 05:45 UTC. |
| 10 · Data · UKÄ – högskolan i siffror | [etl-uka.yml](../.github/workflows/etl-uka.yml) | Hämta indikatorerna 13, 31, 33, 97, 99, 108 och 136; behåll senaste fem åren. | Måndagar 04:30 UTC samt push till main som ändrar de angivna R-/testfilerna. |
| 20 · Kontroll · AF – historikrevision | [etl-af-quarterly-revisions.yml](../.github/workflows/etl-af-quarterly-revisions.yml) | Kontrollera historiska revisioner; manuell baseline vid behov. | Den 16 januari, april, juli och oktober, 05:15 UTC. |
| 20 · Kontroll · SCB BAS – historikrevision (TAB3784, TAB2597) | [etl-scb-bas-quarterly-revisions.yml](../.github/workflows/etl-scb-bas-quarterly-revisions.yml) | Hämta hela BAS-historiken och publicera en komplett snapshot för att få med revideringar. | Den 18 januari, april, juli och oktober, 12:15 UTC. |
| 90 · Test · SCB E3 – kommunimport (TAB6929) | [validate-e3-municipal.yml](../.github/workflows/validate-e3-municipal.yml) | Testa R, databasens återstart/behörigheter och aggregat samt ett faktiskt SCB-prov. | Pull requests som berör de angivna filerna; även manuellt. |
| 90 · Test · SCB BAS – import (TAB3784, TAB2597) | [validate-scb-bas.yml](../.github/workflows/validate-scb-bas.yml) | Testa kalenderfönster, återstart och JSON-stat samt verkliga SCB-uttag utan produktionsåtkomst. | Relevanta pull requests och push till main; även manuellt. |

Alla workflows kan startas manuellt. GitHub Actions scheman kan fördröjas.
UTC-tider utan lokal tidskontroll flyttas en timme i svensk klocktid vid
övergång mellan sommar- och vintertid.

BAS återanvänder befintligt ETL-kontrakt och kräver registreringsmigration
0039 före första produktionsimporten. [Urval, tillstånd och driftsättning](bas-etl.md).

## Varför E3-testet finns kvar

Importworkflowet kör syntetiska R-regressionsexempel. Det separata
testworkflowet kontrollerar dessutom återstart, behörigheter och aggregat i en
isolerad PostgreSQL-databas samt ett faktiskt SCB-prov utan produktionsåtkomst.
Det kompletterar importens kontroller och publicerar ingen produktionsdata.

## Grön kommunimport kan betyda paus

En grön körning betyder att jobbet avslutades enligt sina regler. Den behöver
inte betyda att hela datasetet har publicerats.

- **Import pausad:** importens fyratimmarsbudget är förbrukad. Mottagna chunkar
  ligger kvar i en osynlig batch. Återstående delar fortsätter nästa körning.
- **Publicerad:** samtliga chunkar och förväntat radantal har verifierats och
  indikatorns aktiva version har växlats atomiskt.
- **Ingen ny SCB-version:** ingen fullimport behövdes.

Vid återstart måste SCB-version och urval stämma med den sparade importnyckeln.
En delvis sparad SCB-del skickas om och redan sparade chunkar kontrolleras med
checksumma. Om SCB-versionen har ändrats byggs en ny import; versioner blandas
inte. Tidigare publicerade data påverkas inte av en pausad import.

Detaljer finns i [E3-dokumentationen](e3-etl.md).

## Borttagna workflows (2026-10-14)

- `probe-af-yrkesbarometer.yml`: inledande källprov inför ETL. Den färdiga
  importen validerar källfält, perioder, geografi och dubbletter samt kör regressionstester.
- `etl-af-yrkesbarometer-archive.yml`: separat engångshämtning till Actions-artefakt.
  Databasimporten hämtar historiken och bevarar alla källrader som JSON.
  Hjälpskriptet `scripts/etl_af_yrkesbarometer_archive.py` behålls eftersom importen
  använder dess hämtfunktion och källista. Manuell filarkivering kan fortfarande
  göras med `python scripts/etl_af_yrkesbarometer_archive.py`.
- `probe-skatteverket-agi.yml` och `validate-skatteverket-agi.yml`: tekniska prov
  för AGI, som inte används som datakälla i projektet. Kartläggning, skript och
  testfall behålls för eventuell framtida återanvändning.

E3- och BAS-testerna behålls eftersom de verifierar aktiva importer och,
för E3, databasens återstart, behörigheter och aggregat. Sällan körda
historikrevisioner är också aktiva delar av dataförvaltningen.
