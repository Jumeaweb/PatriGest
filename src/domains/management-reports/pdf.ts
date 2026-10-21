import PDFDocument from "pdfkit";
import path from "node:path";
import type { ManagementReportPreview } from "./preview-model";
import type { ManagementReportPdfMode } from "./document-helpers";

const fontPackageFile = (...segments: string[]) => path.join(process.cwd(), "node_modules", "@expo-google-fonts", "noto-sans", ...segments);
const FONT_REGULAR = fontPackageFile("400Regular", "NotoSans_400Regular.ttf");
const FONT_BOLD = fontPackageFile("700Bold", "NotoSans_700Bold.ttf");
const REGULAR = "NotoSans";
const BOLD = "NotoSansBold";

const PAGE_BOTTOM = 785;
const LEFT = 42;
const WIDTH = 511;
const BLUE = "#1D4ED8";
const DARK = "#0F172A";
const MUTED = "#64748B";
const BORDER = "#CBD5E1";

const date = (value: string | null | undefined) =>
  value
    ? new Intl.DateTimeFormat("fr-FR", { timeZone: "UTC" }).format(
        new Date(`${value}T00:00:00Z`),
      )
    : "Non renseigné";
const money = (value: number | null) =>
  value === null
    ? "Indisponible"
    : new Intl.NumberFormat("fr-FR", {
        style: "currency",
        currency: "EUR",
      })
        .format(value)
        .replace(/[\u00a0\u202f]/g, " ");
const yesNo = (value: boolean | null) =>
  value === null ? "Non renseigné" : value ? "Oui" : "Non";
const join = (values: Array<string | null | undefined>) =>
  values.filter(Boolean).join(", ") || "Non renseigné";

function addPageHeader(doc: PDFKit.PDFDocument, year: number, mode: ManagementReportPdfMode) {
  if (mode === "draft") {
    doc.save();
    doc.fillColor("#64748B").fillOpacity(0.1).font(BOLD).fontSize(76);
    doc.rotate(-35, { origin: [297.5, 421] });
    doc.text("PROJET", 65, 365, { width: 465, align: "center", lineBreak: false });
    doc.restore();
  }
  doc
    .font(BOLD)
    .fontSize(8)
    .fillColor(MUTED)
    .text(`COMPTE DE GESTION - ANNEXE 1 - ${year}`, LEFT, 24, {
      width: WIDTH,
      align: "right",
      lineBreak: false,
    });
  doc.moveTo(LEFT, 39).lineTo(LEFT + WIDTH, 39).strokeColor(BORDER).stroke();
  if (mode === "draft") {
    doc.font(BOLD).fontSize(7.5).fillColor("#B45309").text(
      "DOCUMENT DE TRAVAIL — NON FINALISÉ",
      LEFT,
      42,
      { width: WIDTH, align: "center", lineBreak: false },
    );
  }
  doc.y = 52;
}

function ensure(doc: PDFKit.PDFDocument, height: number) {
  if (doc.y + height > PAGE_BOTTOM) doc.addPage();
}

function section(doc: PDFKit.PDFDocument, title: string) {
  ensure(doc, 55);
  doc.moveDown(0.5);
  doc
    .roundedRect(LEFT, doc.y, WIDTH, 24, 4)
    .fill("#EFF6FF");
  doc
    .font(BOLD)
    .fontSize(11)
    .fillColor(BLUE)
    .text(title, LEFT + 8, doc.y + 6, { width: WIDTH - 16 });
  doc.y += 31;
}

function field(doc: PDFKit.PDFDocument, label: string, value: string) {
  const labelWidth = 170;
  const valueHeight = doc
    .font(REGULAR)
    .fontSize(9)
    .heightOfString(value, { width: WIDTH - labelWidth - 12 });
  const height = Math.max(18, valueHeight + 8);
  ensure(doc, height);
  const y = doc.y;
  doc
    .font(BOLD)
    .fontSize(8)
    .fillColor(MUTED)
    .text(label, LEFT, y + 4, { width: labelWidth });
  doc
    .font(REGULAR)
    .fontSize(9)
    .fillColor(DARK)
    .text(value, LEFT + labelWidth, y + 4, {
      width: WIDTH - labelWidth,
    });
  doc.moveTo(LEFT, y + height).lineTo(LEFT + WIDTH, y + height).strokeColor("#E2E8F0").stroke();
  doc.y = y + height;
}

function paragraph(doc: PDFKit.PDFDocument, text: string) {
  const height = doc.font(REGULAR).fontSize(9).heightOfString(text, { width: WIDTH });
  ensure(doc, height + 8);
  doc.fillColor(DARK).text(text, LEFT, doc.y, { width: WIDTH, lineGap: 2 });
  doc.moveDown(0.5);
}

