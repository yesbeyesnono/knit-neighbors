import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Scene, Headline, Caption, Card, Chip, clamp, Layout } from "../common";
import { C, SCENES } from "../theme";

const STEPS = [
  { t: "회원 글 · 신고 · 모임", d: "들어오는 즉시" },
  { t: "지기 AI 감지", d: "규칙 + AI 분류" },
  { t: "텔레그램 보고", d: "[승인] [반려] 버튼" },
  { t: "조치 · 기록", d: "되돌리기 가능" },
];
export const S6: React.FC<{ layout: Layout }> = ({ layout }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const land = layout === "landscape";
  const w = land ? 360 : 900, h = land ? 200 : 150, gap = land ? 80 : 40;
  const x0 = land ? (1920 - (w * 4 + gap * 3)) / 2 : 90, y0 = land ? 520 : 520;
  return (
    <Scene dur={SCENES.s6.dur}>
      <Headline text="혼자서도 운영된다" at={8} size={land ? 72 : 64} x={120} y={120} />
      <Caption text={"운영 담당 AI ‘지기’가 감지하고 보고한다 — 결정은 대표가 버튼 하나로\n1차 응대 · 가게 서류 확인 · 공지 타겟팅도 같은 AI"} at={30} x={120} y={230} size={30} width={land ? 1600 : 900} />
      <svg width={land ? 1920 : 1080} height={land ? 1080 : 1920} style={{ position: "absolute", left: 0, top: 0 }}>
        {STEPS.slice(0, -1).map((_, i) => {
          const o = interpolate(f, [40 + i * 22, 60 + i * 22], [0, 1], clamp);
          return land
            ? <path key={i} d={`M${x0 + (i + 1) * w + i * gap + 14} ${y0 + h / 2} h ${(gap - 28) * o} m -14 -12 l 14 12 l -14 12`} stroke={C.acc} strokeWidth={5} strokeLinecap="round" strokeLinejoin="round" fill="none" opacity={o} />
            : <path key={i} d={`M540 ${y0 + (i + 1) * h + i * gap + 10} v ${(gap - 20) * o}`} stroke={C.acc} strokeWidth={5} strokeLinecap="round" opacity={o} />;
        })}
      </svg>
      {STEPS.map((s, i) => {
        const p = spring({ frame: f - 20 - i * 22, fps, config: { damping: 18, stiffness: 140 } });
        const x = land ? x0 + i * (w + gap) : x0, y = land ? y0 : y0 + i * (h + gap);
        const hot = i === 1;
        return (
          <Card key={s.t} x={x} y={y} w={w} h={h} p={p} style={hot ? { background: C.chip, borderColor: C.btn } : undefined}>
            <div style={{ padding: 26 }}>
              <div style={{ fontSize: 30, fontWeight: 700, color: hot ? C.olive : C.ink }}>{s.t}</div>
              <div style={{ fontSize: 24, color: C.muted, marginTop: 10 }}>{s.d}</div>
            </div>
          </Card>
        );
      })}
      <div style={{ position: "absolute", left: 120, top: land ? 820 : 1360, display: "flex", gap: 12, opacity: interpolate(f, [130, 150], [0, 1], clamp) }}>
        <Chip text="AI 단독은 임시 숨김까지" size={24} /><Chip text="모든 조치 기록 · 되돌리기" size={24} /><Chip text="회원 글은 자료일 뿐, 지시는 대표만" size={24} />
      </div>
    </Scene>
  );
};
