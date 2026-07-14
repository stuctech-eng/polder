import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { z } from "zod";

const costCenterSchema = z.object({
  name: z.string().min(1, "Naam is verplicht"),
  code: z.string().optional(),
  departmentId: z.string().uuid().optional().or(z.literal("")),
});

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();
  const { data, error } = await supabase
    .from("cost_centers")
    .select("*")
    .eq("company_id", params.id)
    .order("name");

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({ costCenters: data });
}

export async function POST(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    await requireRole("MANAGE_COMPANIES");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();

  const body = await request.json();
  const parsed = costCenterSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { data, error } = await supabase
    .from("cost_centers")
    .insert({
      company_id: params.id,
      name: parsed.data.name,
      code: parsed.data.code || null,
      department_id: parsed.data.departmentId || null,
    })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ costCenter: data }, { status: 201 });
}
