import { NextResponse } from "next/server";
import { requirePlatformAdmin } from "@/lib/platform/platform-access";
import * as platform from "@/lib/platform/platform-service";
import { platformErrorResponse } from "@/lib/platform/route-errors";

export async function GET() {
  try {
    await requirePlatformAdmin();
    return NextResponse.json({ log: await platform.listLog() });
  } catch (err) {
    return platformErrorResponse(err);
  }
}
