import { requirePlatformAdmin } from "@/lib/platform/platform-access";
import * as platform from "@/lib/platform/platform-service";
import { PermissionError } from "@/lib/user-management/permission-service";
import PlatformUI from "./platform-ui";

export const dynamic = "force-dynamic";

export default async function PlatformPage() {
  let restaurants: platform.PlatformRestaurant[] = [];
  let log: platform.PlatformLogEntry[] = [];
  let error: string | null = null;

  try {
    await requirePlatformAdmin();
    [restaurants, log] = await Promise.all([platform.listRestaurants(), platform.listLog()]);
  } catch (err) {
    error =
      err instanceof PermissionError || err instanceof platform.PlatformError ? err.message : "Onbekende fout";
  }

  if (error) {
    return (
      <main className="p-4 max-w-2xl mx-auto">
        <h1 className="text-xl font-semibold mb-4">Platformbeheer</h1>
        <p className="text-sm text-red-600" role="alert">
          {error}
        </p>
      </main>
    );
  }

  return <PlatformUI initialRestaurants={restaurants} initialLog={log} />;
}
