import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Scene, Headline, Caption, Card, Chip, YarnBall, clamp, Layout } from "../common";
import { C, SCENES } from "../theme";

const fmt = (n: number) => Math.round(n).toLocaleString("ko-KR");
export const S4: React.FC<{ layout: Layout }> = ({ layout }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const land = layout === "landscape";
  const cardIn = spring({ frame: f - 20, fps, config: { damping: 18, stiffness: 140 } });
  const flow = interpolate(f, [60, 100], [0, 1], clamp);
  const dictIn = spring({ frame: f - 80, fps, config: { damping: 18, stiffness: 140 } });
  const cnt = interpolate(f, [90, 150], [0, 1], clamp);
  const stats = [
    { n: 1156 * cnt, unit: "종", label: "표준 실" },
    { n: 27000 * cnt, unit: "+", label: "색" },
    { n: 1242 * cnt, unit: "곳", label: "판매처" },
  ];
  // 가로: 왼쪽 인증 카드, 오른쪽 실 사전 카드 / 세로: 위·아래
  const cardX = land ? 120 : 90, cardY = land ? 330 : 420, cardW = land ? 620 : 900, cardH = land ? 560 : 520;
  const dictX = land ? 1060 : 90, dictY = land ? 330 : 1060, dictW = land ? 740 : 900, dictH = land ? 560 : 560;
  return (
    <Scene dur={SCENES.s4.dur}>
      <Headline text="작품 하나가 데이터가 된다" at={8} size={land ? 72 : 60} x={120} y={120} />
      <Caption text="작품 인증에 적은 실 이름·색·사용량이 표준 실 사전으로 묶인다" at={30} x={120} y={land ? 230 : 230} size={30} width={land ? 1600 : 900} />
      <Card x={cardX} y={cardY} w={cardW} h={cardH} p={cardIn}>
        <div style={{ padding: 32 }}>
          <div style={{ display: "flex", gap: 24, alignItems: "center" }}>
            <div style={{ width: 180, height: 180, borderRadius: 20, background: C.chip, display: "flex", alignItems: "center", justifyContent: "center" }}>
              <svg width={120} height={120} viewBox="-60 -60 120 120"><YarnBall x={0} y={0} r={50} /></svg>
            </div>
            <div>
              <div style={{ fontSize: 38, fontWeight: 700 }}>코바늘 토트백</div>
              <div style={{ fontSize: 26, color: C.muted, marginTop: 6 }}>작품 인증 · 가방</div>
              <div style={{ marginTop: 14, display: "flex", gap: 8, flexWrap: "wrap" }}>
                <Chip text="한길 긴뜨기" size={22} /><Chip text="코 늘리기" size={22} /><Chip text="파트 조립" size={22} />
              </div>
            </div>
          </div>
          <div style={{ marginTop: 28, borderTop: `2px solid ${C.line}`, paddingTop: 22, fontSize: 28, lineHeight: 1.6 }}>
            <div><span style={{ color: C.muted }}>실</span>&nbsp;&nbsp;낙양모사 아임울 · 베이지 · 2볼</div>
            <div><span style={{ color: C.muted }}>규격</span>&nbsp;&nbsp;50g / 110m · 울 100%</div>
          </div>
        </div>
      </Card>
      {/* 흐름 화살표 */}
      {land ? (
        <svg width={1920} height={1080} style={{ position: "absolute", left: 0, top: 0 }}>
          <path d={`M${cardX + cardW + 30} 610 H ${cardX + cardW + 30 + 250 * flow}`} stroke={C.acc} strokeWidth={6} strokeLinecap="round" fill="none" strokeDasharray="14 14" />
          <path d="M-12 -14 L10 0 L-12 14" transform={`translate(${cardX + cardW + 30 + 250 * flow} 610)`} fill="none" stroke={C.acc} strokeWidth={6} strokeLinecap="round" strokeLinejoin="round" opacity={flow} />
        </svg>
      ) : (
        <svg width={1080} height={1920} style={{ position: "absolute", left: 0, top: 0 }}>
          <path d={`M540 ${cardY + cardH + 20} V ${cardY + cardH + 20 + 80 * flow}`} stroke={C.acc} strokeWidth={6} strokeLinecap="round" fill="none" strokeDasharray="14 14" />
        </svg>
      )}
      <Card x={dictX} y={dictY} w={dictW} h={dictH} p={dictIn} style={{ background: C.chip, borderColor: C.btn }}>
        <div style={{ padding: 36 }}>
          <div style={{ fontSize: 34, fontWeight: 700, color: C.olive }}>표준 실 사전</div>
          <div style={{ fontSize: 24, color: C.muted, marginTop: 4 }}>브랜드 · 규격 · 소재 · 색 번호 · 판매처</div>
          <div style={{ display: "flex", gap: 24, marginTop: 36 }}>
            {stats.map((s) => (
              <div key={s.label} style={{ flex: 1, background: "#fff", borderRadius: 18, padding: "22px 20px" }}>
                <div style={{ fontSize: land ? 54 : 48, fontWeight: 700, color: C.ink, letterSpacing: -1 }}>{fmt(s.n)}<span style={{ fontSize: 26, color: C.muted, marginLeft: 4 }}>{s.unit}</span></div>
                <div style={{ fontSize: 24, color: C.muted, marginTop: 4 }}>{s.label}</div>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 30, fontSize: 26, color: C.olive, opacity: interpolate(f, [140, 160], [0, 1], clamp) }}>→ 어떤 실을 어디서 많이 쓰는지 보이고, 호환 실을 추천한다</div>
        </div>
      </Card>
    </Scene>
  );
};
