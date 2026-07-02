import { type NextRequest, NextResponse } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

const PUBLIC_PATHS = ["/login", "/forgot-password", "/reset-password"];
// Reset-password gebruikt zelf een (tijdelijke) sessie via de e-maillink —
// een ingelogde gebruiker mag hier dus niet worden weggestuurd.
const REDIRECT_IF_AUTHENTICATED = ["/login", "/forgot-password"];

export async function middleware(request: NextRequest) {
  const { response, user } = await updateSession(request);

  const isPublicPath = PUBLIC_PATHS.some((path) =>
    request.nextUrl.pathname.startsWith(path)
  );

  // Niet ingelogd + geen publieke pagina → naar login (sectie 7.2 beveiliging)
  if (!user && !isPublicPath) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("redirectTo", request.nextUrl.pathname);
    return NextResponse.redirect(loginUrl);
  }

  // Al ingelogd + op login/forgot-password → door naar bedrijvenoverzicht
  const isRedirectIfAuthPath = REDIRECT_IF_AUTHENTICATED.some((path) =>
    request.nextUrl.pathname.startsWith(path)
  );
  if (user && isRedirectIfAuthPath) {
    return NextResponse.redirect(new URL("/companies", request.url));
  }

  return response;
}

export const config = {
  matcher: [
    /*
     * Alle routes behalve statische assets en API-interne Next.js paden.
     */
    "/((?!_next/static|_next/image|favicon.ico|manifest.json).*)",
  ],
};
