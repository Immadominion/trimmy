import {useCallback, useEffect, useRef, useState} from 'react';
export type WorkCue = 'select' | 'paper' | 'saved' | 'complete';
const sources: Record<WorkCue, string> = {select: 'soft_tap.wav', paper: 'paper_open.wav', saved: 'saved_mark_v1.wav', complete: 'arrival.wav'};
const key = 'trimmy.web.workSound';
/** The same four mobile cues, played only after interaction and never in the background. */
export function useWorkSound() {
  const [enabled, setEnabled] = useState(() => {try {return localStorage.getItem(key) !== 'off';} catch {return true;}});
  const players = useRef(new Map<WorkCue, HTMLAudioElement>());
  const stop = useCallback(() => {for (const player of players.current.values()) {player.pause(); player.currentTime = 0;}}, []);
  useEffect(() => {
    const visibility = () => {if (document.hidden) stop();};
    document.addEventListener('visibilitychange', visibility);
    if (!enabled) stop();
    return () => {document.removeEventListener('visibilitychange', visibility); stop();};
  }, [enabled, stop]);
  const play = useCallback((cue: WorkCue) => {
    if (!enabled || document.hidden || typeof Audio === 'undefined') return;
    stop();
    let player = players.current.get(cue);
    if (!player) {player = new Audio(`/trimmy/work-sounds/${sources[cue]}`); player.volume = .4; players.current.set(cue, player);}
    void player.play().catch(() => { /* Audio permission never blocks an assignment. */ });
  }, [enabled, stop]);
  const toggle = useCallback(() => {setEnabled(current => {
    const next = !current;
    try {localStorage.setItem(key, next ? 'on' : 'off');} catch { /* The preference still applies for this session. */ }
    return next;
  });}, []);
  return {enabled, toggle, play};
}
