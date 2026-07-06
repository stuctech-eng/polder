import { PDFDocument, StandardFonts, rgb } from "pdf-lib";

export interface InvoiceLineItem {
  description: string;
  amount: number;
}

export interface InvoicePdfData {
  invoiceNumber: string;
  issuedAt: string;
  dueAt: string;
  restaurantName: string;
  companyName: string;
  companyAddress?: string | null;
  companyVatNumber?: string | null;
  lines: InvoiceLineItem[];
  subtotal: number;
  vatAmount: number;
  total: number;
}

/**
 * Document Engine — factuur-PDF generator (Fase 1: alleen factuur-type actief).
 * Generiek genoeg om later hergebruikt te worden voor creditfacturen/offertes
 * (blueprint sectie 2, Document Engine).
 */
export async function generateInvoicePdf(data: InvoicePdfData): Promise<Uint8Array> {
  const pdfDoc = await PDFDocument.create();
  const page = pdfDoc.addPage([595.28, 841.89]); // A4
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  const { width, height } = page.getSize();
  let y = height - 60;
  const marginX = 50;

  const drawText = (
    text: string,
    x: number,
    yPos: number,
    options: { bold?: boolean; size?: number } = {}
  ) => {
    page.drawText(text, {
      x,
      y: yPos,
      size: options.size ?? 10,
      font: options.bold ? fontBold : font,
      color: rgb(0.1, 0.1, 0.1),
    });
  };

  // Header
  drawText(data.restaurantName, marginX, y, { bold: true, size: 18 });
  y -= 30;
  drawText(`Factuur ${data.invoiceNumber}`, marginX, y, { bold: true, size: 13 });
  y -= 40;

  // Bedrijfsgegevens + factuurdata naast elkaar
  drawText("Aan:", marginX, y, { bold: true });
  drawText(`Factuurdatum: ${data.issuedAt}`, 350, y);
  y -= 15;
  drawText(data.companyName, marginX, y);
  drawText(`Vervaldatum: ${data.dueAt}`, 350, y);
  y -= 15;
  if (data.companyAddress) {
    drawText(data.companyAddress, marginX, y);
    y -= 15;
  }
  if (data.companyVatNumber) {
    drawText(`BTW: ${data.companyVatNumber}`, marginX, y);
    y -= 15;
  }

  y -= 25;

  // Tabelkop
  drawText("Omschrijving", marginX, y, { bold: true });
  drawText("Bedrag", 480, y, { bold: true });
  y -= 8;
  page.drawLine({
    start: { x: marginX, y },
    end: { x: width - marginX, y },
    thickness: 1,
    color: rgb(0.7, 0.7, 0.7),
  });
  y -= 18;

  for (const line of data.lines) {
    drawText(line.description, marginX, y);
    drawText(`€${line.amount.toFixed(2)}`, 480, y);
    y -= 18;
  }

  y -= 10;
  page.drawLine({
    start: { x: marginX, y },
    end: { x: width - marginX, y },
    thickness: 1,
    color: rgb(0.7, 0.7, 0.7),
  });
  y -= 20;

  drawText("Subtotaal", 380, y);
  drawText(`€${data.subtotal.toFixed(2)}`, 480, y);
  y -= 16;
  drawText("BTW", 380, y);
  drawText(`€${data.vatAmount.toFixed(2)}`, 480, y);
  y -= 16;
  drawText("Totaal", 380, y, { bold: true });
  drawText(`€${data.total.toFixed(2)}`, 480, y, { bold: true });

  return pdfDoc.save();
}
