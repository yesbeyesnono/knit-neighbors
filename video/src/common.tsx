import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { loadFont } from "@remotion/fonts";
import { staticFile } from "remotion";
import { C, SAFE_BOTTOM } from "./theme";
import { TS_SVG } from "./tsfont.js";

// 글꼴은 public/fonts 의 Noto Sans KR(OFL)을 직접 읽는다 — 렌더 환경에 인터넷이 없어도 되고 결과가 늘 같다
export const FONT = "Noto Sans KR";
for (const w of ["400", "500", "700"]) {
  loadFont({ family: FONT, url: staticFile(`fonts/NotoSansKR-${w}.ttf`), weight: w, display: "block" });
}

export type Layout = "landscape" | "portrait";

export const clamp = { extrapolateLeft: "clamp" as const, extrapolateRight: "clamp" as const };

/** 장면 공통 바탕: 흰 배경 + 들어올 때 12프레임 페이드, 나갈 때 10프레임 페이드 */
export const Scene: React.FC<{ dur: number; children: React.ReactNode }> = ({ dur, children }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [0, 12, dur - 10, dur], [0, 1, 1, 0], clamp);
  return (
    <AbsoluteFill style={{ background: C.bg, fontFamily: FONT, color: C.ink, opacity: o }}>
      {children}
    </AbsoluteFill>
  );
};

/** 헤드라인: 아래에서 올라오며 나타남 */
export const Headline: React.FC<{
  text: string; at?: number; size?: number; x?: number; y?: number; align?: "left" | "center"; width?: number; weight?: number;
}> = ({ text, at = 10, size = 64, x = 120, y = 120, align = "left", width, weight = 700 }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f - at, fps, config: { damping: 200, stiffness: 120 }, durationInFrames: 30 });
  return (
    <div style={{ position: "absolute", left: x, top: y + (1 - p) * 24, width, opacity: p, fontSize: size, fontWeight: weight,
      letterSpacing: -1, lineHeight: 1.25, textAlign: align, whiteSpace: "pre-line" }}>{text}</div>
  );
};

export const Caption: React.FC<{ text: string; at?: number; x?: number; y?: number; size?: number; align?: "left" | "center"; width?: number; color?: string }> =
  ({ text, at = 30, x = 120, y = 220, size = 30, align = "left", width, color = C.muted }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [at, at + 18], [0, 1], clamp);
  return <div style={{ position: "absolute", left: x, top: y, width, opacity: o, fontSize: size, fontWeight: 400, color, textAlign: align, lineHeight: 1.4, whiteSpace: "pre-line" }}>{text}</div>;
};

/** 털실체 제목(앱의 SVG 글자 엔진) */
export const TsTitle: React.FC<{ text: string; size: number; color?: string; style?: React.CSSProperties }> = ({ text, size, color = C.ink, style }) => {
  const svg = TS_SVG(text, size, 95, color) as string | null;
  if (!svg) return <span style={{ fontSize: size, fontWeight: 700, ...style }}>{text}</span>;
  return <div style={{ display: "inline-block", lineHeight: 0, ...style }} dangerouslySetInnerHTML={{ __html: svg }} />;
};

/** 실 한 가닥 + 실뭉치 (앱 .tshead 의 YARN_SVG) */
export const YarnLine: React.FC<{ w: number; style?: React.CSSProperties }> = ({ w, style }) => {
  const n = Math.max(1, Math.round((w - 30) / 50)), end = 2 + 50 * n, W = end + 26;
  const d = "M2 9 " + Array.from({ length: n }, (_, i) => (i === 0 ? "c 20 -8 30 10 50 2" : "s 30 " + (i % 2 ? "10 50 2" : "-10 50 -2"))).join(" ");
  return (
    <svg width={W} height={18} viewBox={`0 0 ${W} 18`} style={style}>
      <path d={d} fill="none" stroke={C.acc} strokeWidth={3} strokeLinecap="round" />
      <circle cx={end + 14} cy={9} r={7} fill={C.btn} stroke={C.acc} strokeWidth={2} />
      <path d={`M${end + 9} 6.5 c3 1 7 1 10 0 M${end + 9} 11.5 c3 1 7 1 10 0`} fill="none" stroke={C.acc} strokeWidth={1.3} strokeLinecap="round" />
    </svg>
  );
};

/** 실뭉치 아이콘 */
export const YarnBall: React.FC<{ x: number; y: number; r: number; color?: string; stroke?: string; opacity?: number; scale?: number }> =
  ({ x, y, r, color = C.btn, stroke = C.acc, opacity = 1, scale = 1 }) => (
  <g transform={`translate(${x} ${y}) scale(${scale})`} opacity={opacity}>
    <circle r={r} fill={color} stroke={stroke} strokeWidth={r * 0.12} />
    <path d={`M${-r * 0.7} ${-r * 0.25} q ${r * 0.7} ${-r * 0.5} ${r * 1.4} 0 M${-r * 0.75} ${r * 0.15} q ${r * 0.75} ${-r * 0.5} ${r * 1.5} 0 M${-r * 0.6} ${r * 0.5} q ${r * 0.6} ${-r * 0.45} ${r * 1.2} 0`}
      fill="none" stroke={stroke} strokeWidth={r * 0.09} strokeLinecap="round" />
  </g>
);

/** 흰 카드 */
export const Card: React.FC<{ x: number; y: number; w: number; h: number; p?: number; children?: React.ReactNode; style?: React.CSSProperties; opacity?: number; scale?: number }> =
  ({ x, y, w, h, p = 1, children, style, opacity = 1, scale = 1 }) => (
  <div style={{ position: "absolute", left: x, top: y, width: w, height: h, background: "#fff", border: `2px solid ${C.line}`, borderRadius: 24,
    boxShadow: "0 8px 30px rgba(60,64,67,.08)", opacity: opacity * p, transform: `scale(${scale * (0.92 + 0.08 * p)})`, transformOrigin: "center", ...style }}>
    {children}
  </div>
);

export const Chip: React.FC<{ text: string; bg?: string; color?: string; size?: number; style?: React.CSSProperties }> = ({ text, bg = C.chip, color = C.olive, size = 24, style }) => (
  <span style={{ display: "inline-block", padding: `${size * 0.3}px ${size * 0.7}px`, borderRadius: 999, background: bg, color, fontSize: size, fontWeight: 500, lineHeight: 1.2, ...style }}>{text}</span>
);

export const safeBottom = SAFE_BOTTOM;
