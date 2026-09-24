/**
 * Plays rendered Blender sequences (the buildings rising, the camera tilting
 * down to the street, the modern street lifting away) as frames drawn on one
 * canvas, one frame per scroll position.
 *
 * Each sequence fetches its compressed frames up front, coarse ones first so a
 * fast scroll always has something close to show, and decodes off the main
 * thread only around where the scroll is. A sequence that is not on screen lets
 * its decoded frames go. The last frame can be replaced by a sharper still.
 */

type Homography = number[];

export type SequenceSet = {
  dir: string;
  frames: number;
  size: [number, number];
  /** Sharper still that replaces the last frame. */
  final?: string;
  finalSize?: [number, number];
  /** Tilt: one sky homography per frame. Peel: one for the whole sequence. */
  sky?: Homography[] | Homography;
  /** Tilt: the bond's bounding box per frame, normalised to the frame, or null. */
  bond?: ([number, number, number, number] | null)[];
  /** Whip: the first frame rendered in Blender, after the 2D whip out of 1792. */
  cut?: number;
  /** Market: calm area for the large line, normalised to the frame. */
  textArea?: [number, number, number, number];
};

export type RiseSet = {
  frames: number;
  size: [number, number];
  hero: string;
  heroSize: [number, number];
  sky: string;
  skySize?: [number, number];
  /** Wider sky from the hero pose, drawn over this box of the hero frame. */
  skyBox?: [number, number, number, number];
  sequences?: { tilt?: SequenceSet; peel?: SequenceSet; whip?: SequenceSet; market?: SequenceSet };
};

export type RiseManifest = { desktop: RiseSet; portrait: RiseSet };

const KEEP = 12;
const AHEAD = 3;
const DECODING = 3;
const FETCHING = 3;

const frameName = (index: number) => `frame-${String(index).padStart(3, "0")}.webp`;

export class FrameSequence {
  readonly frames: number;
  private readonly blobs: (Blob | null)[];
  private readonly bitmaps = new Map<number, ImageBitmap>();
  private readonly pending = new Set<number>();
  private finalBitmap: ImageBitmap | null = null;
  private readonly abort = new AbortController();
  private target = 0;
  private disposed = false;
  private started = false;
  /** Resolves once every frame has been tried at the coarsest step. */
  readonly coarse: Promise<void>;
  private coarseDone!: () => void;

  constructor(private readonly base: string, frames: number, private readonly final?: string) {
    this.frames = frames;
    this.blobs = new Array(frames).fill(null);
    this.coarse = new Promise((resolve) => { this.coarseDone = resolve; });
  }

  /** Begin fetching. Safe to call more than once. */
  start() {
    if (this.started || this.disposed) return;
    this.started = true;
    void this.load();
  }

  /** The best decoded image for `progress` (0..1), or null if none is ready yet. */
  pick(progress: number): ImageBitmap | null {
    this.start();
    const last = this.frames - 1;
    const target = Math.round(Math.min(1, Math.max(0, progress)) * last);
    this.target = target;
    if (target >= last && this.finalBitmap) return this.finalBitmap;
    this.want(target);
    let best: ImageBitmap | null = null;
    let distance = Infinity;
    for (const [index, bitmap] of this.bitmaps) {
      const d = Math.abs(index - target);
      if (d < distance) { best = bitmap; distance = d; }
    }
    return best ?? (target >= last - 1 ? this.finalBitmap : null);
  }

  /** Let decoded frames go while the sequence is off screen; keep its ends. */
  rest() {
    for (const [index, bitmap] of this.bitmaps) {
      if (index === 0 || index === this.frames - 1) continue;
      bitmap.close();
      this.bitmaps.delete(index);
    }
  }

  dispose() {
    this.disposed = true;
    this.abort.abort();
    for (const bitmap of this.bitmaps.values()) bitmap.close();
    this.bitmaps.clear();
    this.finalBitmap?.close();
    this.finalBitmap = null;
    this.coarseDone();
  }

