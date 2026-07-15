import { randomBytes } from "crypto";

/** Genereert een niet-raadbare token voor de publieke goedkeuringslink. */
export function generateApprovalToken(): string {
  return randomBytes(24).toString("hex");
}
