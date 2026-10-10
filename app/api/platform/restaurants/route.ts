import { NextResponse } from "next/server";
import { z } from "zod";
import { requirePlatformAdmin } from "@/lib/platform/platform-access";
import * as platform from "@/lib/platform/platform-service";
import { platformErrorResponse } from "@/lib/platform/route-errors";

const createSchema = z.object({
  name: z.string().trim().min(1, "Naam is verplicht").max(120, "Naam is te lang"),
});

export async function GET() {
  try {
    await requirePlatformAdmin();
    return NextResponse.json({ restaurants: await platform.listRestaurants() });
  } catch (err) {
    return platformErrorResponse(err);
  }
}

export async function POST(request: Request) {
  try {
    const ctx = await requirePlatformAdmin();
    const parsed = createSchema.safeParse(await request.json().catch(() => null));
    if (!parsed.success) {
      return NextResponse.json({ error: "Validatiefout", details: parsed.error.flatten() }, { status: 400 });
    }
    const restaurant = await platform.createRestaurant(ctx, parsed.data.name);
    return NextResponse.json({ restaurant }, { status: 201 });
  } catch (err) {
    return platformErrorResponse(err);
  }
}
