import { LogoutButton } from "@/components/ui/logout-button";

export default function PlatformLayout({ children }: { children: React.ReactNode }) {
  return (
    <div>
      <header className="border-b border-neutral-200 bg-white sticky top-0 z-10">
        <div className="flex items-center justify-between px-4 py-3">
          <span className="font-semibold">Polder platformbeheer</span>
          <LogoutButton />
        </div>
      </header>
      {children}
    </div>
  );
}
