import type { UkaRow } from "./uka-view";

export function exportFilename(indicator: string, university: string): string {
  return `${indicator}-${university}`
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9-]+/g, "-")
    .toLowerCase()
    .replace(/-+$/g, "");
}

function csvCell(value: string | number | null): string {
  // Text ska förbli text när CSV öppnas i Excel, även om en etikett börjar med =.
  let text =
    value === null ? "" : typeof value === "number" ? String(value).replace(".", ",") : value;
  if (typeof value === "string" && /^[\s]*[=+@-]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

/** Exakt samma rader som den öppningsbara tabellen, inklusive saknade värden. */
export function educationCsv(rows: UkaRow[], title: string, unit: string): string {
  const header = [
    "Mått",
    "Lärosäte",
    "Period",
    "Uppdelning",
    "Grupp",
    "Kön",
    "Värde",
    "Enhet",
    "Källa",
  ];
  const data = rows.map((r) => [
    title,
    r.university,
    r.period,
    r.breakdown,
    r.category.replaceAll("|", " · ") || "Samtliga",
    r.gender === "Total" ? "Samtliga" : r.gender,
    r.value,
    unit,
    "UKÄ",
  ]);
  return "\uFEFF" + [header, ...data].map((r) => r.map(csvCell).join(";")).join("\r\n");
}

export function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60000);
}

/** Radbryt hela etiketten, inklusive enstaka långa ord, utan att kasta tecken. */
export function wrapChartLabel(text: string, maxChars = 28): string[] {
  const lines: string[] = [];
  let current = "";
  for (const word of text.split(/\s+/)) {
    if (current && current.length + word.length + 1 > maxChars) {
      lines.push(current);
      current = "";
    }
    let rest = word;
    while (rest.length > maxChars) {
      if (current) {
        lines.push(current);
        current = "";
      }
      lines.push(rest.slice(0, maxChars));
      rest = rest.slice(maxChars);
    }
    current = current ? `${current} ${rest}` : rest;
  }
  if (current) lines.push(current);
  return lines.length ? lines : [""];
}

