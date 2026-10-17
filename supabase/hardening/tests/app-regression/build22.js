// Bundelt t22.ts (stap 14c: tekenscherm voor de klant) met het ECHTE scherm en de echte React; next/navigation is gestubd, jsdom als browser.
const esbuild = require(process.env.ESBUILD || "/home/pgtest/apptest/node_modules/esbuild"); const path = require("path");
const P = process.argv[2]; const here = __dirname;
esbuild.build({ entryPoints: [here + "/t22.ts"], bundle: true, platform: "node", outfile: here + "/t22.js", external: ["jsdom"], logLevel: "error",
  jsx: "automatic", define: { "process.env.NODE_ENV": '"development"' },
  plugins: [{ name: "alias", setup(b) {
    b.onResolve({ filter: /^next\/navigation$/ }, () => ({ path: here + "/stubs/navigation.ts" }));
    b.onResolve({ filter: /^(react|react-dom)(\/.*)?$/ }, async a => b.resolve("./node_modules/" + a.path, { resolveDir: P, kind: a.kind }));
    b.onResolve({ filter: /^@\// }, async a => b.resolve("./" + a.path.slice(2), { resolveDir: P, kind: a.kind }));
  } }] }).catch(() => process.exit(1));
