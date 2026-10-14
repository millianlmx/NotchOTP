import { AbsoluteFill, OffthreadVideo, staticFile, useVideoConfig } from "remotion";
import { frames, type Clip } from "./timeline";

// take.mov is 640 × 420 pt around the notch at 2x: 1280 × 840 px. The 420 pt panel sits
// at x = 110 pt; the menu bar items on either side are cropped away, leaving 40 pt of
// backdrop beside the panel — the status items on this Mac reach 60 pt from the panel.
const TAKE_W = 1280;
const TAKE_H = 840;
const CROP_X = 180;
const CROP_W = TAKE_W - 2 * CROP_X;
// The physical notch is 185 × 32 pt (`NotchGeometry`); the capture renders those pixels,
// the display does not, so the video paints them black like the machine does.
const NOTCH_W = 370;
const NOTCH_H = 64;

/** How much of the canvas height the footage takes; the rest is for the captions. */
export const FOOTAGE_HEIGHT_SHARE = 0.68;

export const footageScale = (width: number, height: number): number =>
  Math.min((width - 120) / CROP_W, (height * FOOTAGE_HEIGHT_SHARE) / TAKE_H);

/** The cropped take, hung from the top edge like the panel is, inside a thin bezel. */
export const Footage = ({ clip }: { clip: Clip }) => {
  const { width, height } = useVideoConfig();
  const s = footageScale(width, height);
  const w = CROP_W * s;
  const h = TAKE_H * s;

  return (
    <AbsoluteFill style={{ alignItems: "center" }}>
      <div
        style={{
          position: "relative",
          width: w,
          height: h,
          overflow: "hidden",
          borderRadius: `0 0 ${36 * s}px ${36 * s}px`,
          boxShadow: "0 40px 120px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.08)",
        }}
      >
        <OffthreadVideo
          src={staticFile("take.mov")}
          startFrom={frames(clip.from)}
          endAt={frames(clip.to)}
          muted
          style={{
            position: "absolute",
            left: -CROP_X * s,
            top: 0,
            width: TAKE_W * s,
            height: h,
          }}
        />
        <div
          style={{
            position: "absolute",
            top: 0,
            left: (w - NOTCH_W * s) / 2,
            width: NOTCH_W * s,
            height: NOTCH_H * s,
            background: "#000",
            borderRadius: `0 0 ${14 * s}px ${14 * s}px`,
          }}
        />
      </div>
    </AbsoluteFill>
  );
};