  private want(target: number) {
    for (let step = 0; step <= AHEAD && this.pending.size < DECODING; step++) {
      for (const index of step ? [target + step, target - step] : [target]) {
        if (index < 0 || index >= this.frames || this.pending.size >= DECODING) continue;
        const blob = this.blobs[index];
        if (!blob || this.bitmaps.has(index) || this.pending.has(index)) continue;
        this.pending.add(index);
        createImageBitmap(blob).then((bitmap) => {
          this.pending.delete(index);
          if (this.disposed) { bitmap.close(); return; }
          this.bitmaps.set(index, bitmap);
          this.evict();
        }, () => this.pending.delete(index));
      }
    }
  }

  private evict() {
    while (this.bitmaps.size > KEEP) {
      let far = -1;
      let distance = -1;
      for (const index of this.bitmaps.keys()) {
        const d = Math.abs(index - this.target);
        if (d > distance) { far = index; distance = d; }
      }
      if (far < 0) return;
      this.bitmaps.get(far)!.close();
      this.bitmaps.delete(far);
    }
  }

  private async fetchBlob(file: string) {
    const response = await fetch(`${this.base}/${file}`, { signal: this.abort.signal });
    if (!response.ok) throw new Error(`${file}: ${response.status}`);
    return response.blob();
  }

  private async load() {
    const { frames } = this;
    const order: number[] = [];
    const seen = new Set<number>();
    const coarseCount = Math.ceil(frames / 8) + 1;
    for (const step of [8, 4, 2, 1]) {
      for (let i = 0; i < frames; i += step) if (!seen.has(i)) { seen.add(i); order.push(i); }
      if (step === 8 && !seen.has(frames - 1)) { seen.add(frames - 1); order.push(frames - 1); }
    }
    let next = 0;
    let finished = 0;
    let finalStarted = false;
    const worker = async () => {
      while (!this.disposed && next < order.length) {
        const index = order[next++]!;
        try { this.blobs[index] = await this.fetchBlob(frameName(index)); } catch { if (this.disposed) return; }
        if (++finished === coarseCount) this.coarseDone();
        if (!finalStarted && this.final && finished >= coarseCount) {
          finalStarted = true;
          this.fetchBlob(this.final).then((blob) => createImageBitmap(blob)).then((bitmap) => {
            if (this.disposed) { bitmap.close(); return; }
            this.finalBitmap = bitmap;
          }).catch(() => undefined);
        }
      }
    };
    await Promise.all(Array.from({ length: FETCHING }, worker));
    this.coarseDone();
  }
}

/** Draws whichever image is current onto the canvas, only when it changes. */
export class FrameCanvas {
  private readonly ctx: CanvasRenderingContext2D | null;
  private drawn: ImageBitmap | null | undefined = undefined;

  constructor(private readonly canvas: HTMLCanvasElement) {
    this.ctx = canvas.getContext("2d");
  }

  resize(width: number, height: number) {
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width;
      this.canvas.height = height;
    }
    this.drawn = undefined;
  }

  show(image: ImageBitmap | null) {
    if (!this.ctx || image === this.drawn) return;
    this.ctx.imageSmoothingQuality = "high";
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    if (image) this.ctx.drawImage(image, 0, 0, this.canvas.width, this.canvas.height);
    this.drawn = image;
  }
}

export function multiply(a: number[], b: number[]) {
  const out = new Array(9).fill(0);
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) {
    let sum = 0;
    for (let k = 0; k < 3; k++) sum += a[r * 3 + k]! * b[k * 3 + c]!;
    out[r * 3 + c] = sum;
  }
  return out;
}

export function invert(m: number[]) {
  const [a, b, c, d, e, f, g, h, i] = m as [number, number, number, number, number, number, number, number, number];
  const A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
  const det = a * A + b * B + c * C;
  return [A, -(b * i - c * h), b * f - c * e, B, a * i - c * g, -(a * f - c * d), C, -(a * h - b * g), a * e - b * d].map((v) => v / det);
}

export const IDENTITY: Homography = [1, 0, 0, 0, 1, 0, 0, 0, 1];
