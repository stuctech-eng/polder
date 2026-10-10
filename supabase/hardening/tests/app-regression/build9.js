// Bundelt t9.ts met de ECHTE permission-service en session-context (alleen de Supabase-clients en react.cache zijn gestubd).
const esbuild = require(process.env.ESBUILD || "/home/pgtest/apptest/node_modules/esbuild"); const path = require("path");
const P = process.argv[2]; const here = __dirname;
esbuild.build({ entryPoints: [here + "/t9.ts"], bundle: true, platform: "node", outfile: here + "/t9.js", external: ["pg"], logLevel: "error",
  plugins: [{ name: "alias", setup(b) {
    const map = { "@/lib/supabase/server": "stubs/server.ts", "@/lib/supabase/admin": "stubs/admin.ts" };
    b.onResolve({ filter: /^@\/lib\/supabase\/(server|admin)$/ }, a => ({ path: path.join(here, map[a.path]) }));
    b.onResolve({ filter: /^react$/ }, () => ({ path: here + "/stubs/react.ts" }));
    b.onResolve({ filter: /^@supabase\/supabase-js$/ }, () => ({ path: here + "/fake-supabase.js" }));
    b.onResolve({ filter: /^@\// }, async a => { const r = await b.resolve("./" + a.path.slice(2), { resolveDir: P, kind: a.kind }); return r; });
  } }] }).catch(() => process.exit(1));
