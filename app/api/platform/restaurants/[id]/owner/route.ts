import { NextResponse } from "next/server";
import { z } from "zod";
import { requirePlatformAdmin } from "@/lib/platform/platform-access";
import * as platform from "@/lib/platform/platform-service";
import { platformErrorResponse } from "@/lib/platform/route-errors";

const ownerSchema = z.object({
  email: z.string().trim().email("Ongeldig e-mailadres"),
  fullName: z.string().trim().min(1, "Naam is verplicht"),
});
const idSchema = z.string().uuid();

export async function POST(request: Request, { params }: { params: { id: string } }) {
  try {
    const ctx = await requirePlatformAdmin();
    const parsed = ownerSchema.safeParse(await request.json().catch(() => null));
    if (!parsed.success || !idSchema.safeParse(params.id).success) {
      return NextResponse.json({ error: "Validatiefout", details: parsed.success ? undefined : parsed.error.flatten() }, { status: 400 });
    }
    const result = await platform.inviteOwner(ctx, params.id, parsed.data.email, parsed.data.fullName);
    return NextResponse.json(result, { status: 201 });
  } catch (err) {
    return platformErrorResponse(err);
  }
}
