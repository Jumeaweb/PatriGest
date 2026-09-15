export const MAX_PROOF_FILE_SIZE = 10 * 1024 * 1024;
export const PROOF_MIME_EXTENSIONS = new Map([
  ["application/pdf", "pdf"],
  ["image/jpeg", "jpg"],
  ["image/png", "png"],
]);

export class ProofFileError extends Error {}

export type PreparedProofFile = { bytes: Uint8Array; mimeType: string; extension: string; size: number };

export async function prepareProofFile(value: FormDataEntryValue | null, optional: boolean): Promise<PreparedProofFile | null> {
  if (optional && (value === null || value instanceof File && value.size === 0 && !value.name)) return null;
  if (!(value instanceof File) || value.size === 0) throw new ProofFileError("Sélectionnez un fichier non vide.");
  if (!PROOF_MIME_EXTENSIONS.has(value.type)) throw new ProofFileError("Utilisez un PDF, JPEG ou PNG.");
  if (value.size > MAX_PROOF_FILE_SIZE) throw new ProofFileError("Le justificatif ne doit pas dépasser 10 Mo.");
  const bytes = new Uint8Array(await value.arrayBuffer());
  const detected = detectProofMimeType(bytes);
  if (!detected || detected !== value.type) throw new ProofFileError("Le fichier ne correspond pas à un PDF, JPEG ou PNG valide.");
  return { bytes, mimeType: detected, extension: PROOF_MIME_EXTENSIONS.get(detected)!, size: value.size };
}

export function detectProofMimeType(bytes: Uint8Array) {
  if (bytes.length >= 5 && String.fromCharCode(...bytes.slice(0, 5)) === "%PDF-") return "application/pdf";
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length >= png.length && png.every((value, index) => bytes[index] === value)) return "image/png";
  return null;
}

export function buildProofFileName(reference: string, label: string, extension: string) {
  const safeLabel = label.normalize("NFKC").replace(/[<>:"/\\|?*\u0000-\u001F]/g, " ").replace(/\s+/g, " ").trim().slice(0, 90) || "Justificatif";
  return `${reference} - ${safeLabel}.${extension}`;
}
