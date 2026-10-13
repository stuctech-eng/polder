import { createSupabaseAdminClient } from "@/lib/supabase/admin";

/**
 * PIN-gegevens (hash + salt) van een bedrijf — ALLEEN op de server (hardening stap 12, architecture 13.24).
 * Sinds migratie 0035 kan geen gebruikerssessie pin_hash/pin_salt lezen; deze functies lezen ze met de service-sleutel.
 * Aanroepvoorwaarden (de aanroeper is verantwoordelijk):
 *  - eerst requireRole (APPROVE_RECEIPTS resp. MANAGE_SETTINGS);
 *  - het bedrijf komt uit een rij die eerst via de GEBRUIKERSsessie is gelezen (RLS: eigen restaurant);
 *  - hash en salt nooit in een response, logregel of foutmelding.
 * Fail closed: bij elke leesfout een ApprovalPinError (nooit "geen PIN" aannemen).
 */
export class ApprovalPinError extends Error {
  constructor() {
    super("PIN-gegevens konden niet worden gelezen");
  }
}

export interface ApprovalPin {
  pinHash: string | null;
  pinSalt: string | null;
}

export async function getApprovalPin(companyId: string): Promise<ApprovalPin> {
  try {
    const admin = createSupabaseAdminClient();
    const { data, error } = await admin
      .from("approval_settings")
      .select("pin_hash, pin_salt")
      .eq("company_id", companyId)
      .maybeSingle();
    if (error) throw new ApprovalPinError();
    return { pinHash: (data?.pin_hash as string | null) ?? null, pinSalt: (data?.pin_salt as string | null) ?? null };
  } catch {
    throw new ApprovalPinError();
  }
}

/** Alleen ja/nee: is er voor dit bedrijf al een PIN ingesteld? */
export async function hasApprovalPin(companyId: string): Promise<boolean> {
  const pin = await getApprovalPin(companyId);
  return !!pin.pinHash;
}
