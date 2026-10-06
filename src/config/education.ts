export const educationSections = [
  {
    slug: "hogskolan",
    title: "Högskolan – studier, examina och arbetsmarknad",
    intro:
      "Följ utbildningens omfattning, antalet examinerade och etableringen på arbetsmarknaden efter examen.",
  },
  {
    slug: "yrkesexamensprogram",
    title: "Yrkesexamensprogram i högskolan",
    intro:
      "Här samlas sökande, antagna, söktryck och nybörjare på program som leder till yrkesexamen. Dessa är högskoleutbildningar, exempelvis till lärare, sjuksköterska eller ingenjör.",
  },
] as const;

export const educationIndicators = [
  {
    id: "uka-forstahandssokande-yrkesprogram",
    section: "yrkesexamensprogram",
    title: "Förstahandssökande",
    unit: "antal",
    ukaId: 13,
    explanation: "Behöriga sökande som har valt ett yrkesexamensprogram i första hand.",
    definition:
      "Förstahandssökande har rangordnat utbildningen först i sin ansökan. Här ingår de som är behöriga till utbildningen. Måttet avser intresse vid ansökan, inte hur många som senare börjar studera.",
  },
  {
    id: "uka-antagna-yrkesprogram",
    section: "yrkesexamensprogram",
    title: "Antagna",
    unit: "antal",
    ukaId: 97,
    explanation: "Sökande som har erbjudits en plats på ett yrkesexamensprogram.",
    definition:
      "Att vara antagen innebär att ha erbjudits en utbildningsplats. Personen behöver inte ha påbörjat studierna. Antagna och nybörjare är därför olika mått.",
  },
  {
    id: "uka-soktryck-yrkesprogram",
    section: "yrkesexamensprogram",
    title: "Söktryck",
    unit: "sökande per antagen",
    ukaId: 99,
    explanation:
      "Antal behöriga förstahandssökande per antagen. Ett högre värde visar större konkurrens om de erbjudna platserna.",
    definition:
      "Söktryck är behöriga förstahandssökande dividerat med antagna. Ett värde över 1 innebär fler behöriga förstahandssökande än antagna. Måttet beskriver intresse och antal antagna tillsammans; det mäter inte utbildningens kvalitet.",
  },
  {
    id: "uka-nyborjare-yrkesprogram",
    section: "yrkesexamensprogram",
    title: "Nybörjare på yrkesexamensprogram",
    unit: "antal",
    ukaId: 31,
    explanation: "Studenter som börjar på ett program som leder till yrkesexamen.",
    definition:
      "En yrkesexamen är knuten till ett särskilt yrkesområde, till exempel sjuksköterska, lärare eller civilingenjör. Nybörjare på program är ett annat mått än antagna och ska inte användas som ett direkt mått på hur många antagna som började.",
  },
  {
    id: "uka-hst",
    section: "hogskolan",
    title: "Helårsstudenter",
    unit: "HST",
    ukaId: 33,
    explanation: "Registrerad utbildningsvolym omräknad till heltidsstudier under ett år.",
    definition:
      "Helårsstudenter (HST) beräknas från registrerade högskolepoäng: 60 poäng motsvarar en helårsstudent. Måttet anger studiernas omfattning, inte antalet unika personer eller avklarade poäng.",
  },
  {
    id: "uka-examinerade",
    section: "hogskolan",
    title: "Examinerade",
    unit: "antal",
    ukaId: 108,
    explanation: "Personer som har tagit examen under det angivna läsåret.",
    definition:
      "En person kan ta mer än en examen. Uppdelningar efter examen kan därför överlappa. Använd källans total när alla examinerade ska beskrivas, i stället för att summera examensgrupperna.",
  },
  {
    id: "uka-etablering",
    section: "hogskolan",
    title: "Etablering på arbetsmarknaden",
    unit: "%",
    ukaId: 136,
    explanation:
      "Andel examinerade med etablerad ställning på arbetsmarknaden enligt UKÄ:s definition.",
    definition:
      "UKÄ följer upp arbetsmarknadsställningen 1–1,5 år efter examen. Etablerad ställning kräver bland annat sysselsättning, arbetsinkomst över en viss nivå och frånvaro av arbetslöshet. Det är ett striktare mått än att ha ett jobb och visar inte om arbetet motsvarar utbildningen eller finns i Norrbotten.",
  },
] as const;
export type EducationIndicator = (typeof educationIndicators)[number];
