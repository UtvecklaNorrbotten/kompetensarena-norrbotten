import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { MatchingMapPage } from "@/components/labour-market/MatchingMapPage";

export const Route = createFileRoute("/omraden/arbetsmarknad/matchning_/matchningskarta")({
  validateSearch: z.object({
    direction: z.enum(["education", "occupation"]).catch("education").default("education"),
    code: z.string().catch("").default(""),
    group: z.string().catch("").default(""),
  }),
  head: () => ({
    meta: [
      { title: "Matchningskartan – Kompetensarena Norrbotten" },
      {
        name: "description",
        content:
          "Utforska SCB:s matchningskarta: vilka utbildningar och yrken matchar, och hur vanliga är kombinationerna i Sverige?",
      },
    ],
  }),
  component: MatchingMapPage,
});