export async function saveEducationPng(
  chart: SVGSVGElement | SVGSVGElement[],
  filename: string,
  title: string,
  notes: string[],
) {
  if (Array.isArray(chart)) {
    if (chart.length === 1) return saveEducationPng(chart[0]!, filename, title, notes);
    if (!chart.length) throw new Error("Figuren har inte laddats färdigt.");
    const ns = "http://www.w3.org/2000/svg";
    const combined = document.createElementNS(ns, "svg");
    let x = 0;
    let height = 0;
    for (const source of chart) {
      const width = source.viewBox.baseVal.width || source.getBoundingClientRect().width;
      const chartHeight = source.viewBox.baseVal.height || source.getBoundingClientRect().height;
      const clone = source.cloneNode(true) as SVGSVGElement;
      const originals = [source, ...source.querySelectorAll<SVGElement>("*")];
      const copies = [clone, ...clone.querySelectorAll<SVGElement>("*")];
      originals.forEach((element, i) => {
        const copy = copies[i];
        if (!copy) return;
        const style = getComputedStyle(element);
        for (const property of [
          "fill",
          "stroke",
          "stroke-width",
          "font-size",
          "font-weight",
          "opacity",
          "text-anchor",
          "dominant-baseline",
        ])
          copy.style.setProperty(property, style.getPropertyValue(property));
      });
      clone.setAttribute("x", String(x));
      clone.setAttribute("y", "30");
      const heading = document.createElementNS(ns, "text");
      heading.setAttribute("x", String(x + 16));
      heading.setAttribute("y", "22");
      heading.setAttribute(
        "fill",
        getComputedStyle(document.documentElement).getPropertyValue("--ink").trim(),
      );
      heading.setAttribute("font-size", "16");
      heading.textContent =
        source.closest("[data-export-title]")?.getAttribute("data-export-title") ?? "";
      combined.append(heading, clone);
      x += width + 24;
      height = Math.max(height, chartHeight + 30);
    }
    combined.setAttribute("width", String(x - 24));
    combined.setAttribute("height", String(height));
    combined.setAttribute("viewBox", `0 0 ${x - 24} ${height}`);
    combined.style.position = "absolute";
    combined.style.left = "-100000px";
    document.body.append(combined);
    try {
      await saveEducationPng(combined, filename, title, notes);
    } finally {
      combined.remove();
    }
    return;
  }
  await document.fonts.ready;
  const ns = "http://www.w3.org/2000/svg";
  const clone = chart.cloneNode(true) as SVGSVGElement;
  // SVG-exporten måste bära med sig sidans färger och typsnitt.
  const originals = [chart, ...chart.querySelectorAll<SVGElement>("*")];
  const copies = [clone, ...clone.querySelectorAll<SVGElement>("*")];
  for (let i = 0; i < originals.length; i++) {
    const original = originals[i];
    const copy = copies[i];
    if (!original || !copy) continue;
    const style = getComputedStyle(original);
    for (const property of [
      "fill",
      "stroke",
      "stroke-width",
      "font-size",
      "font-weight",
      "opacity",
      "text-anchor",
      "dominant-baseline",
    ])
      copy.style.setProperty(property, style.getPropertyValue(property));
    copy.style.fontFamily = "Arial, sans-serif";
  }
  clone.style.removeProperty("position");
  clone.style.removeProperty("left");
  const width = Math.ceil(chart.viewBox.baseVal.width || chart.getBoundingClientRect().width);
  const height = Math.ceil(chart.viewBox.baseVal.height || chart.getBoundingClientRect().height);
  if (!width || !height) throw new Error("Figuren har inte laddats färdigt.");
  const chars = Math.max(20, Math.floor((width - 48) / 8));
  const titles = wrapChartLabel(title, Math.max(18, Math.floor((width - 48) / 12)));
  const footnotes = notes.flatMap((note) => wrapChartLabel(note, chars));
  const top = 32 + titles.length * 28;
  const fullHeight = top + height + 28 + footnotes.length * 20;
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("xmlns", ns);
  svg.setAttribute("width", String(width));
  svg.setAttribute("height", String(fullHeight));
  svg.setAttribute("viewBox", `0 0 ${width} ${fullHeight}`);
  const background = document.createElementNS(ns, "rect");
  background.setAttribute("width", "100%");
  background.setAttribute("height", "100%");
  background.setAttribute(
    "fill",
    getComputedStyle(document.documentElement).getPropertyValue("--surface").trim(),
  );
  svg.append(background);
  function addText(line: string, y: number, size: number, weight: string) {
    const text = document.createElementNS(ns, "text");
    text.setAttribute("x", "24");
    text.setAttribute("y", String(y));
    text.setAttribute("font-family", "Arial, sans-serif");
    text.setAttribute("font-size", String(size));
    text.setAttribute("font-weight", weight);
    text.setAttribute(
      "fill",
      getComputedStyle(document.documentElement).getPropertyValue("--ink").trim(),
    );
    text.textContent = line;
    svg.append(text);
  }
  titles.forEach((line, i) => addText(line, 30 + i * 28, 22, "600"));
  clone.setAttribute("x", "0");
  clone.setAttribute("y", String(top));
  svg.append(clone);
  footnotes.forEach((line, i) => addText(line, top + height + 24 + i * 20, 14, "400"));
  const url = URL.createObjectURL(
    new Blob([new XMLSerializer().serializeToString(svg)], { type: "image/svg+xml;charset=utf-8" }),
  );
  try {
    const image = new Image();
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve();
      image.onerror = () => reject(new Error("Figuren kunde inte sparas."));
      image.src = url;
    });
    const scale = Math.min(2, 16000 / Math.max(width, fullHeight));
    const canvas = document.createElement("canvas");
    canvas.width = Math.ceil(width * scale);
    canvas.height = Math.ceil(fullHeight * scale);
    const context = canvas.getContext("2d");
    if (!context) throw new Error("Bildexport saknar stöd i webbläsaren.");
    context.scale(scale, scale);
    context.drawImage(image, 0, 0, width, fullHeight);
    const blob = await new Promise<Blob>((resolve, reject) =>
      canvas.toBlob(
        (b) => (b ? resolve(b) : reject(new Error("Figuren kunde inte sparas."))),
        "image/png",
      ),
    );
    downloadBlob(blob, `${filename}.png`);
  } finally {
    URL.revokeObjectURL(url);
  }
}
