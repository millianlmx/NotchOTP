import marks from "../public/timeline.json";
import { FPS, makeSchedule } from "./schedule";

export { FPS } from "./schedule";
export type { Clip, FootageScene } from "./schedule";

/** Seconds into take.mov at which the named step of the take started. */
const at = (name: string): number => {
  const mark = marks.find((m) => m.name === name);
  if (!mark) throw new Error(`timeline.json has no "${name}" mark`);
  return mark.at;
};

export const schedule = makeSchedule(at);

export const frames = (seconds: number): number => Math.round(seconds * FPS);
