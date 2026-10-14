# Marketing

The launch material, produced the way the review video was: scripted, never filmed by hand.

```
Scripts/Marketing/record-clips.sh        # 1. the take: Marketing/video/public/{take.mov,timeline.json}
cd Marketing/video && npm install        # 2. once
npm run render                           # 3. out/notchotp.mp4        (1920×1080, 23 s, with music)
npm run render:square                    #    out/notchotp-square.mp4 (1080×1080)
npm start                                #    Remotion Studio, to tune the cut
```

**The take.** `record-clips.sh` puts a plain gradient window behind the panel
(`Backdrop.swift`), records the 640 × 420 pt region around the notch with `screencapture -v -R`,
and plays `Scripts/Review/Recorder.swift --marketing`: hover, one code (GitHub, demo key, demo
sensor), lock, leave. The driver writes `timeline.json` — seconds into the take at which each
step started — so the cuts in `video/src/timeline.ts` are computed, not eyeballed. Re-record
and the video follows. Same requirements as the review recording: a notched Mac, Accessibility
and Screen Recording permissions, no NotchOTP already running.

**The video.** A Remotion project in `video/`: intro, three footage scenes with captions,
outro. The footage crops the menu bar items out of the take and paints the physical notch black
(the capture renders those pixels; the display does not). The system font is used on purpose:
the render runs on the Mac, and the panel is set in the same face.

**The music.** `video/public/music.mp3` is "Sun And Clouds" by FSM Team feat. < e s c p >,
CC BY 4.0, from https://www.free-stock-music.com/sun-and-clouds.html — calm, bright, 106 BPM,
and its own five-second fade-in carries the title so the panel opens as it reaches full level.
The composition fades it out with the picture. The licence wants a credit line next to the
video; it is tweet 12 of the thread. Chosen over a synthesised score because it is a real
arrangement; chosen over the other candidates (In The Zone, Flight, Synthetic, Moon Rover,
Lucid Dreaming) for the fade-in that fits the intro and the brightest, least busy texture.

**The thread.** `twitter-thread.md`, eleven tweets with character counts; the video goes on
the first one.

Two things the take cannot show, and why: typed text never reaches the search field from
synthetic input (the keystrokes go to the active app, and the panel cannot activate NotchOTP
from a non-activating click), and the first click into a freshly opened panel only gives it
key status — a row's tap gesture does not fire on it. The scenario clicks the blank header
first and the cut removes it (`focus` → `confirm`).
