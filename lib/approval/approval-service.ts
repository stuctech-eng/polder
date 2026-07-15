import type { SupabaseClient } from "@supabase/supabase-js";
import type { ApprovalMethod, ApprovalAttempt } from "./types";
import { pinProvider } from "./providers/pin-provider";
import { restaurantConfirmProvider } from "./providers/restaurant-confirm-provider";
import { sendEmail } from "@/lib/email/email-service";

const PROVIDERS = {
  pin: pinProvider,
  restaurant_confirms: restaurantConfirmProvider,
  // email/qr gebruiken geen verify() — dat zijn token-link-flows via de
  // publieke goedkeuringspagina (app/approve/[token]), niet een credential
  // die een ingelogde gebruiker intikt. signature volgt in Fase D.
} as const;

export interface ApprovalSettings {
  enabled: boolean;
  method: ApprovalMethod | null;
  autoLock: boolean;
  pinHash: string | null;
  pinSalt: string | null;
  notifyEmail: string | null;
}

export async function getApprovalSettings(
  supabase: SupabaseClient,
  companyId: string
): Promise<ApprovalSettings> {
  const { data } = await supabase
    .from("approval_settings")
    .select("is_required, method, auto_lock, pin_hash, pin_salt, notify_email")
    .eq("company_id", companyId)
    .maybeSingle();

  return {
    enabled: data?.is_required ?? false,
    method: (data?.method as ApprovalMethod) ?? null,
    autoLock: data?.auto_lock ?? true,
    pinHash: data?.pin_hash ?? null,
    pinSalt: data?.pin_salt ?? null,
    notifyEmail: data?.notify_email ?? null,
  };
}

/**
 * Side-effect bij het AANVRAGEN van goedkeuring (niet bij het bevestigen).
 * Voor PIN/restaurant_confirms is dit een no-op (niets te versturen). Voor
 * E-mail stuurt dit de daadwerkelijke mail met de publieke goedkeuringslink.
 * QR heeft geen server-side actie nodig — de link wordt client-side als
 * afbeelding getoond (zie ApprovalBlock).
 */
export async function notifyApprovalRequested(params: {
  settings: ApprovalSettings;
  token: string;
  restaurantName: string;
  receiptTotal: number;
  baseUrl: string;
}): Promise<{ success: boolean; warning?: string }> {
  if (params.settings.method !== "email") {
    return { success: true };
  }
  if (!params.settings.notifyEmail) {
    return { success: false, warning: "Geen e-mailadres ingesteld voor goedkeuring" };
  }

  const approveUrl = `${params.baseUrl}/approve/${params.token}`;
  const result = await sendEmail({
    to: params.settings.notifyEmail,
    subject: `${params.restaurantName}: bon wacht op goedkeuring (€${params.receiptTotal.toFixed(2)})`,
    html: `
      <p>Er wacht een bon van €${params.receiptTotal.toFixed(2)} op jouw goedkeuring bij ${params.restaurantName}.</p>
      <p><a href="${approveUrl}">Klik hier om te bekijken en goed te keuren</a></p>
      <p style="color:#888;font-size:12px">Deze link is persoonlijk, deel 'm niet met anderen.</p>
    `,
  });

  if (!result.success) {
    return { success: false, warning: `Goedkeuringsmail kon niet verstuurd worden: ${result.error}` };
  }
  return { success: true };
}

/**
 * De Receipt Manager (en elke andere aanroeper) kent alleen deze functie —
 * nooit een concrete provider. "Deze bon heeft goedkeuring nodig" is alles
 * wat de aanroeper weet, niet "gebruik PIN" (klant-instructie, sectie 10.7).
 * Alleen voor credential-gebaseerde methoden (PIN/restaurant_confirms) —
 * email/qr lopen via de publieke token-route, niet via deze functie.
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
    return { success: false, reason: `Deze methode wordt niet via dit kanaal bevestigd: ${settings.method}` };
  }

  return provider.verify(attempt, { pinHash: settings.pinHash, pinSalt: settings.pinSalt });
}