function officialTable(
  doc: PDFKit.PDFDocument,
  title: string,
  groups: ManagementReportPreview["resources"]["sections"],
  totalLabel: string,
  total: number,
) {
  section(doc, title);
  const drawHeader = () => {
    ensure(doc, 22);
    const y = doc.y;
    doc.rect(LEFT, y, WIDTH, 20).fill("#F1F5F9");
    doc.font(BOLD).fontSize(8).fillColor(MUTED);
    doc.text("LIBELLE REGLEMENTAIRE", LEFT + 6, y + 6, { width: 380 });
    doc.text("MONTANT", LEFT + 390, y + 6, { width: 115, align: "right" });
    doc.y = y + 20;
  };
  drawHeader();
  for (const group of groups) {
    if (doc.y + 24 > PAGE_BOTTOM) {
      doc.addPage();
      drawHeader();
    }
    const groupY = doc.y;
    doc.rect(LEFT, groupY, WIDTH, 19).fill("#F8FAFC");
    doc.font(BOLD).fontSize(8.5).fillColor(DARK).text(group.label, LEFT + 6, groupY + 5, { width: WIDTH - 12 });
    doc.y = groupY + 19;
    for (const line of group.lines) {
      const labelHeight = doc.font(REGULAR).fontSize(8).heightOfString(line.label, { width: 378 });
      const rowHeight = Math.max(18, labelHeight + 7);
      if (doc.y + rowHeight > PAGE_BOTTOM) {
        doc.addPage();
        drawHeader();
      }
      const y = doc.y;
      doc.font(REGULAR).fontSize(8).fillColor(DARK).text(line.label, LEFT + 6, y + 4, { width: 378 });
      doc.font(BOLD).text(money(line.amount), LEFT + 390, y + 4, { width: 115, align: "right" });
      doc.moveTo(LEFT, y + rowHeight).lineTo(LEFT + WIDTH, y + rowHeight).strokeColor("#E2E8F0").stroke();
      doc.y = y + rowHeight;
    }
  }
  ensure(doc, 25);
  const y = doc.y;
  doc.rect(LEFT, y, WIDTH, 23).fill("#DBEAFE");
  doc.font(BOLD).fontSize(9).fillColor(DARK).text(totalLabel, LEFT + 6, y + 7, { width: 378 });
  doc.text(money(total), LEFT + 390, y + 7, { width: 115, align: "right" });
  doc.y = y + 28;
}

function simpleTable(
  doc: PDFKit.PDFDocument,
  headers: string[],
  rows: string[][],
  widths: number[],
) {
  const header = () => {
    ensure(doc, 22);
    const y = doc.y;
    doc.rect(LEFT, y, WIDTH, 20).fill("#F1F5F9");
    let x = LEFT;
    headers.forEach((text, index) => {
      doc.font(BOLD).fontSize(7.5).fillColor(MUTED).text(text, x + 4, y + 6, { width: widths[index] - 8, align: index > 1 ? "right" : "left" });
      x += widths[index];
    });
    doc.y = y + 20;
  };
  header();
  for (const row of rows) {
    const heights = row.map((text, index) => doc.font(REGULAR).fontSize(7.5).heightOfString(text, { width: widths[index] - 8 }));
    const height = Math.max(19, Math.max(...heights) + 7);
    if (doc.y + height > PAGE_BOTTOM) {
      doc.addPage();
      header();
    }
    const y = doc.y;
    let x = LEFT;
    row.forEach((text, index) => {
      doc.font(index >= 2 ? BOLD : REGULAR).fontSize(7.5).fillColor(DARK).text(text, x + 4, y + 4, { width: widths[index] - 8, align: index > 1 ? "right" : "left" });
      x += widths[index];
    });
    doc.moveTo(LEFT, y + height).lineTo(LEFT + WIDTH, y + height).strokeColor("#E2E8F0").stroke();
    doc.y = y + height;
  }
}

