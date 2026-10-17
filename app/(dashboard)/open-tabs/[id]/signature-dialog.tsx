"use client";

import { useEffect, useRef, useState } from "react";
import { SIGNER_NAME_MIN, SIGNER_NAME_MAX, SIGNATURE_MAX_LENGTH, isValidSignaturePng } from "@/lib/approval/signature";

/**
 * Stap 14c: de klant leest de bon, vult zijn naam in en tekent op het scherm van het restaurant. Alleen invoer en tekenen;
 * de server en de database (bon_ondertekenen) controleren alles. Volledig scherm, veilig voor de notch (safe-area).
 */
export function SignatureDialog({
  receiptId,
  receiptLabel,
  companyName,
  total,
  lines,
  fingerprint,
  onSigned,
  onClose,
}: {
  receiptId: string;
  receiptLabel: string;
  /** Bedrijf van de rekening: daarvoor tekent de klant. */
  companyName: string | null;
  total: number;
  lines: { description: string; quantity: number; line_total: number }[];
  fingerprint: string;
  onSigned: (status: string, signedBy: string) => void;
  onClose: () => void;
}) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const drawing = useRef(false);
  const [hasDrawn, setHasDrawn] = useState(false);
  const [name, setName] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Canvas op de echte schermgrootte (scherp op een iPhone), hooguit 2x zodat het bestand klein blijft.
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    const rect = canvas.getBoundingClientRect();
    canvas.width = Math.max(1, Math.round(rect.width * ratio));
    canvas.height = Math.max(1, Math.round(rect.height * ratio));
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.scale(ratio, ratio);
    ctx.lineWidth = 2.5;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.strokeStyle = "#111827";
  }, []);

  function point(e: React.PointerEvent<HTMLCanvasElement>) {
    const rect = e.currentTarget.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  }

  function start(e: React.PointerEvent<HTMLCanvasElement>) {
    const ctx = e.currentTarget.getContext("2d");
    if (!ctx) return;
    e.currentTarget.setPointerCapture?.(e.pointerId);
    drawing.current = true;
    const p = point(e);
    ctx.beginPath();
    ctx.moveTo(p.x, p.y);
    ctx.lineTo(p.x + 0.1, p.y + 0.1);
    ctx.stroke();
    setHasDrawn(true);
  }

  function move(e: React.PointerEvent<HTMLCanvasElement>) {
    if (!drawing.current) return;
    const ctx = e.currentTarget.getContext("2d");
    if (!ctx) return;
    const p = point(e);
    ctx.lineTo(p.x, p.y);
    ctx.stroke();
  }

  function stop() {
    drawing.current = false;
  }

  function clear() {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (canvas && ctx) {
      ctx.save();
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.restore();
    }
    setHasDrawn(false);
  }

  const trimmedName = name.trim();
  const nameOk = trimmedName.length >= SIGNER_NAME_MIN && trimmedName.length <= SIGNER_NAME_MAX;

  async function confirm() {
    setError(null);
    if (!nameOk) {
      setError(`Vul de naam van de klant in (${SIGNER_NAME_MIN} tot ${SIGNER_NAME_MAX} tekens).`);
      return;
    }
    if (!hasDrawn || !canvasRef.current) {
      setError("Laat de klant eerst tekenen.");
      return;
    }
    const signature = canvasRef.current.toDataURL("image/png");
    if (signature.length > SIGNATURE_MAX_LENGTH) {
      setError("De handtekening is te groot. Wis en laat de klant opnieuw (kleiner) tekenen.");
      return;
    }
    if (!isValidSignaturePng(signature)) {
      setError("De handtekening kon niet worden vastgelegd. Wis en laat de klant opnieuw tekenen.");
      return;
    }
    setLoading(true);
    let response: Response;
    try {
      response = await fetch(`/api/receipts/${receiptId}/sign`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: trimmedName, signature, fingerprint }),
      });
    } catch {
      setLoading(false);
      setError("Geen verbinding met de server: de bon is niet ondertekend. Probeer het opnieuw.");
      return;
    }
    const body = await response.json().catch(() => ({}));
    setLoading(false);
    if (!response.ok) {
      setError(body.error || "Ondertekenen is niet gelukt.");
      return;
    }
    onSigned(body.status, body.signedBy ?? trimmedName);
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Bon laten ondertekenen"
      className="fixed inset-0 z-50 bg-white overflow-y-auto"
      style={{
        paddingTop: "max(env(safe-area-inset-top), 16px)",
        paddingBottom: "max(env(safe-area-inset-bottom), 16px)",
        paddingLeft: "max(env(safe-area-inset-left), 16px)",
        paddingRight: "max(env(safe-area-inset-right), 16px)",
      }}
    >
      <div className="max-w-lg mx-auto space-y-4">
        <h2 className="text-lg font-semibold">Bon ondertekenen</h2>

        <div className="rounded-lg bg-neutral-50 p-3 text-sm">
          <div className="text-xs text-neutral-500">Bedrijf</div>
          <div className="font-semibold mb-2">{companyName ?? "Onbekend bedrijf"}</div>
          <div className="flex justify-between font-medium">
            <span>{receiptLabel}</span>
            <span>€{total.toFixed(2)}</span>
          </div>
          <div className="text-neutral-600 text-xs mt-1 space-y-0.5">
            {lines.map((l, i) => (
              <div key={i}>
                {l.quantity}× {l.description} — €{l.line_total.toFixed(2)}
              </div>
            ))}
          </div>
        </div>

        <p className="text-sm text-neutral-600">
          Met uw naam en handtekening bevestigt u deze bon voor {companyName ?? "dit bedrijf"}.
        </p>

        <label className="block text-sm font-medium">
          Naam klant
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={SIGNER_NAME_MAX}
            autoComplete="name"
            className="mt-1 w-full min-h-touch px-3 rounded-lg border border-neutral-300 bg-white text-base"
          />
        </label>

        <div>
          <div className="flex items-center justify-between mb-1">
            <span className="text-sm font-medium">Handtekening</span>
            <button type="button" onClick={clear} className="min-h-touch px-3 text-sm text-neutral-600 underline">
              Wissen
            </button>
          </div>
          <canvas
            ref={canvasRef}
            aria-label="Tekenvlak voor de handtekening"
            onPointerDown={start}
            onPointerMove={move}
            onPointerUp={stop}
            onPointerCancel={stop}
            onPointerLeave={stop}
            className="w-full h-48 rounded-lg border-2 border-dashed border-neutral-300 bg-white"
            style={{ touchAction: "none" }}
          />
        </div>

        {error && (
          <p className="text-sm text-red-600" role="alert">
            {error}
          </p>
        )}

        <div className="flex gap-3">
          <button
            type="button"
            onClick={onClose}
            disabled={loading}
            className="flex-1 min-h-touch rounded-lg border border-neutral-300 text-sm font-medium"
          >
            Annuleren
          </button>
          <button
            type="button"
            onClick={confirm}
            disabled={loading || !nameOk || !hasDrawn}
            className="flex-1 min-h-touch rounded-lg bg-neutral-900 text-white text-sm font-medium disabled:opacity-50"
          >
            {loading ? "Bezig..." : "Bevestigen"}
          </button>
        </div>
      </div>
    </div>
  );
}
