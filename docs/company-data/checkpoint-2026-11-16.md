# Kontrollpunkt 2026-11-16

## Återupptagning och resultat

Arbetet återupptogs från `b5dcd71` och PR #88–96. Koden, migrationerna 0048–0052, privata källpaket, versionshistoriken och kontrollpunkterna fanns redan. Vid första databasläsningen fanns 10 409 verifierade senaste bokslut, 192 karantänfall och 1 469 katalogiserade arkiv. Profilernas baslinje samt nästa delta var också klara. Den äldre kontrollpunkten med 233 arkiv var inaktuell.

GitHub-körning [43881472522](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/43881472522) avslutades med **success**. Katalogerna återanvändes och kompletterades till 1 473 arkiv; inga tidigare dokument eller bokslutsversioner raderades. Samtliga arkiv har samma aktuella urvalshash `3449c8ce538b4c5d6853ef1b4f084bccb02795ecdb27662469f8e06c310ccb9b`.

| Mått | Antal |
|---|---:|
| Företag med säte eller verksamt arbetsställe i Norrbotten | 47 854 |
| Företag med digital rapportkandidat | 10 619 |
| Verifierade senaste importerade bokslut | 10 427 |
| Karantän: rapport som parsern inte säkert kan tolka | 192 |
| Utan digital kandidat i tillgänglig katalog | 37 235 |
| Väntande kandidater i urvalet | 0 |
| Ett verksamt svenskt arbetsställe | 36 874 |
| Flera verksamma svenska arbetsställen | 895 |
| Utan verksamt svenskt arbetsställe | 10 085 |
| Arbetsställen med fördelningsposter | 11 853 |

Importerade bokslut täcker **21,8 % av hela urvalet** och **98,2 % av rapportkandidaterna**. Populationen innehåller även företagsformer som inte omfattas av digitala årsredovisningar. Att kandidat saknas betyder inte att ett företag saknar bokslut överallt. Periodsluten sträcker sig från 2021-12-31 till 2026-10-31. Den senast publicerade AFR-källan vid kontrollen var 2026-11-14; en senare schemalagd AFR-traversering pågick fortfarande.

## Driftproblem och åtgärder

Bokslutsjobben hade misslyckats med HTTP 422 i `scope`, innan källhämtning. Underliggande SQLSTATE gick inte att fastställa i efterhand: server- och databasloggarna från 06:41 UTC fanns inte kvar. Ingen bestämd rotorsak påstås utifrån denna ofullständiga loggning.

En separat verifierad prestandabrist fanns i samma urvalsfråga: 55 562 databassidor lästes och körningen tog 17,94 sekunder. Migration 0053 lägger till två små partiella index med exakt samma urvalsvillkor. `VACUUM (ANALYZE)` kördes på båda current-tabellerna. Efteråt använde frågan index-only scans med noll heap fetches och tog 68 ms. Autovacuum/analyze-trösklarna sänktes till 1 % för dessa tabeller; faktisk framtida tid beror fortfarande på cache, samtidighet och kommande delta. Återstarten lyckades efter underhållet; detta bevisar inte vilket enskilt fel som orsakade den äldre HTTP 422-responsen.

API:t lämnar nu bara en kontrollerad SQLSTATE-kod vid databasfel, aldrig fria felmeddelanden eller källpayload. Timeout, låskonflikt och serialiseringsfel blir HTTP 503 och använder klientens befintliga begränsade återförsök. Verkliga valideringsfel är fortsatt terminala. Tester täcker även att känslig text inte läcker till svar eller logg.

De två Python-cachefiler som skapades automatiskt under originalkontrollen tas bort ur git och framtida cachefiler ignoreras. Lovables automatiska uppdatering av byggpaketets version och låsfil bevaras.

## Datakvalitet och bortfall

| Saknat mått bland importerade bokslut | Antal |
|---|---:|
| Nettoomsättning | 597 |
| Rörelseresultat | 47 |
| Årets resultat | 60 |
| Eget kapital | 120 |
| Totala tillgångar | 20 |
| Medelantal anställda | 4 212 |

4 288 bokslut saknar minst ett av de sex måtten. Källvärden för granskning: negativ nettoomsättning 163, negativa tillgångar 8, negativt medelantal anställda 0 och annan periodlängd än tolv månader 901. Totalt 1 065 bokslut har minst en sådan markering; kategorierna kan överlappa. 8 102 rapporter har någon parsermarkering, vilket även omfattar informationsmarkeringar för konsekvent avrundade dubbletter och vanliga faktaluckor, inte enbart misstänkta fel.

Alla relevanta svenska arbetsställen används i nämnaren, även utanför län 25: 2 972 fördelningsposter avser andra län. Fördelningsposter matchades mot faktisk AFR-historik och aktuell verksam struktur. Kontrollfrågorna finns i `tests/company-data-production-audit.sql` och `tests/company-data-denominator-audit.sql`. Urvalscachens medlemskap jämfördes med de oberoende sätes-/verksamhetsvillkoren utan skillnader.

