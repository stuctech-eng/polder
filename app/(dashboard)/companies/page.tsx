import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireRole, PermissionError } from "@/lib/user-management/permission-service";
import Link from "next/link";

export default async function CompaniesPage() {
  try {
    await requireRole("MANAGE_COMPANIES");
  } catch (err) {
    return (
      <main className="p-4 max-w-2xl mx-auto">
        <h1 className="text-xl font-semibold mb-4">Bedrijven</h1>
        <p className="text-sm text-red-600" role="alert">
          {err instanceof PermissionError ? err.message : "Onbekende fout"}
        </p>
      </main>
    );
  }

  const supabase = createSupabaseServerClient();

  const { data: companies, error } = await supabase
    .from("companies")
    .select("id, name, invoice_email, is_active")
    .order("name");

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl font-semibold">Bedrijven</h1>
        <Link
          href="/companies/new"
          className="min-h-touch min-w-touch px-4 flex items-center justify-center rounded-lg bg-neutral-900 text-white text-sm font-medium"
        >
          + Nieuw bedrijf
        </Link>
      </div>

      {error && (
        <p className="text-sm text-red-600 mb-4" role="alert">
          Fout bij ophalen bedrijven: {error.message}
        </p>
      )}

      <ul className="space-y-2">
        {companies?.map((company) => (
          <li key={company.id}>
            <Link
              href={`/companies/${company.id}`}
              className="block min-h-touch px-4 py-3 rounded-lg border border-neutral-200 bg-white active:bg-neutral-100"
            >
              <div className="font-medium">{company.name}</div>
              {company.invoice_email && (
                <div className="text-sm text-neutral-500">{company.invoice_email}</div>
              )}
              {!company.is_active && (
                <span className="text-xs text-neutral-400">Inactief</span>
              )}
            </Link>
          </li>
        ))}
        {!companies?.length && !error && (
          <p className="text-neutral-500 text-sm py-8 text-center">
            Nog geen bedrijven. Voeg het eerste bedrijf toe.
          </p>
        )}
      </ul>
    </main>
  );
}
