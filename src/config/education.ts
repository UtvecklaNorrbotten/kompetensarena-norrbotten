export const educationSections = [
  {
    slug: "sokande-antagna",
    title: "Sökande och antagna",
    intro:
      "Hur stort är intresset för utbildningarna, och hur många erbjuds en plats? Här visas program som leder till yrkesexamen.",
  },
  {
    slug: "studenter",
    title: "Studenter",
    intro:
      "Följ utbildningsvolymen och hur många som börjar studera. Nybörjare och helårsstudenter beskriver olika delar av verksamheten.",
  },
  {
    slug: "examina",
    title: "Examina",
    intro: "Se hur många som har tagit examen och vilka examina utbildningen har lett till.",
  },
  {
    slug: "etablering",
    title: "Arbetsmarknad efter examen",
    intro:
      "Följ examinerades ställning på arbetsmarknaden 1–1,5 år efter examen. Uppföljningen kan därför inte beskriva de allra senaste examenskullarna.",
  },
] as const;

export const educationIndicators = [
  {
    id: "uka-forstahandssokande-yrkesprogram",
    section: "sokande-antagna",
    title: "Förstahandssökande",
    unit: "antal",
    ukaId: 13,
    explanation: "Behöriga sökande som har valt ett yrkesexamensprogram i första hand.",
    definition:
      "Förstahandssökande har rangordnat utbildningen först i sin ansökan. Här ingår de som är behöriga till utbildningen. Måttet avser intresse vid ansökan, inte hur många som senare börjar studera.",
  },
  {
    id: "uka-antagna-yrkesprogram",
    section: "sokande-antagna",
    title: "Antagna",
    unit: "antal",
    ukaId: 97,
    explanation: "Sökande som har erbjudits en plats på ett yrkesexamensprogram.",
    definition:
      "Att vara antagen innebär att ha erbjudits en utbildningsplats. Personen behöver inte ha påbörjat studierna. Antagna och nybörjare är därför olika mått.",
  },
  {
    id: "uka-soktryck-yrkesprogram",
    section: "sokande-antagna",
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
    section: "studenter",
    title: "Nybörjare på yrkesexamensprogram",
    unit: "antal",
    ukaId: 31,
    explanation: "Studenter som börjar på ett program som leder till yrkesexamen.",
    definition:
      "En yrkesexamen är knuten till ett särskilt yrkesområde, till exempel sjuksköterska, lärare eller civilingenjör. Nybörjare på program är ett annat mått än antagna och ska inte användas som ett direkt mått på hur många antagna som började.",
  },
  {
    id: "uka-hst",
    section: "studenter",
    title: "Helårsstudenter",
    unit: "HST",
    ukaId: 33,
    explanation: "Registrerad utbildningsvolym omräknad till heltidsstudier under ett år.",
    definition:
      "Helårsstudenter (HST) beräknas från registrerade högskolepoäng: 60 poäng motsvarar en helårsstudent. Måttet anger studiernas omfattning, inte antalet unika personer eller avklarade poäng.",
  },
  {
    id: "uka-examinerade",
    section: "examina",
    title: "Examinerade",
    unit: "antal",
    ukaId: 108,
    explanation: "Personer som har tagit examen under det angivna läsåret.",
    definition:
      "En person kan ta mer än en examen. Uppdelningar efter examen kan därför överlappa. Använd källans total när alla examinerade ska beskrivas, i stället för att summera examensgrupperna.",
  },
  {
    id: "uka-etablering",
    section: "etablering",
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
