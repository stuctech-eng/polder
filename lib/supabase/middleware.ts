import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { parseAccess, type AccessStatus } from "@/lib/user-management/access";

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

  // Alleen voor navigatie (doorsturen met een melding). De beveiligingsgrens zit in requireRole (fail closed) en RLS.
  // Bij een fout of onbekende status sturen we hier NIET door: de pagina's weigeren dan zelf via requireRole.
  let access: AccessStatus = "onbekend";
  if (user) {
    const { data, error } = await supabase.rpc("my_access");
    access = parseAccess(data, error);
  }

  return { response, user, access };
}
