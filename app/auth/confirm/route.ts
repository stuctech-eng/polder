import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { parseEmailLinkType, safeNextPath, type LinkFailure } from "@/lib/auth/email-link";

/**
 * Doel van de mail-links (wachtwoord herstellen en uitnodiging), zie lib/auth/email-link.ts.
 * Supabase-sjabloon: https://polder.vercel.app/auth/confirm?token_hash={{ .TokenHash }}&type=recovery (of type=invite)
 * Geldige link: de server zet de sessie (cookies) en stuurt door naar /reset-password om een wachtwoord te kiezen.
 * Ongeldige of verlopen link: door naar /reset-password met een zichtbare reden (sectie 15: fouten zichtbaar in de app).
 */
export async function GET(request: NextRequest) {
  const url = request.nextUrl;
  const tokenHash = url.searchParams.get("token_hash");
  const type = parseEmailLinkType(url.searchParams.get("type"));
  const next = safeNextPath(url.searchParams.get("next"));

  const fail = (reden: LinkFailure, detail?: string) => {
    const target = new URL("/reset-password", request.url);
    target.searchParams.set("link", reden);
    if (detail) target.searchParams.set("detail", detail.slice(0, 200));
    return NextResponse.redirect(target);
  };

  if (!tokenHash || !type) return fail("ontbreekt");

  const supabase = createSupabaseServerClient();
  const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
  if (error) return fail("ongeldig", error.message);

  return NextResponse.redirect(new URL(next, request.url));
}
