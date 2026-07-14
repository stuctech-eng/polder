import { LogoutButton } from "@/components/ui/logout-button";
import Link from "next/link";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div>
      <header className="flex items-center justify-between px-4 py-3 border-b border-neutral-200 bg-white sticky top-0 z-10">
        <div className="flex items-center gap-4">
          <span className="font-semibold">Polder</span>
          <nav className="flex gap-3 text-sm text-neutral-500">
            <Link href="/dashboard" className="min-h-touch flex items-center">
              Dashboard
            </Link>
            <Link href="/companies" className="min-h-touch flex items-center">
              Bedrijven
            </Link>
            <Link href="/open-tabs" className="min-h-touch flex items-center">
              Rekeningen
            </Link>
            <Link href="/invoices" className="min-h-touch flex items-center">
              Facturen
            </Link>
            <Link href="/daily-closing" className="min-h-touch flex items-center">
              Dagafsluiting
            </Link>
            <Link href="/team" className="min-h-touch flex items-center">
              Team
            </Link>
          </nav>
        </div>
        <LogoutButton />
      </header>
      {children}
    </div>
  );
}
