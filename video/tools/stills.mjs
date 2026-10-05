// 장면 확인용 정지 화면: node tools/stills.mjs [compId] [frames...]
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import fs from "node:fs";
import path from "node:path";
const comp = process.argv[2] || "KnitIntro16x9";
const frames = process.argv.slice(3).map(Number);
const list = frames.length ? frames : [60, 210, 405, 615, 825, 1035, 1245];
const local = "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell";
const browserExecutable = fs.existsSync(local) ? local : undefined;
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const composition = await selectComposition({ serveUrl, id: comp, browserExecutable });
fs.mkdirSync("out", { recursive: true });
for (const f of list) {
  const output = `out/${comp}-${String(f).padStart(4, "0")}.png`;
  await renderStill({ composition, serveUrl, output, frame: f, browserExecutable, chromiumOptions: { gl: "swangle" } });
  console.log("wrote", output);
}
