// Alleen voor de app-test buiten Next.js: react.cache() als doorgeefluik (geen caching tussen aanroepen).
export function cache<T extends (...args: any[]) => any>(fn: T): T { return fn; }
