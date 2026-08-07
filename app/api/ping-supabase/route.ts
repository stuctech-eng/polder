import { NextResponse } from "next/server";

/**
 * Keep-alive voor Supabase (gratis tier pauzeert na 7 dagen inactiviteit).
 * Wordt aangeroepen door de Vercel Cron Job in vercel.json — geen gevoelige
 * data, alleen een lichte request om Supabase 'wakker' te houden.
 */
export async function GET() {
  try {
    // Service-role key i.p.v. anon-key: het kale /rest/v1/-pad accepteert
    // alleen de secret key (zie diagnose), en een service-role query op een
    // concrete tabel werkt sowieso gegarandeerd (bypast RLS/GRANT-gedoe).
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/restaurants?select=id&limit=1`,
      {
        headers: {
          apikey: process.env.SUPABASE_SERVICE_ROLE_KEY!,
          Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );
    return NextResponse.json({
      ok: response.ok,
      status: response.status,
      pingedAt: new Date().toISOString(),
    });
  } catch (err: any) {
    return NextResponse.json({ ok: false, error: err.message }, { status: 500 });
  }
}
