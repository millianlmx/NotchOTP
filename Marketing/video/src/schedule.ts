// The cut, as pure arithmetic over the marks Scripts/Review/Recorder.swift --marketing
// writes to public/timeline.json (seconds into take.mov at which each step started).
// Nothing here is eyeballed; re-record the take and the cuts follow.

export const FPS = 30;

/** Length of take.mov (`ffprobe`); the last mark can land after it. */
export const TAKE_DURATION = 20.95;

export const INTRO = 2.6;
export const OUTRO = 5.2;

/** A continuous piece of the take, in seconds of take.mov. */
export type Clip = { from: number; to: number };
/** A caption; `from` is in seconds of take.mov. */
export type Line = { from: number; text: string; detail?: string };
export type FootageScene = { clip: Clip; lines: Line[] };

export type Schedule = {
  scenes: FootageScene[];
  /** Length of the whole video, in seconds. */
  total: number;
};

export const makeSchedule = (at: (name: string) => number): Schedule => {
  const hover: Clip = { from: at("hover") - 0.6, to: at("focus") - 0.1 };
  const confirm: Clip = { from: at("confirm") - 0.1, to: at("code") + 2.7 };
  const lock: Clip = { from: at("lock") - 0.4, to: Math.min(at("done"), TAKE_DURATION) };

  const scenes: FootageScene[] = [
    {
      clip: hover,
      lines: [{ from: hover.from, text: "Hover the notch.", detail: "No window, no Dock icon, no ⌘Tab." }],
    },
    {
      clip: confirm,
      lines: [
        { from: confirm.from, text: "Pick an account." },
        { from: at("confirm") + 0.5, text: "Touch the sensor.", detail: "One fingerprint per code — the prompt lives inside the panel." },
        { from: at("confirm") + 2.9, text: "It's on your clipboard.", detail: "Computed on the YubiKey. Wiped after 45 s." },
      ],
    },
    {
      clip: lock,
      lines: [
        { from: lock.from, text: "Lock it, or just walk away.", detail: "Codes gone, list gone, applet relocked on the key." },
        { from: at("leave") + 0.9, text: "Nothing stored. Nothing synced.", detail: "The secrets never leave the YubiKey." },
      ],
    },
  ];

  const total = INTRO + scenes.reduce((sum, scene) => sum + scene.clip.to - scene.clip.from, 0) + OUTRO;
  return { scenes, total };
};
