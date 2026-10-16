// next/navigation voor componenttests (t18): useRouter met een tellende refresh(); het scherm gebruikt alleen refresh/push.
const g = globalThis as any;
g.__refreshes = 0;
export function useRouter() {
  return { refresh: () => { g.__refreshes++; }, push: () => {}, replace: () => {}, back: () => {} };
}
