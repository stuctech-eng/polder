import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import * as teamService from "@/lib/user-management/team-service";
import { z } from "zod";

const updateSchema = z.object({
  role: z.enum(["owner", "manager", "administratie", "bediening", "keuken"]).optional(),
  isActive: z.boolean().optional(),
});

export async function PATCH(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    const ctx = await requireRole("MANAGE_TEAM");
    const body = await request.json();
    const parsed = updateSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { error: "Validatiefout", details: parsed.error.flatten() },
        { status: 400 }
      );
    }

    const supabase = createSupabaseServerClient();
    let result;
    if (parsed.data.role) {
      result = await teamService.updateRole(supabase, ctx, params.id, parsed.data.role);
    }
    if (parsed.data.isActive !== undefined) {
      result = await teamService.setActive(supabase, ctx, params.id, parsed.data.isActive);
    }

    return NextResponse.json({ user: result });
  } catch (err: any) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: err.message || "Onbekende fout" }, { status: 400 });
  }
}

export async function DELETE(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    const ctx = await requireRole("MANAGE_TEAM");
    const supabase = createSupabaseServerClient();
    const { warning } = await teamService.removeUser(supabase, ctx, params.id);
    return NextResponse.json({ success: true, ...(warning ? { warning } : {}) });
  } catch (err: any) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: err.message || "Onbekende fout" }, { status: 400 });
  }
}
