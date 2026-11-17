# Källval för ägar- och koncernstrukturer

Kontrollerat 2026-11-17. Detta är en källundersökning; ingen betaltjänst eller ny
ägardatainsamling har aktiverats och inga leverantörer har kontaktats.

## Rekommendation

Börja med **rapporterade bolagsrelationer i redan sparade årsredovisningar** och
komplettera med GLEIF Level 2. De ger en kostnadsfri, spårbar men ofullständig bas.
För bredare och mer aktuell koncerntäckning bör Roarings **Group Structure** och
Creditsafes **Controlling Owners** jämföras i ett representativt Norrbottensurval
innan leverantör väljs. Faktiska personägare är ett separat databehov.

Detta är ett förslag till källkombination, inte ett påstående om verifierad
Norrbottentäckning. Vi har inte produktionsåtkomst till de kommersiella tjänsterna.

| Källa | Innehåll / maskinell åtkomst | Kostnad och begränsning | Bedömning |
|---|---|---|---|
| Bolagsverkets sparade digitala årsredovisningar | Noter med moderföretag, dotterföretag och ibland ägarandelar; strukturerad iXBRL där begreppen finns | Ingen ny källavgift; kräver separat verifierad relationsextraktion; varierande rapportår och bortfall | Förstahandsbas, men inte ett fullständigt eller dagsaktuellt ägarregister |
| GLEIF Level 2 | Direkt och yttersta redovisningsmässigt konsoliderande moderföretag; API och dagliga filer | Kostnadsfritt; LEI-universum och rapporteringsundantag, inte alla svenska AB eller personägare | Bra komplement, särskilt för internationella koncerner |
| Roaring Group Structure | Koncernträd med moder-/dotterföretag, ägarandelar, AsOfDate och webhooks; `GET /se/company/group-structure/1.0/{companyId}` | Kommersiell åtkomst; faktisk täckning, produktpris och rätt att visa på publik webb måste bekräftas | Konkret kandidat för koncerninformation |
| Roaring Owner Structure | Faktiska direkta ägare, personer och företag, andelar/antal aktier; djup kan anges | Dokumentationen anger företag med omsättning **över 10 mkr** | Kan inte ensamt fylla behovet för alla småbolag. Gränsen gäller denna produkt; den är inte verifierad för Group Structure |
| Creditsafe Controlling Owners | Omedelbara och yttersta kontrollerande ägare samt koncernhierarki; Sverige stöds; `GET /compliance/controllingOwnership/{id}` | Avtal/pris/täckning och publiceringsrätt behöver bekräftas; svar innehåller bara vad leverantören känner till | Alternativ att jämföra med Roaring; ingen garanti för fullständig aktiebok |
| Bolagsverket – verklig huvudman | Fysisk person som ytterst äger/kontrollerar; separat åtkomstlösning och API | Behörighet och ändamål behöver prövas för Region Norrbotten; befintliga HVD-credentials visar inte rätt till denna tjänst | Separat personkopplat komplement; inte fullständigt register över alla aktieägare |
| Firmainfo Group | Dokumenterad relationstjänst från K2/K3-rapporter och GLEIF, med källdatum och stale-flagga | Leverantören anger uttryckligen `is_complete:false`, inga verkliga huvudmän och kostnad 2 enheter/anrop; planpris/publiceringsrätt ej utrett | Bekräftar möjligheten till rapportbaserat träd, men köper i huvudsak bearbetning av samma typer av källor som vi kan använda själva |
| SCB AFR / koncerninformation | AFR ger företags-/arbetsställestruktur och vissa klassificeringar; ingen verifierad fri koncernträdskälla identifierad i undersökningen | Eventuellt särskilt SCB-uttag måste klarläggas; statistiskt register är inte automatiskt öppet API-material | Inte utvald som källa till fullständiga ägarlänkar |

## Viktiga distinktioner

- Aktieägande, kontroll/verklig huvudman, koncernrelation och gemensam styrelse är
  olika relationer. Ingen av dem får automatiskt ersätta en annan.
