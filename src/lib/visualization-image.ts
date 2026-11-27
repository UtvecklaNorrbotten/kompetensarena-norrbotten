import { toCanvas } from "html-to-image";
import { site } from "../config/site";
import {
  downloadBlob,
  filterText,
  sourceName,
  type VisualizationExport,
} from "./visualization-export";

const padding = 24;
const excluded =
  "[data-export-ignore], .recharts-tooltip-wrapper, .recharts-tooltip-cursor, .recharts-active-dot";

function wrapText(context: CanvasRenderingContext2D, text: string, width: number) {
  const lines: string[] = [];
  for (let line of text.split(/\r?\n/)) {
    while (context.measureText(line).width > width) {
      let end = line.length - 1;
      while (end > 1 && context.measureText(line.slice(0, end)).width > width) end--;
      const space = line.lastIndexOf(" ", end);
      if (space > 0) end = space;
      lines.push(line.slice(0, end));
      line = line.slice(end).trimStart();
    }
    if (line) lines.push(line);
  }
  return lines;
}

export async function saveVisualizationImage(parts: HTMLElement[], data: VisualizationExport) {
  if (!parts.length) throw new Error("Visualiseringen har inte laddats färdigt.");
  const sizes = parts.map((part) => {
    const { width, height } = part.getBoundingClientRect();
    return { width: Math.ceil(width), height: Math.ceil(height) };
  });
  if (sizes.some(({ width, height }) => !width || !height)) {
    throw new Error("Visualiseringen har inte laddats färdigt.");
  }

  const width = Math.max(520, ...sizes.map((size) => size.width + 2 * padding));
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Bildexport saknar stöd i webbläsaren.");

  type Caption = { text: string; font: string; height: number; color?: string; dashed?: boolean };
  const title = { text: data.title, font: "bold 24px Arial, sans-serif", height: 30 };
  const detail = (text: string): Caption => ({ text, font: "15px Arial, sans-serif", height: 21 });
  const captions = [
    title,
    ...[
      data.subtitle,
      filterText(data.filters),
      data.period && `Referensperiod: ${data.period}`,
      data.unit && `Enhet: ${data.unit}`,
    ]
      .filter((entry): entry is string => Boolean(entry))
      .map(detail),
    ...(data.legend ?? []).map(({ label, color, dashed }) => ({ ...detail(label), color, dashed })),
  ];
  const notes = [
    `Källa: ${sourceName(data.source)}${data.source.retrieved ? ` · Uttag ${data.source.retrieved.slice(0, 10)}` : ""}`,
    ...(data.notes ?? []),
    site.name,
  ].map(detail);
  const layout = (entries: Caption[]) =>
    entries.flatMap((entry) => {
      context.font = entry.font;
      return wrapText(context, entry.text, width - 2 * padding - (entry.color ? 36 : 0)).map(
        (text) => ({ ...entry, text }),
      );
    });
  const heading = layout(captions);
  const footer = layout(notes);
  const chartHeight = sizes.reduce((sum, size) => sum + size.height, 0);
  const height =
    4 * padding + chartHeight + [...heading, ...footer].reduce((sum, row) => sum + row.height, 0);
  const pixelRatio = Math.min(
    3,
    16000 / Math.max(width, height),
    Math.sqrt(16000000 / (width * height)),
  );

  // Capture the existing responsive markup, including mixed SVG/HTML in the flow diagram.
  const images = await Promise.all(
    parts.map((part, i) =>
      toCanvas(part, {
        ...sizes[i],
        pixelRatio,
        skipAutoScale: true,
        skipFonts: true,
        backgroundColor: "#fff",
        filter: (node) => !(node instanceof Element && node.matches(excluded)),
      }),
    ),
  );
  canvas.width = Math.ceil(width * pixelRatio);
  canvas.height = Math.ceil(height * pixelRatio);
  context.scale(pixelRatio, pixelRatio);
  context.fillStyle = "#fff";
  context.fillRect(0, 0, width, height);

  let y = padding;
  const drawText = ({ text, font, height, color, dashed }: Caption) => {
    context.font = font;
    context.textBaseline = "middle";
    context.fillStyle = "#20251f";
    context.fillText(text, padding + (color ? 36 : 0), y + height / 2);
    if (color) {
      const probe = document.createElement("span");
      probe.style.color = color;
      document.body.append(probe);
      context.strokeStyle = getComputedStyle(probe).color;
      probe.remove();
      context.lineWidth = 3;
      context.setLineDash(dashed ? [7, 4] : []);
      context.beginPath();
      context.moveTo(padding, y + height / 2);
      context.lineTo(padding + 26, y + height / 2);
      context.stroke();
    }
    y += height;
  };
  heading.forEach(drawText);
  y += padding;
  images.forEach((image, i) => {
    const size = sizes[i]!;
    context.drawImage(image, (width - size.width) / 2, y, size.width, size.height);
    y += size.height;
  });
  y += padding;
  footer.forEach(drawText);
  const blob = await new Promise<Blob>((resolve, reject) =>
    canvas.toBlob(
      (result) => (result ? resolve(result) : reject(new Error("Bilden kunde inte sparas."))),
      "image/png",
    ),
  );
  downloadBlob(blob, `${data.filename}.png`);
}
