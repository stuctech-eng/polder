import { NextResponse } from "next/server";

/**
 * Keep-alive voor Supabase (gratis tier pauzeert na 7 dagen inactiviteit).
 * Wordt aangeroepen door de Vercel Cron Job in vercel.json — geen gevoelige
 * data, alleen een lichte request om Supabase 'wakker' te houden.
 */
export async function GET() {
  try {
    const response = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/`, {
      headers: {
        apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        Authorization: `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY}`,
      },
    });
    const bodyText = await response.text();
    return NextResponse.json({
      ok: response.ok,
      status: response.status,
      pingedAt: new Date().toISOString(),
      // Tijdelijk voor diagnose — geeft de exacte Supabase-foutmelding terug
      supabaseResponse: bodyText.slice(0, 300),
      urlUsed: `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/`,
      hasAnonKey: !!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    });
  } catch (err: any) {
    return NextResponse.json({ ok: false, error: err.message }, { status: 500 });
  }
}
