// Noto Sans KR(OFL) 3종을 public/fonts 에 내려받는다. npm install 때 자동 실행(postinstall). 이미 있으면 건너뜀.
import fs from "node:fs";
const U = {
  400: "https://fonts.gstatic.com/s/notosanskr/v40/PbyxFmXiEBPT4ITbgNA5Cgms3VYcOA-vvnIzzuoyeLQ.ttf",
  500: "https://fonts.gstatic.com/s/notosanskr/v40/PbyxFmXiEBPT4ITbgNA5Cgms3VYcOA-vvnIzztgyeLQ.ttf",
  700: "https://fonts.gstatic.com/s/notosanskr/v40/PbyxFmXiEBPT4ITbgNA5Cgms3VYcOA-vvnIzzg01eLQ.ttf",
};
fs.mkdirSync("public/fonts", { recursive: true });
for (const [w, url] of Object.entries(U)) {
  const out = `public/fonts/NotoSansKR-${w}.ttf`;
  if (fs.existsSync(out) && fs.statSync(out).size > 1e6) continue;
  const r = await fetch(url); if (!r.ok) { console.error("font download failed", w, r.status); process.exit(1); }
  fs.writeFileSync(out, Buffer.from(await r.arrayBuffer())); console.log("fetched", out);
}
