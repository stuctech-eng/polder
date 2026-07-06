"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

export default function NewCompanyPage() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string[]>>({});
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setFieldErrors({});
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

    const response = await fetch("/api/companies", {
      method: "POST",
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

    router.push("/companies");
    router.refresh();
  }

  return (
    <main className="p-4 max-w-2xl mx-auto">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/companies" className="min-h-touch min-w-touch flex items-center justify-center text-neutral-500">
          ←
        </Link>
        <h1 className="text-xl font-semibold">Nieuw bedrijf</h1>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <Field label="Naam" name="name" required error={fieldErrors.name} />
        <Field label="Adres" name="address" error={fieldErrors.address} />
        <div className="grid grid-cols-2 gap-4">
          <Field label="BTW-nummer" name="vatNumber" error={fieldErrors.vatNumber} />
          <Field label="KvK-nummer" name="cocNumber" error={fieldErrors.cocNumber} />
        </div>
        <Field
          label="Factuur e-mailadres"
          name="invoiceEmail"
          type="email"
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
            defaultValue={30}
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
            className="w-full px-4 py-3 rounded-lg border border-neutral-300 bg-white"
          />
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
            {loading ? "Bezig met opslaan..." : "Bedrijf opslaan"}
          </button>
          <Link
            href="/companies"
            className="min-h-touch px-4 flex items-center justify-center rounded-lg border border-neutral-300 text-sm"
          >
            Annuleren
          </Link>
        </div>
      </form>
    </main>
  );
}

function Field({
  label,
  name,
  type = "text",
  required = false,
  error,
}: {
  label: string;
  name: string;
  type?: string;
  required?: boolean;
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
