"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type TeamMember = {
  id: string;
  full_name: string;
  role: string;
  is_active: boolean;
  two_factor_enabled: boolean;
  created_at: string;
};

const ROLES = [
  { value: "owner", label: "Eigenaar" },
  { value: "manager", label: "Manager" },
  { value: "administratie", label: "Administratie" },
  { value: "bediening", label: "Bediening" },
  { value: "keuken", label: "Keuken" },
];

export default function TeamManagementUI({ initialTeam }: { initialTeam: TeamMember[] }) {
  const router = useRouter();
  const [team, setTeam] = useState(initialTeam);
  const [showInvite, setShowInvite] = useState(false);

  function handleUpdated(updated: Partial<TeamMember> & { id: string }) {
    setTeam((prev) => prev.map((m) => (m.id === updated.id ? { ...m, ...updated } : m)));
  }

  function handleRemoved(id: string) {
    setTeam((prev) => prev.filter((m) => m.id !== id));
  }

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-semibold">Team</h1>
        <button
          onClick={() => setShowInvite((v) => !v)}
          className="min-h-touch px-4 rounded-lg bg-neutral-900 text-white text-sm font-medium"
        >
          {showInvite ? "Annuleren" : "+ Uitnodigen"}
        </button>
      </div>

      <details className="mb-4 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-3">
        <summary className="px-3 py-2 text-sm font-medium text-neutral-700 cursor-pointer">
          Hoe werkt dit? ℹ️
        </summary>
        <div className="px-3 text-sm text-neutral-600 space-y-1">
          <p>
            Nodig medewerkers uit met hun eigen account, zodat elke actie (bon
            toevoegen, factuur genereren, straks goedkeuren) op naam staat i.p.v.
            allemaal op jouw naam.
          </p>
          <p>
            Let op: de uitnodigingsmail deelt de bekende Resend-testlimiet — komt nu
            alleen betrouwbaar aan bij het Resend-testaccountadres, totdat er een
            eigen domein geverifieerd is.
          </p>
        </div>
      </details>

      {showInvite && (
        <InviteForm
          onInvited={(user) => {
            setTeam((prev) => [...prev, user]);
            setShowInvite(false);
          }}
        />
      )}

      <ul className="space-y-2 mt-4">
        {team.map((member) => (
          <TeamMemberRow
            key={member.id}
            member={member}
            onUpdated={handleUpdated}
            onRemoved={handleRemoved}
          />
        ))}
      </ul>
    </main>
  );
}

function InviteForm({ onInvited }: { onInvited: (user: TeamMember) => void }) {
  const [email, setEmail] = useState("");
  const [fullName, setFullName] = useState("");
  const [role, setRole] = useState("bediening");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);

    const response = await fetch("/api/team", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, fullName, role }),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon niet uitnodigen.");
      return;
    }

    const { user } = await response.json();
    onInvited({ ...user, two_factor_enabled: false });
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3 bg-neutral-50 rounded-lg p-3 mb-4">
      <input
        value={fullName}
        onChange={(e) => setFullName(e.target.value)}
        placeholder="Naam"
        required
        className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
      />
      <input
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder="E-mailadres"
        required
        className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
      />
      <select
        value={role}
        onChange={(e) => setRole(e.target.value)}
        className="w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-sm"
      >
        {ROLES.map((r) => (
          <option key={r.value} value={r.value}>
            {r.label}
          </option>
        ))}
      </select>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <button
        type="submit"
        disabled={loading}
        className="w-full min-h-touch rounded-lg bg-neutral-900 text-white text-sm font-medium disabled:opacity-50"
      >
        {loading ? "Bezig..." : "Uitnodiging versturen"}
      </button>
    </form>
  );
}

function TeamMemberRow({
  member,
  onUpdated,
  onRemoved,
}: {
  member: TeamMember;
  onUpdated: (m: Partial<TeamMember> & { id: string }) => void;
  onRemoved: (id: string) => void;
}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleRoleChange(role: string) {
    setLoading(true);
    setError(null);
    const response = await fetch(`/api/team/${member.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ role }),
    });
    setLoading(false);
    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon rol niet wijzigen.");
      return;
    }
    onUpdated({ id: member.id, role });
  }

  async function handleToggleActive() {
    setLoading(true);
    setError(null);
    const response = await fetch(`/api/team/${member.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ isActive: !member.is_active }),
    });
    setLoading(false);
    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon status niet wijzigen.");
      return;
    }
    onUpdated({ id: member.id, is_active: !member.is_active });
  }

  async function handleRemove() {
    if (!confirm(`${member.full_name} verwijderen?`)) return;
    setLoading(true);
    setError(null);
    const response = await fetch(`/api/team/${member.id}`, { method: "DELETE" });
    setLoading(false);
    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon niet verwijderen.");
      return;
    }
    onRemoved(member.id);
  }

  return (
    <li className="px-4 py-3 rounded-lg border border-neutral-200 bg-white">
      <div className="flex justify-between items-start">
        <div>
          <div className="font-medium">{member.full_name}</div>
          <div className="text-xs text-neutral-400">
            {!member.is_active && <span className="text-red-500">Gedeactiveerd · </span>}
            Lid sinds {new Date(member.created_at).toLocaleDateString("nl-NL")}
          </div>
        </div>
        <select
          value={member.role}
          onChange={(e) => handleRoleChange(e.target.value)}
          disabled={loading}
          className="min-h-touch px-2 rounded-lg border border-neutral-300 bg-white text-sm"
        >
          {ROLES.map((r) => (
            <option key={r.value} value={r.value}>
              {r.label}
            </option>
          ))}
        </select>
      </div>
      <div className="flex gap-3 mt-2">
        <button
          onClick={handleToggleActive}
          disabled={loading}
          className="text-xs text-neutral-600 underline"
        >
          {member.is_active ? "Deactiveren" : "Activeren"}
        </button>
        <button onClick={handleRemove} disabled={loading} className="text-xs text-red-600 underline">
          Verwijderen
        </button>
      </div>
      {error && <p className="text-xs text-red-600 mt-1">{error}</p>}
    </li>
  );
}
