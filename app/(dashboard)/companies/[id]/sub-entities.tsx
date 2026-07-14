"use client";

import { useState } from "react";

type Department = { id: string; name: string };
type CostCenter = { id: string; name: string; code: string | null; department_id: string | null };
type Project = { id: string; name: string; code: string | null; is_active: boolean };

type WorkflowRule = {
  invoice_frequency: "immediate" | "weekly" | "monthly" | "per_project";
  requires_approval: boolean;
};

const FREQUENCY_LABELS: Record<string, string> = {
  immediate: "Direct (elke rekening apart)",
  weekly: "Wekelijks",
  monthly: "Maandelijks",
  per_project: "Per project",
};

export function WorkflowRuleSection({
  companyId,
  initialRule,
}: {
  companyId: string;
  initialRule: WorkflowRule | null;
}) {
  const [frequency, setFrequency] = useState(initialRule?.invoice_frequency ?? "immediate");
  const [requiresApproval, setRequiresApproval] = useState(initialRule?.requires_approval ?? false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleSave() {
    setError(null);
    setSaved(false);
    setLoading(true);

    const response = await fetch(`/api/companies/${companyId}/workflow-rule`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ invoiceFrequency: frequency, requiresApproval }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon regel niet opslaan.");
      return;
    }

    setSaved(true);
  }

  return (
    <Section title="Facturatieregel">
      <details className="mb-2 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-3">
        <summary className="px-3 py-2 text-xs font-medium text-neutral-700 cursor-pointer">
          Hoe werkt dit? ℹ️
        </summary>
        <div className="px-3 text-xs text-neutral-600 space-y-1">
          <p>
            Bepaalt hoe vaak dit bedrijf gefactureerd wordt zodra de Facturatie-module
            klaar is. "Direct" betekent elke gesloten rekening apart; "Wekelijks"/
            "Maandelijks" bundelt meerdere rekeningen in één factuur.
          </p>
        </div>
      </details>

      <div>
        <label className="block text-sm font-medium mb-1">Factureer</label>
        <select
          value={frequency}
          onChange={(e) => setFrequency(e.target.value as WorkflowRule["invoice_frequency"])}
          className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
        >
          {Object.entries(FREQUENCY_LABELS).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </div>

      <label className="flex items-center gap-2 text-sm py-2">
        <input
          type="checkbox"
          checked={requiresApproval}
          onChange={(e) => setRequiresApproval(e.target.checked)}
          className="min-h-touch min-w-touch"
        />
        Goedkeuring vereist vóór factureren
      </label>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {saved && <p className="text-sm text-green-700">Opgeslagen.</p>}

      <button
        onClick={handleSave}
        disabled={loading}
        className="min-h-touch px-4 rounded-lg bg-neutral-900 text-white text-sm font-medium disabled:opacity-50"
      >
        {loading ? "Bezig..." : "Regel opslaan"}
      </button>
    </Section>
  );
}

const CODE_TYPES = [
  { value: "routecode", label: "Routecode" },
  { value: "wbs_wbf", label: "WBS/WBF-nummer" },
  { value: "kostenplaats", label: "Kostenplaats (referentie)" },
  { value: "budgetcode", label: "Budgetcode" },
  { value: "overig", label: "Overig" },
];

export function CompanyCodesSection({
  companyId,
  initialCodes,
}: {
  companyId: string;
  initialCodes: { id: string; type: string; code: string; description: string | null }[];
}) {
  const [codes, setCodes] = useState(initialCodes);
  const [type, setType] = useState("routecode");
  const [code, setCode] = useState("");
  const [description, setDescription] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    if (!code.trim()) return;
    setError(null);
    setLoading(true);

    const response = await fetch(`/api/companies/${companyId}/codes`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type, code, description: description || undefined }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon code niet toevoegen.");
      return;
    }

    const { companyCode } = await response.json();
    setCodes((prev) => [...prev, companyCode]);
    setCode("");
    setDescription("");
  }

  return (
    <Section title="Bedrijfsreferenties">
      <details className="mb-2 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-2">
        <summary className="px-3 py-2 text-xs font-medium text-neutral-700 cursor-pointer">
          Hoe werkt dit? ℹ️
        </summary>
        <div className="px-3 text-xs text-neutral-600">
          <p>
            Interne referentiecodes van dit bedrijf (routecodes, WBS-nummers,
            budgetcodes). Worden straks bij het invoeren van een bon aangeboden als
            keuzeveld, afhankelijk van welke velden je hieronder verplicht stelt.
          </p>
        </div>
      </details>

      <ItemList
        items={codes.map((c) => {
          const label = CODE_TYPES.find((t) => t.value === c.type)?.label ?? c.type;
          return `${label}: ${c.code}${c.description ? ` (${c.description})` : ""}`;
        })}
        emptyText="Nog geen bedrijfsreferenties."
      />

      <form onSubmit={handleAdd} className="space-y-2 pt-2">
        <div className="flex gap-2">
          <select
            value={type}
            onChange={(e) => setType(e.target.value)}
            className="min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-sm"
          >
            {CODE_TYPES.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </select>
          <input
            value={code}
            onChange={(e) => setCode(e.target.value)}
            placeholder="Code, bijv. R-102"
            className="flex-1 min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm min-w-0"
          />
        </div>
        <div className="flex gap-2">
          <input
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Omschrijving (optioneel)"
            className="flex-1 min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
          />
          <button
            type="submit"
            disabled={loading}
            className="min-h-touch px-4 rounded-lg bg-neutral-900 text-white text-sm font-medium disabled:opacity-50"
          >
            +
          </button>
        </div>
      </form>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </Section>
  );
}

