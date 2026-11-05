import PDFDocument from "pdfkit";

export async function createTransactionFixturePdf() {
  return new Promise((resolve, reject) => {
    const chunks = [];
    const fixedDate = new Date("2026-11-04T12:00:00.000Z");
    const document = new PDFDocument({
      size: "A4",
      margin: 72,
      compress: false,
      info: {
        Title: "Justificatif fictif PatriGest",
        Author: "PatriGest",
        Subject: "Fixture locale de validation",
        CreationDate: fixedDate,
        ModDate: fixedDate,
      },
    });
    document.on("data", (chunk) => chunks.push(chunk));
    document.on("error", reject);
    document.on("end", () => resolve(new Uint8Array(Buffer.concat(chunks))));
    document.font("Helvetica-Bold").fontSize(18).text("Justificatif fictif PatriGest");
    document.moveDown().font("Helvetica").fontSize(11).text(
      "Document local destiné exclusivement aux essais fonctionnels du module Transactions.",
    );
    document.end();
  });
}

export function hasReadablePdfStructure(bytes) {
  const content = Buffer.from(bytes).toString("latin1");
  return content.startsWith("%PDF-")
    && /\/Type\s*\/Pages\b/.test(content)
    && /\bxref\b/.test(content)
    && /\bstartxref\b/.test(content)
    && /%%EOF\s*$/.test(content);
}
