import React from "react";
import { Composition } from "remotion";
import { Intro } from "./Intro";
import { FPS, TOTAL } from "./theme";

export const Root: React.FC = () => (
  <>
    <Composition id="KnitIntro16x9" component={Intro} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} defaultProps={{ layout: "landscape" as const }} />
    <Composition id="KnitIntro9x16" component={Intro} durationInFrames={TOTAL} fps={FPS} width={1080} height={1920} defaultProps={{ layout: "portrait" as const }} />
  </>
);
