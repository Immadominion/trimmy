import { useEffect, useRef, useState } from "react";
import { useFrame } from "@/lib/useFrame";
import { isEnabled, onChange, setEnabled, setMusic, setMusicPosition, tick } from "@/lib/sound";
import { getPosition } from "@/lib/stepper";
import { clamp01, smoothstep } from "@/lib/math";

/** The first screen with sound. Before it there is nothing to switch, so no switch. */
const FIRST_SOUND = 7;

const Icon = ({ src }: { src: string }) => (
  <span
    aria-hidden="true"
    className="block h-[18px] w-[18px] bg-current"
    style={{
      WebkitMask: `url(${src}) center / contain no-repeat`,
      mask: `url(${src}) center / contain no-repeat`,
    }}
  />
);

type Props = { music: string };

/**
 * The one sound control, bottom right, for the whole visit. It drives the
 * ordered soundtrack from the shared frame loop. The Icons8
 * speaker, so it matches the rest of the page.
 */
export function SoundSwitch({ music }: Props) {
  const [enabled, setEnabledState] = useState(isEnabled);
  const last = useRef(0);
  const node = useRef<HTMLDivElement>(null);
  const shown = useRef(false);

  useEffect(() => {
    // Keep the existing App prop compatible while retiring its generated soundtrack.
    setMusic(music === "/audio/music.mp3" ? "/audio/reading-piano.mp3" : music);
    setMusicPosition(getPosition());
    return onChange(() => setEnabledState(isEnabled()));
  }, [music]);

  useFrame((time) => {
    const dt = last.current ? Math.min(0.1, (time - last.current) / 1000) : 1 / 60;
    last.current = time;
    const p = getPosition();
    setMusicPosition(p);
    tick(dt);

    // Arrives with the floor screen, the same way its sound does, and stays.
    const el = node.current;
    if (!el) return;
    const k = smoothstep(clamp01((p - (FIRST_SOUND - 0.6)) / 0.6));
    el.style.opacity = String(k);
    const visible = k > 0.02;
    if (visible !== shown.current) {
      shown.current = visible;
      el.style.visibility = visible ? "visible" : "hidden";
    }
  });

  return (
    <div
      ref={node}
      className="group fixed bottom-[calc(env(safe-area-inset-bottom)+2rem)] right-8 z-20"
      style={{ opacity: 0, visibility: "hidden" }}
    >
    <button
      type="button"
      onClick={() => setEnabled(!enabled)}
      aria-pressed={enabled}
      aria-label={enabled ? "Turn sound off" : "Turn sound on"}
      aria-describedby="sound-credit"
      title={enabled ? "Sound on" : "Sound off"}
      className="grid h-11 w-11 place-items-center rounded-full border border-white/20 bg-white/[0.05] text-white/80 transition-colors duration-200 hover:border-white/35 hover:bg-white/10 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white"
    >
      <Icon src={enabled ? "/icons8-speaker.png" : "/icons8-no-audio.png"} />
    </button>
    <div id="sound-credit" role="tooltip" className="invisible absolute bottom-full right-0 w-64 pb-3 opacity-0 transition-opacity group-hover:visible group-hover:opacity-100 group-focus-within:visible group-focus-within:opacity-100">
      <p className="rounded-lg border border-white/15 bg-[#101112] px-4 py-3 text-left text-xs leading-relaxed text-white/75">
        Piano: Gymnopédie No. 1 · Kevin MacLeod.
        <a className="mt-1 block text-white underline underline-offset-4" href="/audio/CREDITS.html" target="_blank" rel="noreferrer">Music credit · CC BY 4.0</a>
      </p>
    </div>
    </div>
  );
}
