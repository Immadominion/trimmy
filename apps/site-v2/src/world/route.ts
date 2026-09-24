export type Point3 = [number, number, number];
export type RoutePoint = { progress: number; position: Point3; lookAt: Point3 };
export type WorldRoute = { waypoints: RoutePoint[]; camera: { near: number; far: number; fovVerticalDegrees: number } };

// Narrative stops follow one distance-parameterized route. Intermediate samples
// preserve both street corners; a spline through chapter stops would cut walls.
const STOPS = [0, 0, 0, .13, .255, .48, .70, .865, .955, 1];
export function routeProgress(pagePosition: number) {
  const p = Math.max(0, Math.min(STOPS.length - 1, pagePosition));
  const i = Math.floor(p);
  const a = STOPS[i]!;
  const b = STOPS[Math.min(i + 1, STOPS.length - 1)]!;
  return a + (b - a) * (p - i);
}

export function sampleRoute(route: WorldRoute, progress: number) {
  let lo = 0, hi = route.waypoints.length - 1;
  while (lo < hi - 1) {
    const mid = Math.floor((lo + hi) / 2);
    if (route.waypoints[mid]!.progress < progress) lo = mid;
    else hi = mid;
  }
  const a = route.waypoints[lo]!, b = route.waypoints[hi]!;
  const t = Math.max(0, Math.min(1, (progress - a.progress) / (b.progress - a.progress || 1)));
  const lerp = (a: Point3, b: Point3): Point3 => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  return { position: lerp(a.position, b.position), lookAt: lerp(a.lookAt, b.lookAt) };
}
