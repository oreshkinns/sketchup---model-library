import { build } from "esbuild";
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const result = await build({
  absWorkingDir: root,
  entryPoints: ["frontend/main.jsx"],
  bundle: true,
  write: false,
  target: ["chrome64"],
  format: "iife",
  minify: true,
  legalComments: "inline",
  define: { "process.env.NODE_ENV": '"production"' },
});
const css = await readFile(
  new URL("../frontend/styles.css", import.meta.url),
  "utf8",
);
const script = result.outputFiles[0].text.replace(/<\/script/gi, "<\\/script");
await writeFile(
  new URL("../preview.html", import.meta.url),
  `<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>МАФ Каталог — модели, библиотека, аудит</title><style>${css}</style></head>
<body><div id="root"></div><script>${script}</script></body></html>\n`,
  "utf8",
);
console.log("Built offline React UI: preview.html (Chrome 64 compatible)");