export async function generateManagementReportPdf(
  preview: ManagementReportPreview,
  options: { mode: ManagementReportPdfMode; deterministicCreationDate?: string },
): Promise<Buffer> {
  const deterministicCreationDate = options.deterministicCreationDate
    ? new Date(options.deterministicCreationDate)
    : null;
  if (deterministicCreationDate && Number.isNaN(deterministicCreationDate.getTime())) {
    throw new Error("La date déterministe du PDF est invalide.");
  }
  const doc = new PDFDocument({
    size: "A4",
    margins: { top: 52, right: 42, bottom: 42, left: 42 },
    bufferPages: true,
    info: {
      Title: `Compte de gestion ${preview.report.report_year}`,
      Author: "PatriGest",
      Subject: "Compte de gestion - Annexe 1",
      ...(deterministicCreationDate
        ? { CreationDate: deterministicCreationDate, ModDate: deterministicCreationDate }
        : {}),
    },
  });
  const chunks: Buffer[] = [];
  doc.registerFont(REGULAR, FONT_REGULAR);
  doc.registerFont(BOLD, FONT_BOLD);
  doc.on("data", (chunk: Buffer) => chunks.push(chunk));
  const completed = new Promise<Buffer>((resolve, reject) => {
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);
  });
  doc.on("pageAdded", () => addPageHeader(doc, preview.report.report_year, options.mode));
  addPageHeader(doc, preview.report.report_year, options.mode);

  doc.font(BOLD).fontSize(18).fillColor(DARK).text(`COMPTE DE GESTION DES BIENS POUR L'ANNÉE ${preview.report.report_year}`, LEFT, doc.y, { width: WIDTH, align: "center" });
  doc.font(REGULAR).fontSize(10).fillColor(MUTED).text("Annexe 1 de l'arrêté du 4 juillet 2024", { align: "center" });
  doc.moveDown(1);
  field(doc, "Année", String(preview.report.report_year));
  field(doc, "Période exacte", `${date(preview.report.period_start)} - ${date(preview.report.period_end)}`);
  field(doc, "Personne protégée", `${preview.person.last_name} ${preview.person.first_name}`);
  if (preview.measure?.case_reference) field(doc, "Numéro RG", preview.measure.case_reference);
  if (preview.measure?.court_cabinet) field(doc, "Cabinet", preview.measure.court_cabinet);

  section(doc, "I - PERSONNE PROTÉGÉE");
  field(doc, "Nom de naissance", preview.person.birth_name ?? "Non renseigné");
  field(doc, "Nom d'usage", preview.person.last_name);
  field(doc, "Prénoms", preview.person.first_name);
  field(doc, "Date et lieu de naissance", `${date(preview.person.birth_date)} - ${preview.person.birth_place ?? "Non renseigné"}`);
  field(doc, "Domicile", join([preview.person.address_line1, preview.person.address_line2, preview.person.postal_code, preview.person.city, preview.person.country]));
  field(doc, "Résidence distincte", join([preview.person.residence_address_line1, preview.person.residence_address_line2, preview.person.residence_postal_code, preview.person.residence_city, preview.person.residence_country]));
  field(doc, "Résidence modifiée pendant la période", yesNo(preview.confirmations.residenceChanged));
  field(doc, "Téléphone", preview.person.phone ?? "Non renseigné");
  field(doc, "Email", preview.person.email ?? "Non renseigné");

  section(doc, "II - MESURE DE PROTECTION");
  field(doc, "Type de mesure", preview.measureCorrespondence?.direct ? preview.measureCorrespondence.officialLabel : "Sans correspondance officielle directe");
  field(doc, "Ouverture / dernier renouvellement", date(preview.measure?.start_date));
  field(doc, "Personne chargée de la mesure", join([preview.measure?.representative_first_name, preview.measure?.representative_last_name]));
  field(doc, "Date de nomination", date(preview.measure?.representative_appointment_date));
  field(doc, "Adresse", join([preview.measure?.representative_address_line1, preview.measure?.representative_address_line2, preview.measure?.representative_postal_code, preview.measure?.representative_city, preview.measure?.representative_country]));
  field(doc, "Adresse modifiée pendant la période", yesNo(preview.confirmations.representativeAddressChanged));
  field(doc, "Téléphone", preview.measure?.representative_phone ?? "Non renseigné");
  field(doc, "Email", preview.measure?.representative_email ?? "Non renseigné");

  section(doc, "III - ACTES DE GESTION");
  field(doc, "Patrimoine immobilier confirmé", yesNo(preview.confirmations.realEstateConfirmed));
  field(doc, "Placements financiers confirmés", yesNo(preview.confirmations.financialInvestmentsConfirmed));
  field(doc, "Biens immobiliers pertinents", String(preview.properties.length));
  field(doc, "Événements immobiliers pendant la période", String(preview.propertyEvents.length));
  field(doc, "Placements suivis", String(preview.placements.length));
  for (const property of preview.properties) {
    field(doc, property.designation, `${property.type} - ${property.status}\n${property.address ?? "Adresse non renseignée"}\nValeur : ${money(property.estimatedValue)}${property.valuationDate ? ` au ${date(property.valuationDate)}` : ""}${property.disposalDate ? ` - cédé le ${date(property.disposalDate)}` : ""}`);
  }
  for (const event of preview.propertyEvents) paragraph(doc, `${date(event.date)} - ${event.property} - ${event.type}${event.amount !== null ? ` - ${money(event.amount)}` : ""}${event.description ? ` - ${event.description}` : ""}`);

  officialTable(doc, "A - LES RESSOURCES", preview.resources.sections, "TOTAL DES RESSOURCES (A)", preview.resources.total);
  officialTable(doc, "B - LES DÉPENSES", preview.expenses.sections, "TOTAL DES DÉPENSES (B)", preview.expenses.total);

  section(doc, "C - BALANCE DE GESTION DE L'ANNÉE");
  field(doc, "Solde de l'année précédente", money(preview.balance.start));
  field(doc, "Total des ressources de l'année (A)", money(preview.resources.total));
  field(doc, "Total des dépenses de l'année (B)", money(preview.expenses.total));
  field(doc, "Solde (A - B)", money(preview.result));

  section(doc, "D - SITUATION DES COMPTES ET LIVRETS BANCAIRES");
  paragraph(doc, "Pour chaque compte bancaire, une copie du dernier relevé bancaire doit être jointe séparément.");
  simpleTable(doc, ["COMPTE", "TYPE", "DEBUT", "RECETTES", "DEPENSES", "FIN"], preview.accounts.map((account) => [
    `${account.institution}\n${account.name}${account.reference ? ` - ${account.reference}` : ""}`,
    account.type,
    money(account.startBalance),
    money(account.income),
    money(account.expense),
    money(account.endBalance),
  ]), [132, 82, 74, 74, 74, 75]);
  if (preview.placements.length) {
    doc.moveDown(0.7);
    paragraph(doc, "Valeurs des placements retenues d'après les valorisations disponibles :");
    for (const placement of preview.placements) {
      field(doc, `${placement.name} - début`, `${money(placement.startValue)}${placement.startValueDate ? ` au ${date(placement.startValueDate)}` : ""}`);
      field(doc, `${placement.name} - fin`, `${money(placement.endValue)}${placement.endValueDate ? ` au ${date(placement.endValueDate)}` : ""}`);
    }
  }

  paragraph(doc, "Relevés et pièces disponibles :");
  for (const statement of preview.statements) {
    field(doc, statement.accountName, statement.endDate ? `Relevé au ${date(statement.endDate)}${statement.startDate ? ` - période du ${date(statement.startDate)} au ${date(statement.endDate)}` : ""} - PDF ${statement.hasDocument ? "présent" : "absent"}` : "Relevé indisponible");
  }

  section(doc, "E - DETTES EN COURS");
  if (!preview.debts.length) paragraph(doc, "Aucune dette pertinente pour la période.");
  for (const debt of preview.debts) {
    field(doc, debt.designation, `${debt.creditor} - ${debt.type} - ${debt.status}\nDette contractée le : ${date(debt.startDate)} - Durée initiale : ${debt.initialDurationMonths === null ? "Non renseignée" : `${debt.initialDurationMonths} mois`}\nMontant initial : ${money(debt.initialAmount)} - Mensualité : ${money(debt.monthlyPayment)}\nSituation au ${date(debt.balanceDate)} - Solde restant : ${money(debt.remainingBalance)}${debt.remainingDurationMonths !== null ? ` - ${debt.remainingDurationMonths} mois restants` : ""}`);
  }

  section(doc, "IV - OBSERVATIONS DE LA PERSONNE EN CHARGE DE LA MESURE");
  paragraph(doc, "Les éléments relatifs à la vie personnelle de la personne protégée doivent figurer dans un document distinct.");
  paragraph(doc, preview.observations || "Aucune observation patrimoniale.");

  section(doc, "V - SIGNATURES");
  paragraph(doc, "La ou les personne(s) en charge de la mesure de protection certifie(nt) le présent compte de gestion sincère et véritable.");
  field(doc, "Fait le", "");
  field(doc, "À", preview.signaturePlace ?? "");
  field(doc, "Nom", join([preview.measure?.representative_first_name, preview.measure?.representative_last_name]));
  ensure(doc, 70);
  doc.font(REGULAR).fontSize(9).fillColor(MUTED).text("Signature :", LEFT, doc.y);
  doc.rect(LEFT, doc.y + 8, WIDTH, 52).strokeColor(BORDER).stroke();
  doc.y += 65;

  const range = doc.bufferedPageRange();
  for (let index = range.start; index < range.start + range.count; index += 1) {
    doc.switchToPage(index);
    doc.font(REGULAR).fontSize(7.5).fillColor(MUTED).text(
      `PatriGest - Page ${index - range.start + 1} / ${range.count}`,
      LEFT,
      788,
      { width: WIDTH, align: "center", lineBreak: false },
    );
  }
  doc.end();
  return completed;
}
