"use client";

import { useState } from "react";

type Department = { id: string; name: string };
type CostCenter = { id: string; name: string; code: string | null; department_id: string | null };
type Project = { id: string; name: string; code: string | null; is_active: boolean };

export function DepartmentsSection({
  companyId,
  initialDepartments,
}: {
  companyId: string;
  initialDepartments: Department[];
}) {
  const [departments, setDepartments] = useState(initialDepartments);
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    setError(null);
    setLoading(true);

    const response = await fetch(`/api/companies/${companyId}/departments`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon afdeling niet toevoegen.");
      return;
    }

    const { department } = await response.json();
    setDepartments((prev) => [...prev, department].sort((a, b) => a.name.localeCompare(b.name)));
    setName("");
  }

  return (
    <Section title="Afdelingen">
      <ItemList items={departments.map((d) => d.name)} emptyText="Nog geen afdelingen." />
      <AddForm value={name} onChange={setName} onSubmit={handleAdd} loading={loading} placeholder="Naam afdeling" />
      {error && <p className="text-sm text-red-600">{error}</p>}
    </Section>
  );
}

export function CostCentersSection({
  companyId,
  initialCostCenters,
  departments,
}: {
  companyId: string;
  initialCostCenters: CostCenter[];
  departments: Department[];
}) {
  const [costCenters, setCostCenters] = useState(initialCostCenters);
  const [name, setName] = useState("");
  const [departmentId, setDepartmentId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    setError(null);
    setLoading(true);

    const response = await fetch(`/api/companies/${companyId}/cost-centers`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name, departmentId: departmentId || undefined }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon kostenplaats niet toevoegen.");
      return;
    }

    const { costCenter } = await response.json();
    setCostCenters((prev) => [...prev, costCenter].sort((a, b) => a.name.localeCompare(b.name)));
    setName("");
    setDepartmentId("");
  }

  return (
    <Section title="Kostenplaatsen">
      <ItemList
        items={costCenters.map((c) => {
          const dept = departments.find((d) => d.id === c.department_id);
          return dept ? `${c.name} (${dept.name})` : c.name;
        })}
        emptyText="Nog geen kostenplaatsen."
      />
      <form onSubmit={handleAdd} className="flex gap-2 pt-2">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Naam kostenplaats"
          className="flex-1 min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
        />
        {departments.length > 0 && (
          <select
            value={departmentId}
            onChange={(e) => setDepartmentId(e.target.value)}
            className="min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-sm"
          >
            <option value="">Geen afdeling</option>
            {departments.map((d) => (
              <option key={d.id} value={d.id}>
                {d.name}
              </option>
            ))}
          </select>
        )}
        <button
          type="submit"
          disabled={loading}
          className="min-h-touch px-4 rounded-lg bg-neutral-900 text-white text-sm font-medium disabled:opacity-50"
        >
          +
        </button>
      </form>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </Section>
  );
}

export function ProjectsSection({
  companyId,
  initialProjects,
}: {
  companyId: string;
  initialProjects: Project[];
}) {
  const [projects, setProjects] = useState(initialProjects);
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    setError(null);
    setLoading(true);

    const response = await fetch(`/api/companies/${companyId}/projects`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon project niet toevoegen.");
      return;
    }

    const { project } = await response.json();
    setProjects((prev) => [...prev, project].sort((a, b) => a.name.localeCompare(b.name)));
    setName("");
  }

  return (
    <Section title="Projecten">
      <ItemList items={projects.map((p) => p.name)} emptyText="Nog geen projecten." />
      <AddForm value={name} onChange={setName} onSubmit={handleAdd} loading={loading} placeholder="Naam project" />
      {error && <p className="text-sm text-red-600">{error}</p>}
    </Section>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="border-t border-neutral-200 pt-4 mt-4 space-y-2">
      <h2 className="text-sm font-semibold text-neutral-700">{title}</h2>
      {children}
    </div>
  );
}

function ItemList({ items, emptyText }: { items: string[]; emptyText: string }) {
  if (!items.length) {
    return <p className="text-sm text-neutral-400">{emptyText}</p>;
  }
  return (
    <ul className="space-y-1">
      {items.map((item, i) => (
        <li key={i} className="text-sm px-3 py-2 rounded-lg bg-neutral-100">
          {item}
        </li>
      ))}
    </ul>
  );
}

function AddForm({
  value,
  onChange,
  onSubmit,
  loading,
  placeholder,
}: {
  value: string;
  onChange: (v: string) => void;
  onSubmit: (e: React.FormEvent) => void;
  loading: boolean;
  placeholder: string;
}) {
  return (
    <form onSubmit={onSubmit} className="flex gap-2 pt-2">
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="flex-1 min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
      />
      <button
        type="submit"
        disabled={loading}
        className="min-h-touch px-4 rounded-lg bg-neutral-900 text-white text-sm font-medium disabled:opacity-50"
      >
        +
      </button>
    </form>
  );
}
