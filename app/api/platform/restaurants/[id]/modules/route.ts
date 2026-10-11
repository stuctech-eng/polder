import { NextResponse } from "next/server";
import { z } from "zod";
import { requirePlatformAdmin } from "@/lib/platform/platform-access";
import * as platform from "@/lib/platform/platform-service";
import { platformErrorResponse } from "@/lib/platform/route-errors";
import { isFeatureKey } from "@/lib/features/features";

const moduleSchema = z.object({ feature: z.string().refine(isFeatureKey, "Onbekende module"), enabled: z.boolean() });
const idSchema = z.string().uuid();

/** Module aan/uit voor een restaurant. Alleen platformbeheer; de databasefunctie controleert de beheerder ook zelf. */
export async function PATCH(request: Request, { params }: { params: { id: string } }) {
  try {
    const ctx = await requirePlatformAdmin();
    const parsed = moduleSchema.safeParse(await request.json().catch(() => null));
    if (!parsed.success || !idSchema.safeParse(params.id).success || !isFeatureKey(parsed.data.feature)) {
      return NextResponse.json({ error: "Validatiefout" }, { status: 400 });
    }
    const result = await platform.setModule(ctx, params.id, parsed.data.feature, parsed.data.enabled);
    return NextResponse.json(result);
  } catch (err) {
    return platformErrorResponse(err);
  }
}
