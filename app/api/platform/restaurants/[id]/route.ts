import { NextResponse } from "next/server";
import { z } from "zod";
import { requirePlatformAdmin } from "@/lib/platform/platform-access";
import * as platform from "@/lib/platform/platform-service";
import { platformErrorResponse } from "@/lib/platform/route-errors";

const statusSchema = z.object({ isActive: z.boolean() });
const idSchema = z.string().uuid();

export async function PATCH(request: Request, { params }: { params: { id: string } }) {
  try {
    const ctx = await requirePlatformAdmin();
    const parsed = statusSchema.safeParse(await request.json().catch(() => null));
    if (!parsed.success || !idSchema.safeParse(params.id).success) {
      return NextResponse.json({ error: "Validatiefout" }, { status: 400 });
    }
    const result = await platform.setRestaurantActive(ctx, params.id, parsed.data.isActive);
    return NextResponse.json(result);
  } catch (err) {
    return platformErrorResponse(err);
  }
}
