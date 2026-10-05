// MP4 렌더: node tools/render.mjs [compId]
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import fs from "node:fs";
import path from "node:path";
const comp = process.argv[2] || "KnitIntro16x9";
const local = "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell";
const browserExecutable = fs.existsSync(local) ? local : undefined;
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const composition = await selectComposition({ serveUrl, id: comp, browserExecutable });
fs.mkdirSync("out", { recursive: true });
const out = `out/${comp}.mp4`;
let last = -1;
await renderMedia({ composition, serveUrl, codec: "h264", outputLocation: out, browserExecutable, chromiumOptions: { gl: "swangle" },
  concurrency: Math.max(1, Math.min(4, (await import("node:os")).cpus().length)),
  onProgress: ({ progress }) => { const p = Math.floor(progress * 10); if (p !== last) { last = p; console.log(`${p * 10}%`); } } });
console.log("wrote", out);
