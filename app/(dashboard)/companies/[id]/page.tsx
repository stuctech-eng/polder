import { createSupabaseServerClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import CompanyEditForm from "./edit-form";
import { DepartmentsSection, CostCentersSection, ProjectsSection } from "./sub-entities";

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

  const [{ data: departments }, { data: costCenters }, { data: projects }] = await Promise.all([
    supabase.from("departments").select("*").eq("company_id", params.id).order("name"),
    supabase.from("cost_centers").select("*").eq("company_id", params.id).order("name"),
    supabase.from("projects").select("*").eq("company_id", params.id).order("name"),
  ]);

  return (
    <>
      <CompanyEditForm company={company} />
      <div className="p-4 max-w-2xl mx-auto">
        <DepartmentsSection companyId={params.id} initialDepartments={departments ?? []} />
        <CostCentersSection
          companyId={params.id}
          initialCostCenters={costCenters ?? []}
          departments={departments ?? []}
        />
        <ProjectsSection companyId={params.id} initialProjects={projects ?? []} />
      </div>
    </>
  );
}
