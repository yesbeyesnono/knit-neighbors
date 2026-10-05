import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Scene, Headline, Caption, Chip, clamp, Layout } from "../common";
import { C, SCENES } from "../theme";
import provinces from "../provinces.json";

type Prov = { name: string; rings: number[][][] };
const PINS: { lon: number; lat: number; kind: "이웃" | "모임" | "가게" | "작가" }[] = [
  { lon: 126.98, lat: 37.57, kind: "이웃" }, { lon: 127.03, lat: 37.50, kind: "모임" }, { lon: 127.06, lat: 37.55, kind: "가게" },
  { lon: 126.90, lat: 37.48, kind: "이웃" }, { lon: 127.12, lat: 37.40, kind: "작가" }, { lon: 126.70, lat: 37.45, kind: "이웃" },
  { lon: 127.40, lat: 36.35, kind: "모임" }, { lon: 128.60, lat: 35.87, kind: "이웃" }, { lon: 129.07, lat: 35.18, kind: "가게" },
  { lon: 126.85, lat: 35.16, kind: "이웃" }, { lon: 127.70, lat: 37.88, kind: "작가" }, { lon: 128.90, lat: 37.75, kind: "이웃" },
  { lon: 126.53, lat: 33.50, kind: "모임" }, { lon: 127.15, lat: 37.25, kind: "이웃" }, { lon: 128.70, lat: 35.23, kind: "모임" },
  { lon: 127.00, lat: 37.65, kind: "이웃" }, { lon: 126.95, lat: 36.80, kind: "이웃" }, { lon: 129.35, lat: 36.05, kind: "가게" },
];
const KIND_COLOR = { 이웃: C.olive, 모임: C.acc, 가게: "#C98A4B", 작가: C.author } as const;

export const S2: React.FC<{ layout: Layout }> = ({ layout }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const land = layout === "landscape";
  // 투영: 경도 124.6~130.9, 위도 33.2~38.6
  const k = land ? 160 : 150, ox = land ? 980 : 60, oy = land ? 110 : 520;
  const px = (lon: number) => ox + (lon - 124.6) * k * 0.81;
  const py = (lat: number) => oy + (38.61 - lat) * k;
  const mapIn = interpolate(f, [0, 30], [0, 1], clamp);
  return (
    <Scene dur={SCENES.s2.dur}>
      <svg width={land ? 1920 : 1080} height={land ? 1080 : 1920} style={{ position: "absolute", left: 0, top: 0 }}>
        <g opacity={mapIn}>
          {(provinces as Prov[]).map((p, i) => p.rings.map((ring, j) => (
            <path key={`${i}-${j}`} d={ring.map(([lon, lat], idx) => `${idx ? "L" : "M"}${px(lon).toFixed(1)} ${py(lat).toFixed(1)}`).join(" ") + "Z"}
              fill={C.chip} stroke={C.line} strokeWidth={2} strokeLinejoin="round" />
          )))}
        </g>
        {PINS.map((p, i) => {
          const s = spring({ frame: f - 30 - i * 5, fps, config: { damping: 12, stiffness: 180 } });
          const x = px(p.lon), y = py(p.lat), col = KIND_COLOR[p.kind];
          return (
            <g key={i} transform={`translate(${x} ${y}) scale(${s})`} opacity={s}>
              <circle r={26} fill={col} opacity={0.18} />
              <path d="M0 6 c -12 -14 -12 -30 0 -30 c 12 0 12 16 0 30 z" fill={col} />
              <circle cy={-14} r={5} fill="#fff" />
            </g>
          );
        })}
      </svg>
      <Headline text="우리 동네 뜨개 지도" at={10} size={land ? 72 : 64} x={120} y={land ? 140 : 120} />
      <Caption text={"가까운 이웃 · 모임 · 가게 · 작가가\n지도 위에 켜진다"} at={40} x={120} y={land ? 260 : 220} size={32} />
      <div style={{ position: "absolute", left: 120, top: land ? 420 : 360, display: "flex", gap: 14, opacity: interpolate(f, [70, 90], [0, 1], clamp) }}>
        {(Object.keys(KIND_COLOR) as (keyof typeof KIND_COLOR)[]).map((kd) => (
          <Chip key={kd} text={`● ${kd}`} bg={C.chip} color={KIND_COLOR[kd]} size={26} />
        ))}
      </div>
    </Scene>
  );
};
