import { createSupabaseServerClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import CompanyEditForm from "./edit-form";

export default async function CompanyDetailPage({
  params,
}: {
  params: { id: string };
}) {
  const supabase = createSupabaseServerClient();

  const { data: company, error } = await supabase
    .from("companies")
    .select("*")
    .eq("id", params.id)
    .single();

  if (error || !company) {
    notFound();
  }

  return <CompanyEditForm company={company} />;
}
