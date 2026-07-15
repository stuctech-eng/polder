export default function PageLoading() {
  return (
    <main className="p-4 max-w-2xl mx-auto">
      <div className="animate-pulse space-y-3">
        <div className="h-6 w-40 bg-neutral-200 rounded" />
        <div className="h-10 w-full bg-neutral-100 rounded-lg" />
        <div className="h-10 w-full bg-neutral-100 rounded-lg" />
        <div className="h-10 w-3/4 bg-neutral-100 rounded-lg" />
      </div>
    </main>
  );
}
