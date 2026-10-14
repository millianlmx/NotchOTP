import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { FOOTAGE_HEIGHT_SHARE } from "./Footage";

export const FONT =
  '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Inter, sans-serif';

/** One line under the footage; springs up on entry, fades on the last frames. */
export const Caption = ({
  text,
  detail,
  durationInFrames,
}: {
  text: string;
  detail?: string;
  durationInFrames: number;
}) => {
  const frame = useCurrentFrame();
  const { fps, height, width } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 200, stiffness: 120 } });
  const exit = interpolate(frame, [durationInFrames - 8, durationInFrames - 1], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const size = Math.round(Math.min(width, height) * 0.052);

  return (
    <AbsoluteFill
      style={{
        top: height * FOOTAGE_HEIGHT_SHARE,
        height: height * (1 - FOOTAGE_HEIGHT_SHARE),
        alignItems: "center",
        justifyContent: "center",
        opacity: enter * exit,
        transform: `translateY(${(1 - enter) * 30}px)`,
        fontFamily: FONT,
        color: "#fff",
        textAlign: "center",
        padding: "0 80px",
      }}
    >
      <div style={{ fontSize: size, fontWeight: 700, letterSpacing: -0.5, lineHeight: 1.15 }}>
        {text}
      </div>
      {detail ? (
        <div style={{ fontSize: size * 0.5, marginTop: 14, color: "rgba(255,255,255,0.62)", fontWeight: 500 }}>
          {detail}
        </div>
      ) : null}
    </AbsoluteFill>
  );
};
