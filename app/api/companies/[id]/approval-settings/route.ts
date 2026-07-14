import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import { hashPin } from "@/lib/approval/providers/pin-provider";
import { z } from "zod";

const settingsSchema = z.object({
  enabled: z.boolean(),
  method: z.enum(["pin", "restaurant_confirms"]).nullable(),
  autoLock: z.boolean().default(true),
  newPin: z.string().min(4, "PIN moet minimaal 4 cijfers zijn").optional(),
});

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();
  const { data, error } = await supabase
    .from("approval_settings")
    .select("is_required, method, auto_lock")
    .eq("company_id", params.id)
    .maybeSingle();
  // pin_hash/pin_salt bewust niet geselecteerd — nooit teruggeven aan de client.

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({
    settings: data
      ? {
          enabled: data.is_required,
          method: data.method,
          autoLock: data.auto_lock,
          hasPinSet: undefined, // apart afgehandeld hieronder
        }
      : null,
  });
}

export async function PUT(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    await requireRole("MANAGE_SETTINGS");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();

  // Tenant-isolatie: bevestig dat dit bedrijf bij het eigen restaurant hoort
  // (zelfde les als v1.20 — RLS op approval_settings checkt alleen company_id
  // via de eigen policy die al naar companies verwijst, maar expliciet
  // checken hier voorkomt verwarrende 404's dieper in de keten).
  const { data: company } = await supabase
    .from("companies")
    .select("id")
    .eq("id", params.id)
    .single();
  if (!company) {
    return NextResponse.json({ error: "Bedrijf niet gevonden" }, { status: 404 });
  }

  const body = await request.json();
  const parsed = settingsSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  if (parsed.data.enabled && parsed.data.method === "pin" && !parsed.data.newPin) {
    // Alleen verplicht als er nog geen PIN bestaat — check bestaande rij
    const { data: existing } = await supabase
      .from("approval_settings")
      .select("pin_hash")
      .eq("company_id", params.id)
      .maybeSingle();
    if (!existing?.pin_hash) {
      return NextResponse.json(
        { error: "Stel eerst een PIN in voordat je PIN-goedkeuring activeert" },
        { status: 400 }
      );
    }
  }

  const updates: Record<string, unknown> = {
    is_required: parsed.data.enabled,
    method: parsed.data.method,
    auto_lock: parsed.data.autoLock,
    updated_at: new Date().toISOString(),
  };

  if (parsed.data.newPin) {
    const { hash, salt } = hashPin(parsed.data.newPin);
    updates.pin_hash = hash;
    updates.pin_salt = salt;
  }

  const { data: existing } = await supabase
    .from("approval_settings")
    .select("id")
    .eq("company_id", params.id)
    .maybeSingle();

  let result;
  if (existing) {
    result = await supabase
      .from("approval_settings")
      .update(updates)
      .eq("id", existing.id)
      .select("is_required, method, auto_lock")
      .single();
  } else {
    result = await supabase
      .from("approval_settings")
      .insert({ company_id: params.id, ...updates })
      .select("is_required, method, auto_lock")
      .single();
  }

  if (result.error) {
    return NextResponse.json({ error: result.error.message }, { status: 500 });
  }

  return NextResponse.json({ settings: result.data });
}
