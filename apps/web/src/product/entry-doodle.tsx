import type {CSSProperties} from 'react';
import {art} from './ui';

/**
 * The right half of the entry screens: a few small desk objects doodled
 * around one larger piece, with hand-drawn trails and sparkles. Decorative
 * only; the left half carries every word and action.
 */
export type DoodleScene = 'welcome' | 'note' | 'practice' | 'review' | 'order' | 'account' | 'reminders' | 'money' | 'preserved';

/** x and y place the centre in % of the panel; size is % of its shorter side. */
interface Piece {readonly src: string; readonly x: number; readonly y: number; readonly size: number; readonly turn?: number; readonly coin?: boolean}
interface Scene {
  readonly hero: Piece; readonly around: readonly Piece[];
  /** Indexes into `around`, in the order a pen would wander through them. */
  readonly trail: readonly number[];
  readonly sparks: readonly (readonly [number, number])[];
}

const doodle = (name: string) => art(`doodles/${name}.webp`);
const scenes: Record<DoodleScene, Scene> = {
  welcome: {hero: {src: doodle('sal-chair'), x: 55, y: 55, size: 44}, around: [
    {src: doodle('coffee'), x: 21, y: 19, size: 14, turn: -10}, {src: doodle('newspaper'), x: 73, y: 15, size: 14, turn: 9},
    {src: doodle('skyscraper'), x: 89, y: 47, size: 12, turn: 4}, {src: doodle('taxi'), x: 13, y: 60, size: 14, turn: -5},
    {src: doodle('clock'), x: 86, y: 85, size: 11, turn: 8}, {src: doodle('briefcase'), x: 30, y: 88, size: 12, turn: -6}],
    trail: [3, 0, 1, 2], sparks: [[42, 10], [93, 22], [8, 36], [60, 92], [8, 86]]},
  note: {hero: {src: doodle('newspaper'), x: 48, y: 50, size: 32, turn: -6}, around: [
    {src: doodle('pencil'), x: 19, y: 20, size: 14, turn: -14}, {src: doodle('coffee'), x: 77, y: 17, size: 14, turn: 8},
    {src: doodle('plant'), x: 90, y: 50, size: 11, turn: 4}, {src: doodle('reports'), x: 76, y: 82, size: 16, turn: 7},
    {src: doodle('clock'), x: 15, y: 70, size: 12, turn: -6}, {src: doodle('folders'), x: 36, y: 89, size: 11, turn: 5}],
    trail: [4, 0, 1, 2], sparks: [[46, 9], [94, 28], [7, 44], [58, 93], [92, 72]]},
  practice: {hero: {src: doodle('chart-board'), x: 53, y: 49, size: 31}, around: [
    {src: art('token-AAPLx.webp'), x: 20, y: 25, size: 10, turn: -8, coin: true}, {src: art('token-TSLAx.webp'), x: 76, y: 15, size: 8, turn: 10, coin: true},
    {src: art('token-METAx.webp'), x: 24, y: 73, size: 9, turn: 6, coin: true}, {src: doodle('magnifier'), x: 80, y: 77, size: 15, turn: -10},
    {src: doodle('ticker'), x: 87, y: 45, size: 11, turn: 6}, {src: doodle('coffee'), x: 45, y: 89, size: 10, turn: -6}],
    trail: [2, 0, 1, 4], sparks: [[43, 11], [94, 26], [8, 48], [64, 93], [9, 90]]},
  review: {hero: {src: doodle('calculator'), x: 50, y: 50, size: 28, turn: -6}, around: [
    {src: doodle('reports'), x: 21, y: 21, size: 15, turn: 8}, {src: doodle('balance'), x: 78, y: 18, size: 14, turn: -6},
    {src: doodle('pencil'), x: 88, y: 58, size: 11, turn: 18}, {src: doodle('magnifier'), x: 17, y: 69, size: 13, turn: -8},
    {src: doodle('coffee'), x: 70, y: 86, size: 11, turn: 6}, {src: doodle('folders'), x: 34, y: 90, size: 10, turn: -4}],
    trail: [3, 0, 1, 2], sparks: [[46, 10], [94, 34], [7, 44], [54, 94], [92, 88]]},
  order: {hero: {src: doodle('trophy'), x: 50, y: 48, size: 32}, around: [
    {src: doodle('ticker'), x: 21, y: 20, size: 16, turn: -8}, {src: doodle('chart-board'), x: 79, y: 17, size: 13, turn: 8},
    {src: doodle('coffee'), x: 88, y: 55, size: 10, turn: -6}, {src: doodle('briefcase'), x: 73, y: 84, size: 14, turn: -6},
    {src: doodle('newspaper'), x: 16, y: 70, size: 12, turn: 6}, {src: doodle('clock'), x: 38, y: 90, size: 9, turn: 4}],
    trail: [4, 0, 1, 2], sparks: [[36, 9], [62, 8], [50, 94], [94, 36], [6, 44], [31, 58], [70, 63], [92, 90], [8, 92]]},
  account: {hero: {src: doodle('sal'), x: 52, y: 55, size: 40}, around: [
    {src: doodle('folders'), x: 19, y: 19, size: 14, turn: -8}, {src: doodle('briefcase'), x: 77, y: 16, size: 13, turn: 8},
    {src: doodle('headset'), x: 88, y: 55, size: 11, turn: -6}, {src: doodle('coffee'), x: 15, y: 64, size: 12, turn: 6},
    {src: doodle('desk'), x: 76, y: 87, size: 13, turn: -3}, {src: doodle('plant'), x: 26, y: 90, size: 10, turn: 4}],
    trail: [3, 0, 1, 2], sparks: [[46, 9], [94, 30], [7, 40], [52, 94], [93, 76]]},
  reminders: {hero: {src: doodle('clock'), x: 49, y: 49, size: 29, turn: -4}, around: [
    {src: doodle('bell'), x: 20, y: 21, size: 15, turn: -10}, {src: doodle('mailbox'), x: 78, y: 18, size: 13, turn: 8},
    {src: doodle('coffee'), x: 88, y: 56, size: 10, turn: -6}, {src: doodle('plant'), x: 17, y: 70, size: 13, turn: 4},
    {src: doodle('newspaper'), x: 72, y: 86, size: 12, turn: -5}, {src: doodle('pencil'), x: 36, y: 90, size: 9, turn: 16}],
    trail: [3, 0, 1, 2], sparks: [[46, 10], [94, 32], [7, 46], [56, 94], [92, 90]]},
  money: {hero: {src: doodle('safe'), x: 50, y: 50, size: 30, turn: -3}, around: [
    {src: art('money/cash-usdc.png'), x: 22, y: 24, size: 9, turn: -8, coin: true}, {src: art('money/cash-sol.png'), x: 76, y: 17, size: 8, turn: 10, coin: true},
    {src: doodle('balance'), x: 86, y: 54, size: 13, turn: -6}, {src: doodle('calculator'), x: 17, y: 69, size: 13, turn: 6},
    {src: doodle('briefcase'), x: 72, y: 86, size: 12, turn: -4}, {src: doodle('reports'), x: 36, y: 90, size: 10, turn: 5}],
    trail: [3, 0, 1, 2], sparks: [[46, 10], [94, 30], [8, 44], [56, 94], [92, 90]]},
  preserved: {hero: {src: doodle('desk'), x: 50, y: 50, size: 32}, around: [
    {src: doodle('folders'), x: 20, y: 21, size: 14, turn: -8}, {src: doodle('plant'), x: 78, y: 18, size: 12, turn: 6},
    {src: doodle('clock'), x: 88, y: 56, size: 10, turn: 6}, {src: doodle('coffee'), x: 16, y: 69, size: 12, turn: -6},
    {src: doodle('reports'), x: 72, y: 86, size: 13, turn: 6}, {src: doodle('headset'), x: 34, y: 90, size: 10, turn: -4}],
    trail: [3, 0, 1, 2], sparks: [[46, 10], [94, 32], [7, 44], [56, 94], [92, 90]]},
};

