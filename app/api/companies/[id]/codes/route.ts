import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { z } from "zod";

const companyCodeSchema = z.object({
  type: z.string().min(1, "Type is verplicht"),
  code: z.string().min(1, "Code is verplicht"),
  description: z.string().optional(),
});

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();
  const { data, error } = await supabase
    .from("company_codes")
    .select("*")
    .eq("company_id", params.id)
    .order("type")
    .order("code");

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({ companyCodes: data });
}

export async function POST(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Niet ingelogd" }, { status: 401 });
  }

  const body = await request.json();
  const parsed = companyCodeSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { data, error } = await supabase
    .from("company_codes")
    .insert({
      company_id: params.id,
      type: parsed.data.type,
      code: parsed.data.code,
      description: parsed.data.description || null,
    })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ companyCode: data }, { status: 201 });
}
