"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

type Company = { id: string; name: string };
type Option = { id: string; name: string };

export default function NewOpenTabForm({ companies }: { companies: Company[] }) {
  const router = useRouter();
  const [companyId, setCompanyId] = useState("");
  const [departmentId, setDepartmentId] = useState("");
  const [costCenterId, setCostCenterId] = useState("");
  const [projectId, setProjectId] = useState("");
  const [tableNumber, setTableNumber] = useState("");
  const [guestCount, setGuestCount] = useState("");

  const [departments, setDepartments] = useState<Option[]>([]);
  const [costCenters, setCostCenters] = useState<Option[]>([]);
  const [projects, setProjects] = useState<Option[]>([]);

  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    setDepartmentId("");
    setCostCenterId("");
    setProjectId("");
    setDepartments([]);
    setCostCenters([]);
    setProjects([]);

    if (!companyId) return;

    Promise.all([
      fetch(`/api/companies/${companyId}/departments`).then((r) => r.json()),
      fetch(`/api/companies/${companyId}/cost-centers`).then((r) => r.json()),
      fetch(`/api/companies/${companyId}/projects`).then((r) => r.json()),
    ]).then(([d, c, p]) => {
      setDepartments(d.departments ?? []);
      setCostCenters(c.costCenters ?? []);
      setProjects(p.projects ?? []);
    });
  }, [companyId]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);

    const response = await fetch("/api/open-tabs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        companyId: companyId || undefined,
        departmentId: departmentId || undefined,
        costCenterId: costCenterId || undefined,
        projectId: projectId || undefined,
        tableNumber: tableNumber || undefined,
        guestCount: guestCount ? Number(guestCount) : undefined,
      }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Er ging iets mis. Probeer het opnieuw.");
      return;
    }

    router.push("/open-tabs");
    router.refresh();
  }

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/open-tabs" className="min-h-touch min-w-touch flex items-center justify-center text-neutral-500">
          ←
        </Link>
        <h1 className="text-xl font-semibold">Nieuwe rekening</h1>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium mb-1">Bedrijf</label>
          <select
            value={companyId}
            onChange={(e) => setCompanyId(e.target.value)}
            className="w-full min-h-touch px-4 rounded-lg border border-neutral-300 bg-white"
          >
            <option value="">Geen bedrijf (particulier)</option>
            {companies.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </div>

        {companyId && departments.length > 0 && (
          <Select label="Afdeling" value={departmentId} onChange={setDepartmentId} options={departments} />
        )}
        {companyId && costCenters.length > 0 && (
          <Select label="Kostenplaats" value={costCenterId} onChange={setCostCenterId} options={costCenters} />
        )}
        {companyId && projects.length > 0 && (
          <Select label="Project" value={projectId} onChange={setProjectId} options={projects} />
        )}

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium mb-1">Tafelnummer</label>
            <input
              value={tableNumber}
              onChange={(e) => setTableNumber(e.target.value)}
              className="w-full min-h-touch px-4 rounded-lg border border-neutral-300 bg-white"
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1">Aantal personen</label>
            <input
              type="number"
              min={1}
              value={guestCount}
              onChange={(e) => setGuestCount(e.target.value)}
              className="w-full min-h-touch px-4 rounded-lg border border-neutral-300 bg-white"
            />
          </div>
        </div>

        {error && (
          <p className="text-sm text-red-600" role="alert">
            {error}
          </p>
        )}

        <div className="flex gap-3 pt-2">
          <button
            type="submit"
            disabled={loading}
            className="flex-1 min-h-touch rounded-lg bg-neutral-900 text-white font-medium disabled:opacity-50"
          >
            {loading ? "Bezig..." : "Rekening openen"}
          </button>
          <Link
            href="/open-tabs"
            className="min-h-touch px-4 flex items-center justify-center rounded-lg border border-neutral-300 text-sm"
          >
            Annuleren
          </Link>
        </div>
      </form>
    </main>
  );
}

function Select({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: Option[];
}) {
  return (
    <div>
      <label className="block text-sm font-medium mb-1">{label}</label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full min-h-touch px-4 rounded-lg border border-neutral-300 bg-white"
      >
        <option value="">Geen</option>
        {options.map((o) => (
          <option key={o.id} value={o.id}>
            {o.name}
          </option>
        ))}
      </select>
    </div>
  );
}
