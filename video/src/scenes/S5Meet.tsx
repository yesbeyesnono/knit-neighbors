import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Scene, Headline, Caption, Card, Chip, clamp, Layout } from "../common";
import { C, SCENES } from "../theme";

const ITEMS = [
  { title: "모임", sub: "토요일 오후, 성수 카페에서 코바늘 가방", meta: "4 / 6명 · 배울 기법: 한길 긴뜨기" },
  { title: "클래스", sub: "쎄비하우스 원데이 · 모티프 블랭킷", meta: "신청 → 확정 → 단체방 자동 입장" },
  { title: "채팅", sub: "친구 · 모임 · 클래스 대화", meta: "사진 전송 · 모임 정보 시트" },
];
export const S5: React.FC<{ layout: Layout }> = ({ layout }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const land = layout === "landscape";
  const w = land ? 520 : 900, h = land ? 300 : 260, gap = land ? 40 : 30;
  const x0 = land ? (1920 - (w * 3 + gap * 2)) / 2 : 90, y0 = land ? 460 : 500;
  const link = interpolate(f, [90, 130], [0, 1], clamp);
  return (
    <Scene dur={SCENES.s5.dur}>
      <Headline text="만남으로 이어진다" at={8} size={land ? 72 : 64} x={120} y={120} />
      <Caption text="지도에서 본 이웃과 모임 · 클래스 · 채팅으로 — 신청과 확정은 앱 안에서" at={30} x={120} y={230} size={30} width={land ? 1600 : 900} />
      <svg width={land ? 1920 : 1080} height={land ? 1080 : 1920} style={{ position: "absolute", left: 0, top: 0 }}>
        {land ? (
          <path d={`M${x0 + w} ${y0 + h / 2} H ${x0 + w + gap * link} M${x0 + w * 2 + gap} ${y0 + h / 2} H ${x0 + w * 2 + gap + gap * link}`} stroke={C.acc} strokeWidth={6} strokeLinecap="round" />
        ) : (
          <path d={`M540 ${y0 + h} V ${y0 + h + gap * link} M540 ${y0 + h * 2 + gap} V ${y0 + h * 2 + gap + gap * link}`} stroke={C.acc} strokeWidth={6} strokeLinecap="round" />
        )}
      </svg>
      {ITEMS.map((it, i) => {
        const p = spring({ frame: f - 20 - i * 18, fps, config: { damping: 18, stiffness: 140 } });
        const x = land ? x0 + i * (w + gap) : x0, y = land ? y0 : y0 + i * (h + gap);
        return (
          <Card key={it.title} x={x} y={y} w={w} h={h} p={p}>
            <div style={{ padding: 30 }}>
              <Chip text={it.title} bg={C.olive} color="#fff" size={24} />
              <div style={{ fontSize: land ? 32 : 30, fontWeight: 700, marginTop: 22, lineHeight: 1.35 }}>{it.sub}</div>
              <div style={{ fontSize: 24, color: C.muted, marginTop: 14 }}>{it.meta}</div>
            </div>
          </Card>
        );
      })}
    </Scene>
  );
};
