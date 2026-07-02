import { LogoutButton } from "@/components/ui/logout-button";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div>
      <header className="flex items-center justify-between px-4 py-3 border-b border-neutral-200 bg-white sticky top-0 z-10">
        <span className="font-semibold">Polder</span>
        <LogoutButton />
      </header>
      {children}
    </div>
  );
}
