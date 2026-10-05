import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Scene, Headline, Caption, clamp, Layout } from "../common";
import { C, SCENES } from "../theme";

// DB techniques(코바늘, 2026-10-05) 에서 가져온 이름·단계·선행
const T: { id: string; lv: number; name: string; pre: string[] }[] = [
  { id: "C01", lv: 1, name: "사슬뜨기", pre: [] }, { id: "C02", lv: 1, name: "짧은뜨기", pre: ["C01"] }, { id: "C03", lv: 1, name: "빼뜨기", pre: ["C01"] }, { id: "C04", lv: 1, name: "기둥코·왕복뜨기", pre: ["C01", "C02"] },
  { id: "C05", lv: 2, name: "매직링", pre: ["C01"] }, { id: "C06", lv: 2, name: "원형뜨기", pre: ["C02", "C05"] }, { id: "C07", lv: 2, name: "코 늘리기", pre: ["C02"] }, { id: "C08", lv: 2, name: "코 줄이기", pre: ["C02"] },
  { id: "C09", lv: 2, name: "줄무늬 배색", pre: ["C02"] }, { id: "C10", lv: 2, name: "이랑뜨기", pre: ["C02"] }, { id: "C11", lv: 2, name: "파트 조립·꿰매기", pre: ["C02", "C03"] }, { id: "C37", lv: 2, name: "되돌아 짧은뜨기", pre: ["C02"] },
  { id: "C12", lv: 3, name: "긴뜨기", pre: ["C02", "C04"] }, { id: "C13", lv: 3, name: "한길 긴뜨기", pre: ["C02", "C04"] }, { id: "C14", lv: 3, name: "피코뜨기", pre: ["C01", "C02"] }, { id: "C15", lv: 3, name: "솔잎뜨기", pre: ["C13"] },
  { id: "C16", lv: 3, name: "네트뜨기", pre: ["C01", "C02"] }, { id: "C17", lv: 3, name: "모티프 이어뜨기", pre: ["C03", "C06"] }, { id: "C30", lv: 3, name: "짧은 링뜨기", pre: ["C02"] }, { id: "C36", lv: 3, name: "칠보뜨기", pre: ["C01", "C02"] },
  { id: "C18", lv: 4, name: "두길 긴뜨기", pre: ["C13"] }, { id: "C19", lv: 4, name: "구슬뜨기", pre: ["C13"] }, { id: "C20", lv: 4, name: "팝콘뜨기", pre: ["C19"] }, { id: "C21", lv: 4, name: "교차뜨기", pre: ["C13"] },
  { id: "C22", lv: 4, name: "배색뜨기", pre: ["C09"] }, { id: "C23", lv: 4, name: "의류 구성", pre: ["C07", "C08", "C11"] }, { id: "C31", lv: 4, name: "세길 긴뜨기", pre: ["C18"] }, { id: "C32", lv: 4, name: "네길 긴뜨기", pre: ["C31"] }, { id: "C38", lv: 4, name: "변형 구슬뜨기", pre: ["C19"] },
  { id: "C24", lv: 5, name: "걸어뜨기", pre: ["C13"] }, { id: "C25", lv: 5, name: "바구니뜨기", pre: ["C24"] }, { id: "C26", lv: 5, name: "스타크로셰", pre: ["C12"] }, { id: "C27", lv: 5, name: "감아뜨기", pre: ["C13"] },
  { id: "C28", lv: 5, name: "한붓뜨기", pre: ["C06", "C17"] }, { id: "C29", lv: 5, name: "브레이드", pre: ["C11", "C13"] }, { id: "C33", lv: 5, name: "Y자·역Y자뜨기", pre: ["C18"] }, { id: "C34", lv: 5, name: "X자뜨기", pre: ["C18"] }, { id: "C35", lv: 5, name: "삼각뜨기", pre: ["C33"] },
];
const LV = ["입문", "초급", "중급", "상급", "전문"];

export const S3: React.FC<{ layout: Layout }> = ({ layout }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const land = layout === "landscape";
  // 격자: 단계별 열. 가로판은 열 5개 옆으로, 세로판은 열 폭을 줄여 5열
  const colW = land ? 300 : 200, cellH = land ? 48 : 40, gap = 8;
  const ox = land ? 120 : 40, oy = land ? 380 : 560;
  const pos: Record<string, { x: number; y: number }> = {};
  const counters = [0, 0, 0, 0, 0];
  T.forEach((t) => { const c = t.lv - 1; pos[t.id] = { x: ox + c * (colW + 24), y: oy + 70 + counters[c] * (cellH + gap) }; counters[c]++; });
  const startAt = (t: { lv: number; id: string }) => 20 + (t.lv - 1) * 16 + (parseInt(t.id.slice(1), 10) % 7) * 3;
  const myLevel = 3; // 데모: 중급까지 채워짐
  return (
    <Scene dur={SCENES.s3.dur}>
      <Headline text="내 뜨개 단계" at={8} size={land ? 72 : 64} x={120} y={120} />
      <Caption text={land ? "코바늘 38 · 대바늘 28 기법이 선행 관계로 이어진 실력 지도 — 인증한 작품이 단계를 채운다" : "코바늘 38 · 대바늘 28 기법이\n선행 관계로 이어진 실력 지도"} at={30} x={120} y={land ? 230 : 220} size={30} width={land ? 1500 : 900} />
      <svg width={land ? 1920 : 1080} height={land ? 1080 : 1920} style={{ position: "absolute", left: 0, top: 0 }}>
        {T.map((t) => t.pre.map((p) => {
          const a = pos[p], b = pos[t.id]; if (!a || !b) return null;
          const pl = T.find((x) => x.id === p)?.lv ?? 0; if (pl === t.lv) return null; // 같은 열 안의 선행은 선을 긋지 않음
          const o = interpolate(f, [startAt(t), startAt(t) + 14], [0, 1], clamp);
          return <path key={`${p}-${t.id}`} d={`M${a.x + colW} ${a.y + cellH / 2} C ${a.x + colW + 60} ${a.y + cellH / 2}, ${b.x - 60} ${b.y + cellH / 2}, ${b.x} ${b.y + cellH / 2}`} fill="none" stroke={C.line} strokeWidth={2} opacity={o} />;
        }))}
        {LV.map((n, i) => (
          <text key={n} x={ox + i * (colW + 24)} y={oy + 40} fontSize={land ? 30 : 24} fontWeight={700} fill={i < myLevel ? C.olive : C.muted} opacity={interpolate(f, [10 + i * 6, 24 + i * 6], [0, 1], clamp)}>{i + 1}단계 {n}</text>
        ))}
        {T.map((t) => {
          const s = spring({ frame: f - startAt(t), fps, config: { damping: 16, stiffness: 160 } });
          const p = pos[t.id], done = t.lv <= myLevel;
          return (
            <g key={t.id} transform={`translate(${p.x} ${p.y})`} opacity={s}>
              <rect width={colW} height={cellH} rx={12} fill={done ? C.btn : "#fff"} stroke={done ? C.acc : C.line} strokeWidth={2} />
              <text x={16} y={cellH / 2 + (land ? 9 : 7)} fontSize={land ? 24 : 19} fontWeight={500} fill={done ? C.btnInk : C.ink}>{t.name}</text>
              {done ? <circle cx={colW - 22} cy={cellH / 2} r={8} fill={C.olive} /> : null}
            </g>
          );
        })}
      </svg>
    </Scene>
  );
};
