import { type NextRequest, NextResponse } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";
import { blockedReason, hasAccess } from "@/lib/user-management/access";

const PUBLIC_PATHS = ["/login", "/forgot-password", "/reset-password", "/approve", "/api/public-approve", "/api/ping-supabase"];
// Reset-password gebruikt zelf een (tijdelijke) sessie via de e-maillink —
// een ingelogde gebruiker mag hier dus niet worden weggestuurd.
const REDIRECT_IF_AUTHENTICATED = ["/login", "/forgot-password"];

export async function middleware(request: NextRequest) {
  const { response, user, access } = await updateSession(request);
  const blocked = user ? blockedReason(access) : null;

  const isPublicPath = PUBLIC_PATHS.some((path) =>
    request.nextUrl.pathname.startsWith(path)
  );

  // Niet ingelogd + geen publieke pagina → naar login (sectie 7.2 beveiliging)
  if (!user && !isPublicPath) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("redirectTo", request.nextUrl.pathname);
    return NextResponse.redirect(loginUrl);
  }

  // Gedeactiveerd account of uitgezet restaurant: wel een geldige sessie, maar geen toegang meer.
  // Alleen navigatie met een melding; de beveiliging zelf zit in requireRole en RLS.
  if (blocked && !isPublicPath) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set(blocked, "1");
    return NextResponse.redirect(loginUrl);
  }

  // Al ingelogd + op login/forgot-password → door naar root, die op basis van
  // rol bepaalt waar iemand moet landen (niet iedereen mag /companies zien)
  const isRedirectIfAuthPath = REDIRECT_IF_AUTHENTICATED.some((path) =>
    request.nextUrl.pathname.startsWith(path)
  );
  if (user && hasAccess(access) && isRedirectIfAuthPath) {
    return NextResponse.redirect(new URL("/", request.url));
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
