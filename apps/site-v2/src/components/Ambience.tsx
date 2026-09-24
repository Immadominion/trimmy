import { useFrame } from "@/lib/useFrame";
import { getPosition } from "@/lib/stepper";
import { setAmbience } from "@/lib/sound";
import { clamp01, smoothstep } from "@/lib/math";

/** How far from its screen, in screens, a sound is still audible. */
const REACH = 0.6;

type Props = { index: number; src: string };

/**
 * A screen's ambient sound. Its level follows how present the screen is, so it
 * arrives and leaves with the screen. Renders nothing; the switch is global.
 */
export function Ambience({ index, src }: Props) {
  useFrame(() => {
    const distance = Math.abs(getPosition() - index);
    const recording = src === "/audio/floor.mp3" ? "/audio/floor-quiet.mp3" : src;
    setAmbience(recording, 1 - smoothstep(clamp01(distance / REACH)));
  });
  return null;
}
