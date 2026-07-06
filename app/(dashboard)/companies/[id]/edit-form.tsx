"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

type Company = {
  id: string;
  name: string;
  address: string | null;
  vat_number: string | null;
  coc_number: string | null;
  invoice_email: string | null;
  payment_term_days: number;
  notes: string | null;
  is_active: boolean;
};

export default function CompanyEditForm({ company }: { company: Company }) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string[]>>({});
  const [loading, setLoading] = useState(false);
  const [saved, setSaved] = useState(false);
  const [toggling, setToggling] = useState(false);

  async function handleToggleActive() {
    setToggling(true);
    setError(null);

    const response = await fetch(`/api/companies/${company.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: company.name, isActive: !company.is_active }),
    });

    setToggling(false);

    if (!response.ok) {
      const body = await response.json();
      setError(body.error || "Kon status niet wijzigen.");
      return;
    }

    router.refresh();
  }

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setFieldErrors({});
    setSaved(false);
    setLoading(true);

    const formData = new FormData(e.currentTarget);
    const payload = {
      name: formData.get("name"),
      address: formData.get("address") || undefined,
      vatNumber: formData.get("vatNumber") || undefined,
      cocNumber: formData.get("cocNumber") || undefined,
      invoiceEmail: formData.get("invoiceEmail") || "",
      paymentTermDays: Number(formData.get("paymentTermDays")) || 30,
      notes: formData.get("notes") || undefined,
    };

    const response = await fetch(`/api/companies/${company.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    setLoading(false);

    if (!response.ok) {
      const body = await response.json();
      if (body.details?.fieldErrors) {
        setFieldErrors(body.details.fieldErrors);
      }
      setError(body.error || "Er ging iets mis. Probeer het opnieuw.");
      return;
    }

    setSaved(true);
    router.refresh();
  }

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/companies" className="min-h-touch min-w-touch flex items-center justify-center text-neutral-500">
          ←
        </Link>
        <h1 className="text-xl font-semibold">{company.name}</h1>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <Field label="Naam" name="name" defaultValue={company.name} required error={fieldErrors.name} />
        <Field label="Adres" name="address" defaultValue={company.address ?? ""} error={fieldErrors.address} />
        <div className="grid grid-cols-2 gap-4">
          <Field label="BTW-nummer" name="vatNumber" defaultValue={company.vat_number ?? ""} error={fieldErrors.vatNumber} />
          <Field label="KvK-nummer" name="cocNumber" defaultValue={company.coc_number ?? ""} error={fieldErrors.cocNumber} />
        </div>
        <Field
          label="Factuur e-mailadres"
          name="invoiceEmail"
          type="email"
          defaultValue={company.invoice_email ?? ""}
          error={fieldErrors.invoiceEmail}
        />
        <div>
          <label className="block text-sm font-medium mb-1" htmlFor="paymentTermDays">
            Betalingstermijn (dagen)
          </label>
          <input
            id="paymentTermDays"
            name="paymentTermDays"
            type="number"
            defaultValue={company.payment_term_days}
            min={1}
            className="w-full min-h-touch px-4 rounded-lg border border-neutral-300 bg-white"
          />
        </div>
        <div>
          <label className="block text-sm font-medium mb-1" htmlFor="notes">
            Opmerkingen
          </label>
          <textarea
            id="notes"
            name="notes"
            rows={3}
            defaultValue={company.notes ?? ""}
            className="w-full px-4 py-3 rounded-lg border border-neutral-300 bg-white"
          />
        </div>

        {error && (
          <p className="text-sm text-red-600" role="alert">
            {error}
          </p>
        )}
        {saved && (
          <p className="text-sm text-green-700" role="status">
            Wijzigingen opgeslagen.
          </p>
        )}

        <div className="flex gap-3 pt-2">
          <button
            type="submit"
            disabled={loading}
            className="flex-1 min-h-touch rounded-lg bg-neutral-900 text-white font-medium disabled:opacity-50"
          >
            {loading ? "Bezig met opslaan..." : "Wijzigingen opslaan"}
          </button>
          <Link
            href="/companies"
            className="min-h-touch px-4 flex items-center justify-center rounded-lg border border-neutral-300 text-sm"
          >
            Terug
          </Link>
        </div>
      </form>

      <div className="mt-4 pt-4 border-t border-neutral-200">
        <details className="mb-2 rounded-lg border border-neutral-200 bg-neutral-50 open:pb-2">
          <summary className="px-3 py-2 text-xs font-medium text-neutral-700 cursor-pointer">
            Hoe werkt dit? ℹ️
          </summary>
          <div className="px-3 text-xs text-neutral-600">
            <p>
              Bedrijven worden nooit permanent verwijderd (historische facturen moeten
              intact blijven) — je kunt een bedrijf wel deactiveren zodat het niet meer
              gekozen kan worden bij nieuwe rekeningen.
            </p>
          </div>
        </details>
        <button
          onClick={handleToggleActive}
          disabled={toggling}
          className={`min-h-touch px-4 rounded-lg text-sm font-medium border ${
            company.is_active
              ? "border-red-300 text-red-600"
              : "border-green-300 text-green-700"
          } disabled:opacity-50`}
        >
          {toggling
            ? "Bezig..."
            : company.is_active
              ? "Bedrijf deactiveren"
              : "Bedrijf activeren"}
        </button>
      </div>
    </main>
  );
}

function Field({
  label,
  name,
  type = "text",
  required = false,
  defaultValue,
  error,
}: {
  label: string;
  name: string;
  type?: string;
  required?: boolean;
  defaultValue?: string;
  error?: string[];
}) {
  return (
    <div>
      <label className="block text-sm font-medium mb-1" htmlFor={name}>
        {label}
        {required && <span className="text-red-500"> *</span>}
      </label>
      <input
        id={name}
        name={name}
        type={type}
        required={required}
        defaultValue={defaultValue}
        className="w-full min-h-touch px-4 rounded-lg border border-neutral-300 bg-white"
      />
      {error && (
        <p className="text-sm text-red-600 mt-1" role="alert">
          {error[0]}
        </p>
      )}
    </div>
  );
}
