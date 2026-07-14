import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Ververst de Supabase-sessie op elk request en geeft de bijgewerkte
 * response + de ingelogde gebruiker (indien aanwezig) terug.
 * Gebruikt door middleware.ts om routes te beschermen (sectie 7.2 beveiliging).
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({
    request: { headers: request.headers },
  });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          request.cookies.set({ name, value, ...options });
          response = NextResponse.next({ request: { headers: request.headers } });
          response.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          request.cookies.set({ name, value: "", ...options });
          response = NextResponse.next({ request: { headers: request.headers } });
          response.cookies.set({ name, value: "", ...options });
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  let isActive = true;
  if (user) {
    const { data: profile } = await supabase
      .from("users")
      .select("is_active")
      .eq("id", user.id)
      .maybeSingle();
    // Onbekend profiel (bijv. net uitgenodigd, nog niet gekoppeld) blokkeert niet vooraf —
    // dat wordt al elders afgevangen (bijv. "Geen restaurantprofiel gevonden" in routes).
    isActive = profile?.is_active !== false;
  }

  return { response, user, isActive };
}
