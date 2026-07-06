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
        <details className="mb-4 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-3">
          <summary className="px-3 py-2 text-sm font-medium text-neutral-700 cursor-pointer">
            Hoe werkt dit? ℹ️
          </summary>
          <div className="px-3 text-sm text-neutral-600 space-y-2">
            <p>
              <strong>Afdeling, Kostenplaats en Project zijn optioneel</strong> — gebruik ze
              alleen als dit bedrijf daar behoefte aan heeft.
            </p>
            <p>
              Wanneer iemand van dit bedrijf op rekening komt eten, open je straks een{" "}
              <strong>Open Rekening</strong> en kies je dit bedrijf, en eventueel een
              afdeling/kostenplaats/project erbij. Zo weet je bij het factureren precies
              welke afdeling of welk project de kosten moet dragen.
            </p>
          </div>
        </details>

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
