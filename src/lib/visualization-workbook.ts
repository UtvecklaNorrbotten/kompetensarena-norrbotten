import writeXlsxFile, { type SheetData } from "write-excel-file/browser";
import { downloadBlob, metadataRows, type VisualizationExport } from "./visualization-export";

export async function saveVisualizationWorkbook(data: VisualizationExport) {
  const header = (labels: string[]): SheetData[number] =>
    labels.map((value) => ({ value, fontWeight: "bold" }));

  const metadata = metadataRows(data);
  const blob = await writeXlsxFile([
    {
      sheet: "Statistik",
      data: [header(data.columns), ...data.rows],
      columns: data.columns.map((label) => ({ width: Math.max(18, label.length + 3) })),
      stickyRowsCount: 1,
    },
    {
      sheet: "Metadata",
      data: [
        header(metadata[0]!),
        ...metadata
          .slice(1)
          .map(([key, value]) => [
            key!,
            { value: value!, wrap: true, alignVertical: "top" as const },
          ]),
      ],
      columns: [{ width: 31 }, { width: 96 }],
      stickyRowsCount: 1,
    },
  ]).toBlob();
  downloadBlob(blob, `${data.filename}.xlsx`);
}
