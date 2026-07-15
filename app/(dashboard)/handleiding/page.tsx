import { getCurrentUserContext } from "@/lib/user-management/session-context";
import { hasPermission } from "@/lib/user-management/permission-service";
import { PERMISSIONS, ROLE_LABELS, type UserRole } from "@/lib/user-management/role-helpers";
import { MANUAL_SECTIONS } from "./manual-content";

export default async function ManualPage() {
  const ctx = await getCurrentUserContext();
  const role = ctx?.role ?? null;

  // Sorteren, niet filteren: relevante secties voor de eigen rol bovenaan,
  // maar niets wordt verborgen — iedereen kan alles lezen (bewuste keuze).
  const relevantSections = MANUAL_SECTIONS.filter(
    (s) => s.relevantFor.length > 0 && role && s.relevantFor.some((p) => hasPermission(role!, p))
  );
  const generalSections = MANUAL_SECTIONS.filter((s) => s.relevantFor.length === 0);
  const otherSections = MANUAL_SECTIONS.filter(
    (s) => s.relevantFor.length > 0 && !relevantSections.includes(s)
  );

  const orderedSections = [...generalSections, ...relevantSections, ...otherSections];

  return (
    <main className="p-4 max-w-2xl mx-auto pb-12">
      <h1 className="text-xl font-semibold mb-1">Handleiding</h1>
      <p className="text-sm text-neutral-500 mb-6">
        {role
          ? `Bovenaan eerst wat bij jouw rol (${ROLE_LABELS[role]}) hoort — daaronder de rest, voor wie meer wil weten.`
          : "Volledige handleiding, voor iedereen toegankelijk."}
      </p>

      <div className="space-y-3 mb-8">
        {orderedSections.map((section) => (
          <details
            key={section.id}
            className="rounded-lg border border-neutral-200 bg-white open:pb-3"
            open={relevantSections.includes(section) || generalSections.includes(section)}
          >
            <summary className="px-4 py-3 font-medium cursor-pointer">
              {section.title}
              <span className="block text-xs font-normal text-neutral-500 mt-0.5">
                {section.summary}
              </span>
            </summary>
            <div className="px-4 space-y-3 mt-1">
              {section.steps.map((step, i) => (
                <div key={i} className="text-sm">
                  <div className="font-medium">{step.title}</div>
                  <div className="text-neutral-600">{step.detail}</div>
                </div>
              ))}
            </div>
          </details>
        ))}
      </div>

      <section>
        <h2 className="text-sm font-semibold text-neutral-700 mb-2">Rollen & rechten overzicht</h2>
        <p className="text-xs text-neutral-500 mb-2">
          Handig om aan personeel uit te leggen wie wat mag.
        </p>
        <div className="overflow-x-auto">
          <table className="w-full text-xs border-collapse">
            <thead>
              <tr className="border-b border-neutral-200">
                <th className="text-left py-2 pr-2">Permissie</th>
                {(["owner", "manager", "administratie", "bediening", "keuken"] as UserRole[]).map(
                  (r) => (
                    <th key={r} className="text-center py-2 px-1 whitespace-nowrap">
                      {ROLE_LABELS[r]}
                    </th>
                  )
                )}
              </tr>
            </thead>
            <tbody>
              {Object.entries(PERMISSIONS).map(([permission, roles]) => (
                <tr key={permission} className="border-b border-neutral-100">
                  <td className="py-2 pr-2 font-mono text-[10px]">{permission}</td>
                  {(["owner", "manager", "administratie", "bediening", "keuken"] as UserRole[]).map(
                    (r) => (
                      <td key={r} className="text-center py-2 px-1">
                        {(roles as readonly string[]).includes(r) ? "✅" : "—"}
                      </td>
                    )
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  );
}
