import { createSupabaseAdminClient } from "@/lib/supabase/admin";

/**
 * PIN-pogingen (stap 14a, migraties 0037-0039): hooguit 5 pogingen per 15 minuten per bedrijf, daarna 15 minuten blokkade.
 * De database telt en dwingt af (vanaf 0042 keurt ze een PIN-bon alleen goed met een juiste, verse reservering).
 * Aanroepvoorwaarden (de aanroeper is verantwoordelijk): eerst requireRole("APPROVE_RECEIPTS"), de bon via de
 * GEBRUIKERSsessie gelezen (RLS: eigen restaurant), en startPinAttempt VOOR het lezen van de PIN-hash.
 * Fail closed: elke fout of onverwachte uitkomst is een PinAttemptError (nooit "toegestaan" aannemen).
 */
export class PinAttemptError extends Error {
  constructor() {
    super("PIN-pogingen konden niet worden bijgehouden");
  }
}

export type PinAttemptStart =
  | { allowed: true; id: string; remaining: number; blockedUntil: string | null }
  | { allowed: false; reason: "geblokkeerd" | "ongeldig"; blockedUntil: string | null };

export type PinAttemptFinish = "ok" | "verlopen" | "al_afgerond" | "onbekend";

export async function startPinAttempt(companyId: string, receiptId: string): Promise<PinAttemptStart> {
  try {
    const admin = createSupabaseAdminClient();
    const { data, error } = await admin.rpc("pin_poging_start", { p_company: companyId, p_bon: receiptId });
    if (error || !data || typeof data !== "object") throw new PinAttemptError();
    const r = data as Record<string, unknown>;
    if (r.toegestaan === true && typeof r.id === "string" && typeof r.resterend === "number") {
      return { allowed: true, id: r.id, remaining: r.resterend, blockedUntil: (r.geblokkeerd_tot as string | null) ?? null };
    }
    if (r.toegestaan === false && (r.reden === "geblokkeerd" || r.reden === "ongeldig")) {
      return { allowed: false, reason: r.reden, blockedUntil: (r.geblokkeerd_tot as string | null) ?? null };
    }
    throw new PinAttemptError();
  } catch {
    throw new PinAttemptError();
  }
}

export async function finishPinAttempt(attemptId: string, correct: boolean): Promise<PinAttemptFinish> {
  try {
    const admin = createSupabaseAdminClient();
    const { data, error } = await admin.rpc("pin_poging_afronden", { p_id: attemptId, p_juist: correct });
    if (error || !["ok", "verlopen", "al_afgerond", "onbekend"].includes(data as string)) throw new PinAttemptError();
    return data as PinAttemptFinish;
  } catch {
    throw new PinAttemptError();
  }
}

/** Tijdstip als "HH:MM" (Nederlandse tijd) voor meldingen; leeg als onbekend. */
export function formatBlockedUntil(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Amsterdam" });
}
