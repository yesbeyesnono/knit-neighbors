import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Scene, TsTitle, YarnLine, clamp, Layout } from "../common";
import { C, SCENES } from "../theme";

export const S7: React.FC<{ layout: Layout }> = ({ layout }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const land = layout === "landscape";
  const p = spring({ frame: f - 10, fps, config: { damping: 200, stiffness: 120 }, durationInFrames: 40 });
  const sub = interpolate(f, [45, 65], [0, 1], clamp);
  const size = land ? 200 : 150;
  return (
    <Scene dur={SCENES.s7.dur}>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", paddingBottom: 80 }}>
        <div style={{ opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>
          <TsTitle text="뜨개동네" size={size} color={C.olive} />
        </div>
        <div style={{ marginTop: 24, opacity: sub }}><YarnLine w={land ? 420 : 320} /></div>
        <div style={{ marginTop: 28, fontSize: land ? 40 : 34, color: C.ink, opacity: sub, letterSpacing: -0.5 }}>우리 동네 뜨개 이야기</div>
        <div style={{ marginTop: 18, fontSize: 26, color: C.muted, opacity: sub }}>이웃 · 단계 · 실 데이터 · 만남 · AI 운영</div>
      </div>
    </Scene>
  );
};
