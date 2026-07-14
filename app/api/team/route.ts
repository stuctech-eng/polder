import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import * as teamService from "@/lib/user-management/team-service";
import { z } from "zod";

const inviteSchema = z.object({
  email: z.string().email("Ongeldig e-mailadres"),
  fullName: z.string().min(1, "Naam is verplicht"),
  role: z.enum(["owner", "manager", "administratie", "bediening", "keuken"]),
});

export async function GET() {
  try {
    const ctx = await requireRole("MANAGE_TEAM");
    const supabase = createSupabaseServerClient();
    const team = await teamService.listTeam(supabase, ctx.restaurantId);
    return NextResponse.json({ team });
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const ctx = await requireRole("MANAGE_TEAM");
    const body = await request.json();
    const parsed = inviteSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { error: "Validatiefout", details: parsed.error.flatten() },
        { status: 400 }
      );
    }

    const supabase = createSupabaseServerClient();
    const newUser = await teamService.inviteUser(supabase, ctx, parsed.data);
    return NextResponse.json({ user: newUser }, { status: 201 });
  } catch (err: any) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: err.message || "Onbekende fout" }, { status: 500 });
  }
}
