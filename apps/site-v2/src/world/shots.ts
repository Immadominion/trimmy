import * as THREE from "three";
import { routeProgress, sampleRoute, type WorldRoute } from "./route";

const smooth = (n: number) => { const x = Math.max(0, Math.min(1, n)); return x * x * (3 - 2 * x); };
const entry = new THREE.CatmullRomCurve3([
  new THREE.Vector3(1.3, 2.4, 32.3), new THREE.Vector3(.1, 2.35, 35),
  new THREE.Vector3(-2.2, 2.4, 38.7), new THREE.Vector3(-7, 2.5, 40),
  new THREE.Vector3(-13.6, 3.35, 40), new THREE.Vector3(-16.5, 5.7, 41),
  new THREE.Vector3(-19, 7, 42),
], false, "centripetal");
const descent = new THREE.CatmullRomCurve3([
  new THREE.Vector3(-19, 7, 42), new THREE.Vector3(-21, 6.2, 43.2),
  new THREE.Vector3(-23.5, 4.2, 42.6), new THREE.Vector3(-25, 2.4, 40.7),
], false, "centripetal");

/** Every lens has a subject. The exterior route still supplies both real corners. */
export function frameStory(camera: THREE.PerspectiveCamera, target: THREE.Vector3, route: WorldRoute, p: number) {
  const point = sampleRoute(route, routeProgress(Math.min(p, 8.95)));
  camera.position.fromArray(point.position);
  target.fromArray(point.lookAt); target.y += .45;
  const weight = (chapter: number) => smooth(1 - Math.abs(p - chapter));
  let fov = 48;
  const focus = (chapter: number, position: [number, number, number], aim: [number, number, number], lens: number) => {
    const w = weight(chapter);
    camera.position.lerp(new THREE.Vector3(...position), w);
    target.lerp(new THREE.Vector3(...aim), w);
    fov += (lens - 48) * w;
  };
  focus(2, [-42, 3.1, -.8], [-34.8, 1.65, 5.2], 43);
  focus(3, [-29.6, 3.5, -.65], [-26.65, 1.02, 1.6], 35);
  focus(4, [-13.4, 3.1, .1], [-9.55, 1.45, 2.7], 38);
  // The approved bull composition is deliberately identical to the first build.
  target.lerp(new THREE.Vector3(5.8, 2.25, 19), weight(5) * .9);
  focus(6, [1.3, 2.4, 32.3], [-1.65, 1.45, 35.5], 34);
  if (p > 6 && p <= 7) {
    const t = p - 6;
    camera.position.copy(entry.getPoint(t));
    const turn = smooth((t - .12) / .74);
    target.set(-1.65, 1.45, 35.5).lerp(new THREE.Vector3(-26, 2.25, 35), turn);
    fov = THREE.MathUtils.lerp(34, 52, smooth(t));
  } else if (p > 7) {
    const t = Math.min(1, p - 7);
    camera.position.copy(descent.getPoint(t));
    target.set(-26, 2.25, 35).lerp(new THREE.Vector3(-30, 2.6, 46), smooth(t));
    fov = THREE.MathUtils.lerp(52, 43, smooth(t));
  }
  const adjustedFov = fov + (camera.aspect < .8 ? 17 : 0);
  if (Math.abs(camera.fov - adjustedFov) > .001) { camera.fov = adjustedFov; camera.updateProjectionMatrix(); }
}
