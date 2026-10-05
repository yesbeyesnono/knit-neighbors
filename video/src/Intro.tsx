import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import { SCENES } from "./theme";
import { Layout } from "./common";
import { S1 } from "./scenes/S1Scatter";
import { S2 } from "./scenes/S2Map";
import { S3 } from "./scenes/S3Skill";
import { S4 } from "./scenes/S4Data";
import { S5 } from "./scenes/S5Meet";
import { S6 } from "./scenes/S6Jigi";
import { S7 } from "./scenes/S7Logo";

export const Intro: React.FC<{ layout: Layout }> = ({ layout }) => (
  <AbsoluteFill style={{ background: "#fff" }}>
    <Sequence from={SCENES.s1.from} durationInFrames={SCENES.s1.dur} name="1 흩어진 실뭉치"><S1 layout={layout} /></Sequence>
    <Sequence from={SCENES.s2.from} durationInFrames={SCENES.s2.dur} name="2 지도"><S2 layout={layout} /></Sequence>
    <Sequence from={SCENES.s3.from} durationInFrames={SCENES.s3.dur} name="3 내 뜨개 단계"><S3 layout={layout} /></Sequence>
    <Sequence from={SCENES.s4.from} durationInFrames={SCENES.s4.dur} name="4 실 데이터"><S4 layout={layout} /></Sequence>
    <Sequence from={SCENES.s5.from} durationInFrames={SCENES.s5.dur} name="5 만남"><S5 layout={layout} /></Sequence>
    <Sequence from={SCENES.s6.from} durationInFrames={SCENES.s6.dur} name="6 지기 AI"><S6 layout={layout} /></Sequence>
    <Sequence from={SCENES.s7.from} durationInFrames={SCENES.s7.dur} name="7 로고"><S7 layout={layout} /></Sequence>
  </AbsoluteFill>
);