Slutkontrollerna gav 0 fel i full arbetsställenämnare, aktiva historikreferenser, viktsummor, omsättningssummor, kvoter, proveniens och källpaketens existens. Alla arbetsställeposter är markerade som skattningar och inga koncernposter används som företagsbokslut. RLS är påslaget för alla nya tabeller och källbucket är privat. Totalt finns 10 435 senaste-pekare i lagringen: åtta avser företag som har lämnat det aktuella urvalet och bevaras som tidigare verifierad information, utan att räknas in i dagens täckning.

34 Python-tester och tre Node-testfall för API:s felhantering passerade lokalt. Cacheåteruppbyggnaden passerade transaktionstestet utan bestående ändringar. Katalog-/urvalshashen var oförändrad under den lyckade importens slutkontroll, med `source_archives=1473`, `archives_remaining=0` och `scope_changed_during_run=false`.

Två redan arkiverade verkliga rapporter lästes i projektmiljön: ett företag med flera verksamma svenska arbetsställen inklusive arbetsställe utanför Norrbotten, samt ett bokslut med negativa tillgångar. Paket- och XHTML-SHA256 stämde i båda fallen. Nettoomsättning, tillgångar och faktaproveniens stämde, inklusive context, scale och avrundning. Negativa tillgångar hade uttryckligen `sign="-"` i originalet. Omkörning av parsern gav samma värden. Detta är ett riktat stickprov, inte en oberoende manuell granskning av alla 10 427 rapporter.

**Företagsboksluten är verifierade mot sina källor; omsättning per arbetsställe är en uppskattning med `is_estimate=true`.** 9 160 bokslut med fördelning använder aktuell struktur för ett äldre bokslut, tre historisk observerad struktur. Historikgrund är fortfarande en approximation. Personalintervallens mittpunkter behöver inte avspegla var försäljning eller förädlingsvärde faktiskt uppstår.

## Historik, uppdateringar och fortsatt kontroll

Profiler: 1 828 382 JE och 1 923 504 AE, totalt 3 751 886 aktuella profiler och 3 751 970 historikversioner vid kontrollen. Två fullbordade profilreleaser finns. Nästa release skapade 102 versioner och uppdaterade 260 kontakter; första baslinjen fick inga påhittade historiska flyttdatum. Telefonnummer/e-post sparas fortsatt bara som senaste kontakt.

Migration 0053 är manuellt applicerad och ska inte läggas i Drizzle-journalen för automatisk återapplicering. Återuppbyggnad av urvalscachen provades i en transaktion och rullades tillbaka. Den ordinarie återstarten använde bestående arkiv- och företagsmarkörer, upptäckte fyra nya arkiv och kunde slutföras. Schemat för bokslut är fortsatt var fjärde timme; profiler följer lyckad AFR-kärnsynk. En framtida schemakörning är inte testad i förväg, men samma importväg används och status måste fortsätta följas.

Nästa kontroll: läs aktuell `company_data_coverage()`, `data_source_state` och senaste Actions-logg. Noll `pending` måste bedömas tillsammans med full aktuell arkivkatalog och oförändrat urval; det räcker inte ensamt. Karantänfallen behöver framtida taxonomi-/tolkningsarbete om täckningen ska höjas. Inga personalkostnader, konkurskällor, JobTech eller Vinnova har lagts till.

## Slutlig publicering och upprepad körning

PR [#97](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/pull/97) är mergad till `main`, mergecommit `1ef8d86ca9be37b34cd362970b0bf4aacc07af41`. GitHub-testkörning [43882938464](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/43882938464) passerade både Python- och Node-testerna.

Den efterföljande importkörningen [43883074999](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/43883074999) avslutades också med **success** 2026-11-16 15:12:56 svensk tid: samma 10 427 bokslut, 1 473 källarkiv, 0 väntande kandidater, 0 återstående arkiv och oförändrat urval. Detta verifierar den upprepade driftvägen efter fullimporten. Återförsöken har dessutom separata felinjektionstester; framtida externa källavbrott kan inte garanteras bort.

API-publicering startades med deployment `ac175711-09ad-467e-8caa-f0b479eee3b9`. Lovables publiceringspanel kontrollerades efteråt: **Published**, med **Publish changes** inaktiverad och PR #97 som aktuell förhandsversion. Den publicerade webbplatsen svarade HTTP 200. Ingen ny publik företagsvy har skapats.

Slutlig arbetsställeavstämning omfattade även historiska strukturer och gav 0 nämnarskillnader. Kvarvarande kvalitetsbortfall är redovisade ovan; de är inte en väntande importkö. Den ordinarie AFR-körningen 43865929818 pågick ännu vid slutkontrollen och nästa källdatum ska följas via den vanliga schemaläggningen.
