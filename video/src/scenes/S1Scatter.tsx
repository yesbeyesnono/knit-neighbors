import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { Scene, Headline, Caption, YarnBall, clamp, Layout } from "../common";
import { C, SCENES } from "../theme";

// 흩어진 실뭉치: 서로 모르는 동네 뜨개인들
// 고정 의사난수(렌더마다 같은 배치)
const seed = (i: number) => { let x = Math.sin(i * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };
export const S1: React.FC<{ layout: Layout }> = ({ layout }) => {
  const f = useCurrentFrame();
  const W = layout === "landscape" ? 1920 : 1080, H = layout === "landscape" ? 1080 : 1920;
  const n = 14;
  const balls = Array.from({ length: n }, (_, i) => {
    const bx = 160 + seed(i) * (W - 320), by = (layout === "landscape" ? 330 : 700) + seed(i + 31) * (layout === "landscape" ? 560 : 900);
    const drift = Math.sin((f + i * 17) / 40) * 6;
    const r = 26 + seed(i + 7) * 18;
    const appear = interpolate(f, [i * 4, i * 4 + 14], [0, 1], clamp);
    return <YarnBall key={i} x={bx} y={by + drift} r={r} opacity={appear} scale={0.6 + 0.4 * appear} color={i % 3 === 0 ? C.chip : C.btn} />;
  });
  return (
    <Scene dur={SCENES.s1.dur}>
      <svg width={W} height={H} style={{ position: "absolute", left: 0, top: 0 }}>{balls}</svg>
      <Headline text={"뜨개는 혼자 하기엔\n아까운 취미"} at={12} size={layout === "landscape" ? 72 : 64} x={120} y={120} />
      <Caption text="같은 동네에 뜨는 사람이 있는데, 서로 모른다" at={50} x={120} y={layout === "landscape" ? 330 : 310} size={32} />
    </Scene>
  );
};
