"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type Check = { label: string; status: "ok" | "warning" | "not_applicable"; detail?: string };
type Report = {
  date: string;
  totalRevenue: number;
  businessRevenue: number;
  nonBusinessRevenue: number;
  invoicesToday: number;
  openBusinessTabs: number;
  awaitingInvoice: number;
  pendingApproval: number;
  draftReceipts: number;
  checks: Check[];
  alreadyClosed: boolean;
  closedBy?: string | null;
  closedAt?: string | null;
};

export default function DailyClosingUI({ initialReport }: { initialReport: Report }) {
  const router = useRouter();
  const [report, setReport] = useState(initialReport);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const hasWarnings = report.checks.some((c) => c.status === "warning");

  async function handleClose() {
    if (hasWarnings && !confirm("Er zijn nog openstaande punten. Toch afsluiten?")) return;
    setLoading(true);
    setError(null);

    const response = await fetch("/api/daily-closing", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ date: report.date }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon dag niet afsluiten.");
      return;
    }

    router.refresh();
    setReport((prev) => ({ ...prev, alreadyClosed: true }));
  }

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <h1 className="text-xl font-semibold mb-1">Dagafsluiting</h1>
      <p className="text-sm text-neutral-500 mb-4">
        {new Date(report.date).toLocaleDateString("nl-NL", {
          weekday: "long",
          day: "numeric",
          month: "long",
        })}
      </p>

      <details className="mb-4 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-3">
        <summary className="px-3 py-2 text-sm font-medium text-neutral-700 cursor-pointer">
          Hoe werkt dit? ℹ️
        </summary>
        <div className="px-3 text-sm text-neutral-600 space-y-1">
          <p>
            Operationele controle vóór het afsluiten van de kassa — anders dan het
            Dashboard (dat is voor managementinformatie zoals maandomzet en trends).
          </p>
          <p>
            Een aantal controles staan op "n.v.t." omdat die functionaliteit nog niet
            gebouwd is (bijv. bonnen afkeuren, kassa-import) — geen valse ✓, gewoon
            eerlijk nog niet mogelijk.
          </p>
        </div>
      </details>

      {report.alreadyClosed && (
        <p className="text-sm text-green-700 bg-green-50 border border-green-200 rounded-lg p-3 mb-4">
          Deze dag is al afgesloten{report.closedBy ? ` door ${report.closedBy}` : ""}
          {report.closedAt ? ` om ${new Date(report.closedAt).toLocaleTimeString("nl-NL")}` : ""}.
        </p>
      )}

      <div className="grid grid-cols-2 gap-3 mb-6">
        <StatCard label="Totale omzet" value={`€${report.totalRevenue.toFixed(2)}`} />
        <StatCard label="Zakelijke omzet" value={`€${report.businessRevenue.toFixed(2)}`} />
        <StatCard label="Facturen vandaag" value={String(report.invoicesToday)} />
        <StatCard label="Nog te factureren" value={String(report.awaitingInvoice)} />
      </div>

      <section className="mb-6">
        <h2 className="text-sm font-semibold text-neutral-700 mb-2">Controles</h2>
        <ul className="space-y-1">
          {report.checks.map((check, i) => (
            <li
              key={i}
              className={`px-3 py-2 rounded-lg text-sm flex justify-between items-start gap-2 ${
                check.status === "ok"
                  ? "bg-green-50"
                  : check.status === "warning"
                    ? "bg-amber-50"
                    : "bg-neutral-100"
              }`}
            >
              <span>
                {check.status === "ok" && "✓ "}
                {check.status === "warning" && "⚠ "}
                {check.status === "not_applicable" && "— "}
                {check.label}
              </span>
              {check.detail && <span className="text-xs text-neutral-500 text-right">{check.detail}</span>}
            </li>
          ))}
        </ul>
      </section>

      {error && (
        <p className="text-sm text-red-600 mb-3" role="alert">
          {error}
        </p>
      )}

      {!report.alreadyClosed && (
        <button
          onClick={handleClose}
          disabled={loading}
          className="w-full min-h-touch rounded-lg bg-neutral-900 text-white font-medium disabled:opacity-50"
        >
          {loading ? "Bezig..." : "Dag afsluiten"}
        </button>
      )}
    </main>
  );
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="px-4 py-3 rounded-lg border border-neutral-200 bg-white">
      <div className="text-xs text-neutral-500">{label}</div>
      <div className="text-xl font-semibold mt-1">{value}</div>
    </div>
  );
}
