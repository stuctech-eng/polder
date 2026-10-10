import { NextResponse } from "next/server";
import { PermissionError } from "@/lib/user-management/permission-service";
import { PlatformError } from "./platform-service";

/** Eén foutafhandeling voor alle platformroutes: de melding is altijd zichtbaar in de app (sectie 15). */
export function platformErrorResponse(err: unknown) {
  if (err instanceof PermissionError || err instanceof PlatformError) {
    return NextResponse.json({ error: err.message }, { status: err.status });
  }
  return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
}
