import type { SupabaseClient } from "@supabase/supabase-js";
import type { ApprovalMethod, ApprovalAttempt } from "./types";
import { pinProvider } from "./providers/pin-provider";
import { restaurantConfirmProvider } from "./providers/restaurant-confirm-provider";

const PROVIDERS = {
  pin: pinProvider,
  restaurant_confirms: restaurantConfirmProvider,
  // email/qr/signature volgen in Fase C/D — alleen hier toevoegen nodig,
  // geen wijziging aan de Receipt Manager of deze service.
} as const;

export interface ApprovalSettings {
  enabled: boolean;
  method: ApprovalMethod | null;
  autoLock: boolean;
  pinHash: string | null;
  pinSalt: string | null;
}

export async function getApprovalSettings(
  supabase: SupabaseClient,
  companyId: string
): Promise<ApprovalSettings> {
  const { data } = await supabase
    .from("approval_settings")
    .select("is_required, method, auto_lock, pin_hash, pin_salt")
    .eq("company_id", companyId)
    .maybeSingle();

  return {
    enabled: data?.is_required ?? false,
    method: (data?.method as ApprovalMethod) ?? null,
    autoLock: data?.auto_lock ?? true,
    pinHash: data?.pin_hash ?? null,
    pinSalt: data?.pin_salt ?? null,
  };
}

/**
 * De Receipt Manager (en elke andere aanroeper) kent alleen deze functie —
 * nooit een concrete provider. "Deze bon heeft goedkeuring nodig" is alles
 * wat de aanroeper weet, niet "gebruik PIN" (klant-instructie, sectie 10.7).
 */
export async function verifyApproval(
  settings: ApprovalSettings,
  attempt: ApprovalAttempt
): Promise<{ success: boolean; reason?: string }> {
  if (!settings.method) {
    return { success: false, reason: "Geen goedkeuringsmethode ingesteld" };
  }

  const provider = PROVIDERS[settings.method as keyof typeof PROVIDERS];
  if (!provider) {
    return { success: false, reason: `Onbekende goedkeuringsmethode: ${settings.method}` };
  }

  return provider.verify(attempt, { pinHash: settings.pinHash, pinSalt: settings.pinSalt });
}
