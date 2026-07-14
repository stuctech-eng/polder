import { scryptSync, randomBytes, timingSafeEqual } from "crypto";
import type { ApprovalProvider, ApprovalAttempt, ApprovalVerificationResult } from "../types";

/**
 * PIN nooit plat opslaan. Gebruikt Node's ingebouwde crypto.scrypt (geen
 * extra dependency, geen native bindings — zelfde afweging als pdf-lib,
 * Vercel-compatibel puur JS/Node-stdlib).
 */
export function hashPin(pin: string): { hash: string; salt: string } {
  const salt = randomBytes(16).toString("hex");
  const hash = scryptSync(pin, salt, 64).toString("hex");
  return { hash, salt };
}

function verifyPin(pin: string, hash: string, salt: string): boolean {
  const attemptHash = scryptSync(pin, salt, 64);
  const storedHash = Buffer.from(hash, "hex");
  if (attemptHash.length !== storedHash.length) return false;
  return timingSafeEqual(attemptHash, storedHash);
}

export const pinProvider: ApprovalProvider = {
  method: "pin",
  async verify(
    attempt: ApprovalAttempt,
    settings: { pinHash?: string | null; pinSalt?: string | null }
  ): Promise<ApprovalVerificationResult> {
    if (!settings.pinHash || !settings.pinSalt) {
      return { success: false, reason: "Er is nog geen PIN ingesteld voor dit bedrijf" };
    }
    if (!attempt.credential) {
      return { success: false, reason: "PIN is verplicht" };
    }
    const valid = verifyPin(attempt.credential, settings.pinHash, settings.pinSalt);
    return valid ? { success: true } : { success: false, reason: "Onjuiste PIN" };
  },
};