/**
 * A pen line wandering through the given pieces: each leg sways, and every
 * other leg makes a small loop halfway, the way a doodle does.
 */
function trail(points: readonly Piece[]): string {
  const n = (v: number) => Math.round(v * 10) / 10;
  let path = `M ${points[0]!.x} ${points[0]!.y}`;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1]!, b = points[i]!;
    const length = Math.hypot(b.x - a.x, b.y - a.y) || 1;
    const dx = (b.x - a.x) / length, dy = (b.y - a.y) / length;
    const side = i % 2 ? 1 : -1, nx = -dy * side, ny = dx * side;
    const mx = (a.x + b.x) / 2 + nx * length * 0.12, my = (a.y + b.y) / 2 + ny * length * 0.12;
    if (i % 2) {
      const r = 3.2;
      path += ` Q ${n(a.x + (mx - a.x) * 0.5 + nx * 3)} ${n(a.y + (my - a.y) * 0.5 + ny * 3)} ${n(mx)} ${n(my)}`;
      path += ` C ${n(mx + dx * r * 1.8 + nx * r * 2.2)} ${n(my + dy * r * 1.8 + ny * r * 2.2)} ${n(mx - dx * r * 1.8 + nx * r * 2.2)} ${n(my - dy * r * 1.8 + ny * r * 2.2)} ${n(mx)} ${n(my)}`;
      path += ` Q ${n(b.x + (mx - b.x) * 0.5 + nx * 3)} ${n(b.y + (my - b.y) * 0.5 + ny * 3)} ${b.x} ${b.y}`;
    } else path += ` Q ${n(mx)} ${n(my)} ${b.x} ${b.y}`;
  }
  return path;
}
const spark = 'M0 -10 C1 -2 2 -1 10 0 C2 1 1 2 0 10 C-1 2 -2 1 -10 0 C-2 -1 -1 -2 0 -10 Z';

export function EntryDoodle({scene, motion}: {scene: DoodleScene; motion: boolean}) {
  const {hero, around, sparks, trail: route} = scenes[scene];
  const piece = (item: Piece, index: number, isHero = false) => <img key={`${item.src}:${index}`} src={item.src} alt="" decoding="async"
    className={`entry-doodle-piece${isHero ? ' hero' : ''}${item.coin ? ' coin' : ''}`}
    style={{'--x': `${item.x}%`, '--y': `${item.y}%`, '--size': item.size, '--turn': `${item.turn ?? 0}deg`, '--i': index} as CSSProperties}/>;
  return <div key={scene} className="entry-doodle" data-scene={scene} data-motion={motion} aria-hidden="true"
    style={{'--hx': `${hero.x}%`, '--hy': `${hero.y}%`} as CSSProperties}>
    <svg className="entry-doodle-ink" viewBox="0 0 100 100" preserveAspectRatio="none">
      <path className="trail" d={trail(route.map(index => around[index]!))}/>
    </svg>
    {sparks.map(([x, y], index) => <svg key={`${x}:${y}`} className={`entry-doodle-spark tone-${index % 3}`} viewBox="-11 -11 22 22"
      style={{'--x': `${x}%`, '--y': `${y}%`, '--i': index} as CSSProperties}><path d={spark}/></svg>)}
    {piece(hero, 0, true)}
    {around.map((item, index) => piece(item, index + 1))}
  </div>;
}
