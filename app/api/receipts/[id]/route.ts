import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { z } from "zod";

const updateSchema = z.object({
  receiptNumber: z.string().optional(),
  receiptDate: z.string().optional(),
  notes: z.string().optional(),
});

export async function PATCH(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Niet ingelogd" }, { status: 401 });
  }

  const body = await request.json();
  const parsed = updateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Validatiefout", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { data: profile } = await supabase
    .from("users")
    .select("restaurant_id")
    .eq("id", userData.user.id)
    .single();

  // Guardian Mode: zelfde bescherming als DELETE — een bon op een gefactureerde
  // rekening mag ook niet meer bewerkt worden (audit trail / factuur-integriteit).
  const { data: existingReceipt } = await supabase
    .from("receipts")
    .select("open_tab_id, status")
    .eq("id", params.id)
    .single();

  if (existingReceipt?.status === "locked") {
    return NextResponse.json(
      { error: "Bon is vergrendeld na goedkeuring en kan niet meer bewerkt worden" },
      { status: 400 }
    );
  }

  if (existingReceipt?.open_tab_id) {
    const { data: relatedTab } = await supabase
      .from("open_tabs")
      .select("status")
      .eq("id", existingReceipt.open_tab_id)
      .single();

    if (relatedTab?.status === "invoiced") {
      return NextResponse.json(
        { error: "Bon hoort bij een gefactureerde rekening en kan niet meer bewerkt worden" },
        { status: 400 }
      );
    }
  }

  const { data, error } = await supabase
    .from("receipts")
    .update({
      receipt_number: parsed.data.receiptNumber || null,
      receipt_date: parsed.data.receiptDate || undefined,
      notes: parsed.data.notes || null,
    })
    .eq("id", params.id)
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  if (profile) {
    await supabase.from("activity_log").insert({
      restaurant_id: profile.restaurant_id,
      user_id: userData.user.id,
      action: "wijzigde een bon",
      target_table: "receipts",
      target_id: data.id,
    });
  }

  return NextResponse.json({ receipt: data });
}

export async function DELETE(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Niet ingelogd" }, { status: 401 });
  }

  // Guardian Mode: impact-analyse — een bon mag nooit verwijderd worden zodra
  // de rekening al gefactureerd is (audit trail / factuur-integriteit).
  const { data: receipt } = await supabase
    .from("receipts")
    .select("open_tab_id, status")
    .eq("id", params.id)
    .single();

  if (!receipt) {
    return NextResponse.json({ error: "Bon niet gevonden" }, { status: 404 });
  }

  if (receipt.status === "locked") {
    return NextResponse.json(
      { error: "Bon is vergrendeld na goedkeuring en kan niet meer verwijderd worden" },
      { status: 400 }
    );
  }

  if (receipt.open_tab_id) {
    const { data: tab } = await supabase
      .from("open_tabs")
      .select("status")
      .eq("id", receipt.open_tab_id)
      .single();

    if (tab?.status === "invoiced") {
      return NextResponse.json(
        { error: "Bon hoort bij een gefactureerde rekening en kan niet meer verwijderd worden" },
        { status: 400 }
      );
    }
  }

  const { data: profile } = await supabase
    .from("users")
    .select("restaurant_id")
    .eq("id", userData.user.id)
    .single();

  const { error } = await supabase.from("receipts").delete().eq("id", params.id);
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  if (profile) {
    await supabase.from("activity_log").insert({
      restaurant_id: profile.restaurant_id,
      user_id: userData.user.id,
      action: "verwijderde een bon",
      target_table: "receipts",
      target_id: params.id,
    });
  }

  return NextResponse.json({ success: true });
}
 
