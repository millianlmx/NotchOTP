import {
  AbsoluteFill,
  Audio,
  Img,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Caption, FONT } from "./Caption";
import { Footage } from "./Footage";
import { INTRO, OUTRO, type FootageScene } from "./schedule";
import { frames, schedule } from "./timeline";

// MARK: - Schedule

const INTRO_FRAMES = frames(INTRO);
const OUTRO_FRAMES = frames(OUTRO);
const { scenes } = schedule;
const sceneFrames = scenes.map((scene) => frames(scene.clip.to - scene.clip.from));
export const totalFrames = INTRO_FRAMES + sceneFrames.reduce((a, b) => a + b, 0) + OUTRO_FRAMES;

// MARK: - Scenes

const Background = () => (
  <AbsoluteFill
    style={{
      background:
        "radial-gradient(ellipse 70% 55% at 50% 0%, rgba(124, 92, 220, 0.35), transparent 70%), #0a0a10",
    }}
  />
);

const Intro = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const title = spring({ frame, fps, config: { damping: 200, stiffness: 90 } });
  const tagline = spring({ frame: frame - 10, fps, config: { damping: 200, stiffness: 90 } });
  const out = interpolate(frame, [INTRO_FRAMES - 10, INTRO_FRAMES - 1], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const base = Math.min(width, height);

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: out, fontFamily: FONT, color: "#fff" }}>
      <Img
        src={staticFile("icon.png")}
        style={{
          width: base * 0.2,
          height: base * 0.2,
          transform: `scale(${0.7 + 0.3 * title})`,
          opacity: title,
          filter: "drop-shadow(0 30px 60px rgba(0,0,0,0.5))",
        }}
      />
      <div
        style={{
          fontSize: base * 0.11,
          fontWeight: 800,
          letterSpacing: -3,
          marginTop: 24,
          opacity: title,
          transform: `translateY(${(1 - title) * 40}px)`,
        }}
      >
        NotchOTP
      </div>
      <div
        style={{
          fontSize: base * 0.038,
          fontWeight: 500,
          color: "rgba(255,255,255,0.7)",
          opacity: tagline,
          transform: `translateY(${(1 - tagline) * 30}px)`,
          textAlign: "center",
        }}
      >
        Your YubiKey codes, in your Mac's notch.
      </div>
    </AbsoluteFill>
  );
};

const FootageSceneView = ({ scene, durationInFrames }: { scene: FootageScene; durationInFrames: number }) => (
  <>
    <Footage clip={scene.clip} />
    {scene.lines.map((line, index) => {
      const start = frames(line.from - scene.clip.from);
      const next = scene.lines[index + 1];
      const end = next ? frames(next.from - scene.clip.from) : durationInFrames;
      return (
        <Sequence key={line.text} from={start} durationInFrames={end - start} layout="none">
          <Caption text={line.text} detail={line.detail} durationInFrames={end - start} />
        </Sequence>
      );
    })}
  </>
);

const facts = ["Secrets stay on the key", "One gesture, one code", "No account, no telemetry", "macOS 14+ · Touch ID or Apple Watch"];

const Outro = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const base = Math.min(width, height);
  const title = spring({ frame, fps, config: { damping: 200, stiffness: 100 } });

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT, color: "#fff" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 28, opacity: title, transform: `translateY(${(1 - title) * 30}px)` }}>
        <Img src={staticFile("icon.png")} style={{ width: base * 0.13, height: base * 0.13 }} />
        <div>
          <div style={{ fontSize: base * 0.08, fontWeight: 800, letterSpacing: -2, lineHeight: 1 }}>NotchOTP</div>
          <div style={{ fontSize: base * 0.032, color: "rgba(255,255,255,0.7)", marginTop: 10, fontWeight: 500 }}>
            $2.99 on the Mac App Store
          </div>
        </div>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 10, marginTop: base * 0.06, alignItems: "flex-start" }}>
        {facts.map((fact, index) => {
          const enter = spring({ frame: frame - 12 - index * 7, fps, config: { damping: 200, stiffness: 120 } });
          return (
            <div
              key={fact}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 16,
                fontSize: base * 0.03,
                fontWeight: 500,
                opacity: enter,
                transform: `translateX(${(1 - enter) * -24}px)`,
              }}
            >
              <span style={{ width: 10, height: 10, borderRadius: 5, background: "#34c759", display: "inline-block" }} />
              {fact}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// MARK: - Composition

export const LaunchVideo = () => {
  let cursor = INTRO_FRAMES;
  return (
    <AbsoluteFill>
      <Background />
      {/* "Sun And Clouds" by < e s c p > (FSM Team), CC BY 4.0 — credit line in
          ../twitter-thread.md. Its own 5 s fade-in carries the title; the panel opens as
          it reaches full level. Faded out over the last two seconds with the picture. */}
      <Audio
        src={staticFile("music.mp3")}
        volume={(frame) =>
          interpolate(frame, [totalFrames - frames(2), totalFrames - 1], [0.85, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          })
        }
      />
      <Sequence durationInFrames={INTRO_FRAMES} layout="none">
        <Intro />
      </Sequence>
      {scenes.map((scene, index) => {
        const from = cursor;
        cursor += sceneFrames[index];
        return (
          <Sequence key={index} from={from} durationInFrames={sceneFrames[index]} layout="none">
            <FootageSceneView scene={scene} durationInFrames={sceneFrames[index]} />
          </Sequence>
        );
      })}
      <Sequence from={cursor} durationInFrames={OUTRO_FRAMES} layout="none">
        <Outro />
      </Sequence>
    </AbsoluteFill>
  );
};
