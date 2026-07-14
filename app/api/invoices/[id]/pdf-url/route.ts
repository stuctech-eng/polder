import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";

export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    await requireRole("MANAGE_INVOICES");
  } catch (err) {
    if (err instanceof PermissionError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    return NextResponse.json({ error: "Onbekende fout" }, { status: 500 });
  }

  const supabase = createSupabaseServerClient();

  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Niet ingelogd" }, { status: 401 });
  }

  const { data: document, error } = await supabase
    .from("documents")
    .select("storage_path")
    .eq("related_table", "invoices")
    .eq("related_id", params.id)
    .eq("type", "invoice")
    .single();

  if (error || !document) {
    return NextResponse.json({ error: "Document niet gevonden" }, { status: 404 });
  }

  const { data: signedUrl, error: signError } = await supabase.storage
    .from("documents")
    .createSignedUrl(document.storage_path, 60 * 5); // 5 minuten geldig

  if (signError || !signedUrl) {
    return NextResponse.json(
      { error: signError?.message ?? "Kon geen downloadlink maken" },
      { status: 500 }
    );
  }

  return NextResponse.json({ url: signedUrl.signedUrl });
}
