import { NextResponse } from "next/server";
import { z } from "zod";
import { requestPasswordReset } from "@/lib/auth/recovery";

const schema = z.object({ email: z.string().trim().email("Ongeldig e-mailadres") });

/** Herstelmail aanvragen via de server (zie lib/auth/recovery.ts). Publiek: de middleware laat dit pad door. */
export async function POST(request: Request) {
  const parsed = schema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: "Vul een geldig e-mailadres in." }, { status: 400 });
  }
  const { error } = await requestPasswordReset(parsed.data.email);
  if (error) {
    // Zichtbaar in de app (sectie 15), bijv. de wachttijd tussen twee aanvragen.
    return NextResponse.json({ error: `Herstelmail kon niet worden verstuurd: ${error}` }, { status: 500 });
  }
  return NextResponse.json({ ok: true });
}
