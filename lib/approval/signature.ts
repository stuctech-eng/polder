/**
 * Handtekening van de klant (stap 14c, migraties 0043-0048). De klant tekent op het toestel van het restaurant; de bediening
 * start dit (MANAGE_RECEIPTS, geen APPROVE_RECEIPTS). De database (bon_ondertekenen) controleert alles opnieuw: rol, restaurant,
 * module, methode, bonstatus, bedrijf van de rekening en vingerafdruk. Deze grenzen zijn dezelfde als in de database, zodat de gebruiker de melding
 * meteen krijgt in plaats van na een ronde naar de server.
 */
export const SIGNER_NAME_MIN = 2;
export const SIGNER_NAME_MAX = 100;
export const SIGNATURE_MIN_LENGTH = 100;
export const SIGNATURE_MAX_LENGTH = 200000;
const SIGNATURE_PREFIX = "data:image/png;base64,";
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;
export const PNG_MAX_WIDTH = 2048;
export const PNG_MAX_HEIGHT = 1024;
const PNG_START = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52]; // handtekening + IHDR
const PNG_END = [0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]; // IEND

/**
 * Echte PNG, dezelfde regel als de database (png_geldig, migratie 0048): geldige base64, begint met de PNG-handtekening en
 * IHDR, breedte 1-2048 en hoogte 1-1024, eindigt op IEND; de hele data-URL 100-200000 tekens.
 */
export function isValidSignaturePng(value: string): boolean {
  if (value.length < SIGNATURE_MIN_LENGTH || value.length > SIGNATURE_MAX_LENGTH || !value.startsWith(SIGNATURE_PREFIX)) return false;
  const data = value.slice(SIGNATURE_PREFIX.length);
  if (!BASE64_PATTERN.test(data) || data.length % 4 !== 0) return false;
  let bin: string;
  try {
    bin = atob(data);
  } catch {
    return false;
  }
  if (bin.length < PNG_START.length + 8 + PNG_END.length) return false;
  const byte = (i: number) => bin.charCodeAt(i);
  if (PNG_START.some((v, i) => byte(i) !== v)) return false;
  if (PNG_END.some((v, i) => byte(bin.length - PNG_END.length + i) !== v)) return false;
  const width = byte(16) * 16777216 + byte(17) * 65536 + byte(18) * 256 + byte(19);
  const height = byte(20) * 16777216 + byte(21) * 65536 + byte(22) * 256 + byte(23);
  return width >= 1 && width <= PNG_MAX_WIDTH && height >= 1 && height <= PNG_MAX_HEIGHT;
}
const FINGERPRINT_PATTERN = /^[0-9a-f]{32}$/;

export interface SignatureInput {
  name: string;
  signature: string;
  fingerprint: string;
}

export type SignatureCheck = { ok: true; value: SignatureInput } | { ok: false; error: string };

export function checkSignatureInput(body: unknown): SignatureCheck {
  const b = (body ?? {}) as Record<string, unknown>;
  const name = typeof b.name === "string" ? b.name.trim() : "";
  const signature = typeof b.signature === "string" ? b.signature : "";
  const fingerprint = typeof b.fingerprint === "string" ? b.fingerprint : "";
  if (name.length < SIGNER_NAME_MIN || name.length > SIGNER_NAME_MAX) {
    return { ok: false, error: `Vul de naam van de klant in (${SIGNER_NAME_MIN} tot ${SIGNER_NAME_MAX} tekens).` };
  }
  if (!isValidSignaturePng(signature)) {
    return { ok: false, error: "Er is geen geldige handtekening gezet. Laat de klant opnieuw tekenen." };
  }
  if (!FINGERPRINT_PATTERN.test(fingerprint)) {
    return { ok: false, error: "De bon is niet goed geladen. Vernieuw de pagina en probeer het opnieuw." };
  }
  return { ok: true, value: { name, signature, fingerprint } };
}

/**
 * Rekening hoort nu bij een ander bedrijf dan waarvoor de bon is ingediend: zo niet te ondertekenen. De app kan het bedrijf
 * van een rekening niet wijzigen en een handtekeningbon niet afwijzen; herstel kan alleen de beheerder (zie architecture 13.27).
 */
export const COMPANY_MISMATCH =
  "Deze bon kan zo niet worden ondertekend: de rekening hoort nu bij een ander bedrijf dan waarvoor de bon is ingediend. Neem contact op met de beheerder.";

/** Databasefout van bon_ondertekenen -> HTTP-status en een duidelijke Nederlandse melding. Onbekend = 500, nooit "gelukt". */
export function signErrorResponse(error: { code?: string; message?: string }): { status: number; error: string } {
  const message = error.message ?? "";
  switch (error.code) {
    case "P0002":
      return { status: 404, error: "Bon niet gevonden." };
    case "42501":
      if (/Module staat uit/.test(message)) {
        return { status: 403, error: "De module Handtekening staat uit voor dit restaurant." };
      }
      return { status: 403, error: "Je hebt geen recht om een bon te laten ondertekenen." };
    case "55000":
      return { status: 409, error: "Deze bon wacht niet (meer) op een handtekening. Vernieuw de pagina." };
    case "22000":
      if (/Bedrijf/.test(message)) {
        return { status: 409, error: COMPANY_MISMATCH };
      }
      return { status: 409, error: "De bon is intussen gewijzigd. Vernieuw de pagina en laat de klant opnieuw tekenen." };
    case "22023":
      return { status: 400, error: /Naam/.test(message)
        ? `Vul de naam van de klant in (${SIGNER_NAME_MIN} tot ${SIGNER_NAME_MAX} tekens).`
        : "Er is geen geldige handtekening gezet. Laat de klant opnieuw tekenen." };
    default:
      return { status: 500, error: "Ondertekenen is niet gelukt. De bon is niet gewijzigd; probeer het opnieuw." };
  }
}
