import { Composition } from "remotion";
import { FPS } from "./timeline";
import { LaunchVideo, totalFrames } from "./LaunchVideo";

export const Root = () => (
  <>
    <Composition
      id="NotchOTP"
      component={LaunchVideo}
      durationInFrames={totalFrames}
      fps={FPS}
      width={1920}
      height={1080}
    />
    <Composition
      id="NotchOTPSquare"
      component={LaunchVideo}
      durationInFrames={totalFrames}
      fps={FPS}
      width={1080}
      height={1080}
    />
  </>
);
