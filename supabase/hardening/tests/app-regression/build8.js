const esbuild = require("/home/pgtest/apptest/node_modules/esbuild"); const path = require("path");
const P = process.argv[2]; const here = __dirname;
esbuild.build({ entryPoints: [here + "/t8.ts"], bundle: true, platform: "node", outfile: here + "/t8.js", external: ["pg"], logLevel: "error",
  plugins: [{ name: "alias", setup(b) {
    const map = { "@/lib/supabase/server": "stubs/server.ts", "@/lib/supabase/admin": "stubs/admin.ts", "@/lib/user-management/permission-service": "stubs/permission.ts" };
    b.onResolve({ filter: /^@\/lib\/(supabase\/(server|admin)|user-management\/permission-service)$/ }, a => ({ path: path.join(here, map[a.path]) }));
    b.onResolve({ filter: /^@supabase\/supabase-js$/ }, () => ({ path: here + "/fake-supabase.js" }));
    b.onResolve({ filter: /^@\// }, async a => { const r = await b.resolve("./" + a.path.slice(2), { resolveDir: P, kind: a.kind }); return r; });
  } }] }).catch(() => process.exit(1));
