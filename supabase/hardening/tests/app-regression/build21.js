// Bundelt t21.ts (stap 14c: handtekening van de klant) met de ECHTE routes en pagina.
// Alleen de Supabase-clients, react.cache en de mailer zijn gestubd. JSX automatisch, zodat pagina's als element-boom te toetsen zijn.
const esbuild = require(process.env.ESBUILD || "/home/pgtest/apptest/node_modules/esbuild"); const path = require("path");
const P = process.argv[2]; const here = __dirname;
esbuild.build({ entryPoints: [here + "/t21.ts"], bundle: true, platform: "node", outfile: here + "/t21.js", external: ["pg"], logLevel: "error",
  jsx: "automatic", define: { "process.env.NODE_ENV": '"production"' },
  plugins: [{ name: "alias", setup(b) {
    const map = { "@/lib/supabase/server": "stubs/server.ts", "@/lib/supabase/admin": "stubs/admin.ts", "@/lib/email/email-service": "stubs/email.ts" };
    b.onResolve({ filter: /^@\/lib\/(supabase\/(server|admin)|email\/email-service)$/ }, a => ({ path: path.join(here, map[a.path]) }));
    b.onResolve({ filter: /^react$/ }, () => ({ path: here + "/stubs/react-full.js" }));
    b.onResolve({ filter: /^react-echt$/ }, () => ({ path: path.join(P, "node_modules/react/index.js") }));
    b.onResolve({ filter: /^@supabase\/supabase-js$/ }, () => ({ path: here + "/fake-supabase.js" }));
    b.onResolve({ filter: /^@\// }, async a => { const r = await b.resolve("./" + a.path.slice(2), { resolveDir: P, kind: a.kind }); return r; });
  } }] }).catch(() => process.exit(1));