const REQUIRED_FIELD_OPTIONS = [
  { key: "routecode", label: "Routecode" },
  { key: "wbs_wbf", label: "WBS/WBF-nummer" },
  { key: "kostenplaats", label: "Kostenplaats" },
  { key: "budgetcode", label: "Budgetcode" },
];

export function RequiredFieldsSection({
  companyId,
  initialConfig,
}: {
  companyId: string;
  initialConfig: Record<string, boolean>;
}) {
  const [fields, setFields] = useState<Record<string, boolean>>(initialConfig);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSave() {
    setError(null);
    setSaved(false);
    setLoading(true);

    const response = await fetch(`/api/companies/${companyId}/required-fields`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ receiptFields: fields }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon niet opslaan.");
      return;
    }

    setSaved(true);
  }

  return (
    <Section title="Verplichte velden bij bon">
      <details className="mb-2 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-2">
        <summary className="px-3 py-2 text-xs font-medium text-neutral-700 cursor-pointer">
          Hoe werkt dit? ℹ️
        </summary>
        <div className="px-3 text-xs text-neutral-600">
          <p>
            Bepaal welke bedrijfsreferenties verplicht zijn bij het invoeren van een bon
            voor dit bedrijf. Elk bedrijf kan andere velden verplicht stellen — dit
            wordt nog niet afgedwongen in het bonformulier zelf (volgt in een latere
            stap), maar wordt hier al vastgelegd.
          </p>
        </div>
      </details>

      {REQUIRED_FIELD_OPTIONS.map((opt) => (
        <label key={opt.key} className="flex items-center gap-2 text-sm py-1">
          <input
            type="checkbox"
            checked={fields[opt.key] ?? false}
            onChange={(e) => setFields((prev) => ({ ...prev, [opt.key]: e.target.checked }))}
            className="min-h-touch min-w-touch"
          />
          {opt.label} verplicht
        </label>
      ))}

      {error && <p className="text-sm text-red-600">{error}</p>}
      {saved && <p className="text-sm text-green-700">Opgeslagen.</p>}

      <button
        onClick={handleSave}
        disabled={loading}
        className="min-h-touch px-4 rounded-lg bg-neutral-900 text-white text-sm font-medium disabled:opacity-50 mt-2"
      >
        {loading ? "Bezig..." : "Opslaan"}
      </button>
    </Section>
  );
}

export function ApprovalSettingsSection({
  companyId,
  initialEnabled,
  initialMethod,
}: {
  companyId: string;
  initialEnabled: boolean;
  initialMethod: "pin" | "restaurant_confirms" | null;
}) {
  const [enabled, setEnabled] = useState(initialEnabled);
  const [method, setMethod] = useState<"pin" | "restaurant_confirms">(initialMethod ?? "restaurant_confirms");
  const [newPin, setNewPin] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleSave() {
    setError(null);
    setSaved(false);
    setLoading(true);

    const response = await fetch(`/api/companies/${companyId}/approval-settings`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        enabled,
        method: enabled ? method : null,
        autoLock: true,
        newPin: newPin || undefined,
      }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon niet opslaan.");
      return;
    }

    setSaved(true);
    setNewPin("");
  }

  return (
    <Section title="Goedkeuring bij bonnen">
      <details className="mb-2 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-2">
        <summary className="px-3 py-2 text-xs font-medium text-neutral-700 cursor-pointer">
          Hoe werkt dit? ℹ️
        </summary>
        <div className="px-3 text-xs text-neutral-600 space-y-1">
          <p>
            Wanneer ingeschakeld, moet elke nieuwe bon voor dit bedrijf goedgekeurd
            worden vóórdat 'm gefactureerd kan worden. Na goedkeuring is de bon
            vergrendeld (niet meer te wijzigen).
          </p>
          <p>
            <strong>PIN</strong>: een code die de manager invoert bij elke bon.{" "}
            <strong>Restaurant bevestigt</strong>: een geautoriseerde gebruiker klikt
            gewoon op "Goedkeuren", geen code nodig.
          </p>
        </div>
      </details>

      <label className="flex items-center gap-2 text-sm py-2">
        <input
          type="checkbox"
          checked={enabled}
          onChange={(e) => setEnabled(e.target.checked)}
          className="min-h-touch min-w-touch"
        />
        Goedkeuring vereist voor bonnen van dit bedrijf
      </label>

      {enabled && (
        <>
          <div className="mb-2">
            <label className="block text-sm font-medium mb-1">Methode</label>
            <select
              value={method}
              onChange={(e) => setMethod(e.target.value as "pin" | "restaurant_confirms")}
              className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
            >
              <option value="restaurant_confirms">Restaurant bevestigt</option>
              <option value="pin">PIN</option>
            </select>
          </div>

          {method === "pin" && (
            <div className="mb-2">
              <label className="block text-sm font-medium mb-1">
                {initialMethod === "pin" ? "Nieuwe PIN instellen" : "PIN instellen"}
              </label>
              <input
                type="password"
                inputMode="numeric"
                value={newPin}
                onChange={(e) => setNewPin(e.target.value)}
                placeholder="Minimaal 4 cijfers"
                className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
              />
            </div>
          )}
        </>
      )}

      {error && <p className="text-sm text-red-600">{error}</p>}
      {saved && <p className="text-sm text-green-700">Opgeslagen.</p>}

      <button
        onClick={handleSave}
        disabled={loading}
        className="min-h-touch px-4 rounded-lg bg-neutral-900 text-white text-sm font-medium disabled:opacity-50"
      >
        {loading ? "Bezig..." : "Opslaan"}
      </button>
    </Section>
  );
}

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
