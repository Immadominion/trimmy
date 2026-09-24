export const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);

/** Soft start, soft stop, for fades that sit inside a move that is already eased. */
export const smoothstep = (t: number) => t * t * (3 - 2 * t);

/**
 * A CSS style cubic-bezier as a function of time, solved for x the way a browser
 * does: Newton's method, with bisection when the slope is too flat to trust.
 */
export function cubicBezier(x1: number, y1: number, x2: number, y2: number) {
  const cx = 3 * x1;
  const bx = 3 * (x2 - x1) - cx;
  const ax = 1 - cx - bx;
  const cy = 3 * y1;
  const by = 3 * (y2 - y1) - cy;
  const ay = 1 - cy - by;

  const sampleX = (t: number) => ((ax * t + bx) * t + cx) * t;
  const sampleY = (t: number) => ((ay * t + by) * t + cy) * t;
  const slopeX = (t: number) => (3 * ax * t + 2 * bx) * t + cx;

  const solveX = (x: number) => {
    let t = x;
    for (let i = 0; i < 8; i++) {
      const error = sampleX(t) - x;
      if (Math.abs(error) < 1e-6) return t;
      const slope = slopeX(t);
      if (Math.abs(slope) < 1e-6) break;
      t -= error / slope;
    }
    let lo = 0;
    let hi = 1;
    t = x;
    while (hi - lo > 1e-6) {
      const value = sampleX(t);
      if (Math.abs(value - x) < 1e-6) return t;
      if (x > value) lo = t;
      else hi = t;
      t = (lo + hi) / 2;
    }
    return t;
  };

  return (x: number) => (x <= 0 ? 0 : x >= 1 ? 1 : sampleY(solveX(x)));
}

/** After Effects' Easy Ease: 33% influence on both keyframes. */
export const easyEase = cubicBezier(0.33, 0, 0.67, 1);
