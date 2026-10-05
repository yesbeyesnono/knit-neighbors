import { Config } from "@remotion/cli/config";
import fs from "node:fs";
Config.setVideoImageFormat("jpeg");
Config.setOverwriteOutput(true);
// 이 작업 환경(클라우드 세션)에는 Playwright 크롬이 이미 있다. 대표님 PC에서는 Remotion이 자체 크롬을 받는다.
const local = "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell";
if (fs.existsSync(local)) Config.setBrowserExecutable(local);