- Årsredovisningens uppgift om det moderföretag som upprättar koncernredovisning
  för minsta koncernen är inte automatiskt det direkt ägande moderföretaget.
  Lagra rapporterad relationstyp, inte en gissad direkt ägarlänk.
- Två bolag med samma fysiska ägare är inte i sig en verifierad juridisk koncern.
- En utebliven relation betyder **okänd**, inte att bolaget är fristående.
- Ett bolagsträd räcker inte för att eliminera intern omsättning mellan bolag.
- Relationer bör sparas med organisationsnummer/LEI, relationstyp, andel där
  uttryckligen angiven, period/källdatum, källhash, observationstid och kvalitetsstatus.
  Rapportårets relation ska inte visas som säker dagens relation.
- Tillgång till API och rätt att återpublicera data på öppen webb är olika frågor.
  För en betalprodukt behövs uttryckligt besked om lagring, historik, cache,
  allmän visning och härledda regionala summeringar före köp/integrering.

## Nästa konkreta jämförelse

Efter bokslutskompletteringen: mät förekomsten av uttryckliga relationsuppgifter i
våra sparade rapporter och matchning mot LEI. Använd ett fryst urval med stora och
små AB, holdingbolag, offentligt ägda bolag, utländska moderföretag och företag som
saknar digital rapport. Begär sedan en testleverans/täckningsuppgift och offert för
**koncernträd respektive personägande separat**, med rätt till publik visning.
Inga kommersiella fullständighets- eller kostnadsantaganden bör byggas in före testet.

Roarings offentliga prissida visade 1 795 SEK/mån för Integrations Small vid kontrollen.
Det är **inte** en verifierad totalkostnad för våra koncern-/ägardataanrop: produktåtkomst,
förbrukning och publiceringslicens behöver specificeras. Creditsafe-pris för detta
användningsfall kunde inte fastställas från det granskade materialet.

## Primärkällor

- [Bolagsverket: noter i årsredovisningen](https://bolagsverket.se/foretag/aktiebolag/arsredovisningforaktiebolag/delarochbilagoriarsredovisningen/noteriarsredovisningen.773.html)
- [GLEIF Level 2](https://www.gleif.org/en/lei-data/access-and-use-lei-data/level-2-data-who-owns-whom)
- [GLEIF dagliga relationsfiler och rapporteringsundantag](https://www.gleif.org/en/lei-data/gleif-concatenated-file/download-the-concatenated-file)
- [Roaring Group Structure, teknisk dokumentation](https://developer.roaring.io/docs/apis/se-company-group-structure-1.0)
- [Roaring Owner Structure, inklusive omsättningsgräns](https://developer.roaring.io/docs/apis/se-company-owner-structure-1.0)
- [Roaring offentlig planprissättning](https://developer.roaring.io/pricing)
- [Creditsafe Controlling Owners](https://doc.creditsafe.com/connect-apis-catalog/product-catalog/controlling-owners)
- [Bolagsverket: hämta verklig huvudman](https://bolagsverket.se/apierochoppnadata/hamtaforetagsinformation/hamtainformationomverklighuvudman.6009.html)
- [Bolagsverket: API för företagsinformation, åtkomstförutsättningar](https://bolagsverket.se/apierochoppnadata/hamtaforetagsinformation/apiforatthamtaforetagsinformation.3988.html)
- [Firmainfo: koncernstruktur och täckningsförbehåll](https://www.firmainfo.se/docs/api/koncernstruktur/)
- [SCB: avgiftsfritt AFR-API](https://www.scb.se/vara-tjanster/bestall-data-och-statistik/foretagsregistret/avgiftsfria-uppgifter-i-foretagsregistret/)

Bolagsverkets webbplats gav en JavaScript-/robotkontroll vid direktöppning. De
angivna sakuppgifterna kunde läsas i sökmotorns indexerade officiella sidutdrag;
åtkomst-/avtalsdetaljer har därför inte presenterats som slutligt klarlagda.
