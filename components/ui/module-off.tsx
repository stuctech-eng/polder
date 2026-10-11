import { MODULE_OFF_MESSAGE } from "@/lib/features/features";

/** Melding voor een pagina of onderdeel van een uitgezette module (sectie 15: zichtbaar in de app). */
export function ModuleOff({ title }: { title?: string }) {
  return (
    <div className="text-sm text-amber-700 bg-amber-50 border border-amber-200 rounded-lg p-3" role="status">
      {title ? <span className="font-medium">{title}: </span> : null}
      {MODULE_OFF_MESSAGE}
    </div>
  );
}
