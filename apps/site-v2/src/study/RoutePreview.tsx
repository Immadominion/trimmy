import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";

type Point = [number, number, number];
type Sample = { progress: number; position: Point; lookAt: Point };
type Stop = Sample & { id: string; title: string };
type Route = {
  stops: Stop[];
  waypoints: Sample[];
  camera: { fovVerticalDegrees: number; near: number; far: number };
};

function sampleRoute(route: Route, progress: number) {
  const points = route.waypoints;
  let low = 0;
  let high = points.length - 1;
  while (low < high - 1) {
    const mid = Math.floor((low + high) / 2);
    if (points[mid]!.progress <= progress) low = mid;
    else high = mid;
  }
  const a = points[low]!;
  const b = points[high]!;
  const t = Math.max(0, Math.min(1, (progress - a.progress) / (b.progress - a.progress || 1)));
  const mix = (x: Point, y: Point): Point => [x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t];
  return { position: mix(a.position, b.position), lookAt: mix(a.lookAt, b.lookAt) };
}

function disposeWorld(object: THREE.Object3D) {
  const geometries = new Set<THREE.BufferGeometry>();
  const materials = new Set<THREE.Material>();
  object.traverse((node) => {
    if (node instanceof THREE.Mesh || node instanceof THREE.Line) {
      geometries.add(node.geometry);
      (Array.isArray(node.material) ? node.material : [node.material]).forEach((m: THREE.Material) => materials.add(m));
    }
  });
  geometries.forEach((g) => g.dispose());
  materials.forEach((m) => m.dispose());
}

export default function RoutePreview() {
  const host = useRef<HTMLDivElement>(null);
  const progressRef = useRef(0);
  const playingRef = useRef(false);
  const overheadRef = useRef(false);
  const dirty = useRef(true);
  const [route, setRoute] = useState<Route | null>(null);
  const [progress, setProgress] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [overhead, setOverhead] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const container = host.current!;
    let disposed = false;
    let renderer: THREE.WebGLRenderer;
    try { renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: "low-power" }); }
    catch { setError("This browser could not open the 3D view. The look and story views are still available."); return; }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    container.appendChild(renderer.domElement);
    renderer.domElement.setAttribute("aria-label", "Continuous 3D camera study of the street, two right turns, and trading floor");
    renderer.domElement.setAttribute("role", "img");

    const world = new THREE.Scene();
    world.background = new THREE.Color("#33404e");
    world.fog = new THREE.Fog("#33404e", 100, 220);
    const sky = new THREE.HemisphereLight("#c3d9f1", "#6d6556", 2.2);
    world.add(sky);
    const sun = new THREE.DirectionalLight("#ffe3bd", 2.5);
    sun.position.set(-35, 70, -40);
    world.add(sun);
    const camera = new THREE.PerspectiveCamera(58, 1, .1, 220);
    const planCamera = new THREE.OrthographicCamera(-70, 70, 50, -50, .1, 400);
    let model: THREE.Object3D | undefined;
    let routeLine: THREE.Line | undefined;
    let marker: THREE.Mesh | undefined;
    let activeRoute: Route | undefined;
    let lastTime = 0;
    let lastUpdate = 0;
    let mapHeight = 110;

    const resize = () => {
      const width = Math.max(1, container.clientWidth);
      const height = Math.max(1, container.clientHeight);
      renderer.setSize(width, height);
      const aspect = width / height;
      camera.aspect = aspect;
      // Portrait widens vertical coverage while keeping the same ground route.
      camera.fov = aspect < .85 ? 72 : activeRoute?.camera.fovVerticalDegrees ?? 58;
      camera.updateProjectionMatrix();
      planCamera.top = mapHeight / 2;
      planCamera.bottom = -mapHeight / 2;
      planCamera.left = -mapHeight * aspect / 2;
      planCamera.right = mapHeight * aspect / 2;
      planCamera.updateProjectionMatrix();
      dirty.current = true;
    };
    const observer = new ResizeObserver(resize);
    observer.observe(container);
    const onContextLost = (event: Event) => {
      event.preventDefault();
      playingRef.current = false;
      setPlaying(false);
      setError("The 3D view was interrupted. Switch to The look, then reopen The turns to reload it.");
    };
    renderer.domElement.addEventListener("webglcontextlost", onContextLost);

    Promise.all([
      fetch("/studies/wall-street/camera-route.json").then(async (response) => {
        if (!response.ok) throw new Error("Route data unavailable");
        return await response.json() as Route;
      }),
      new GLTFLoader().loadAsync("/studies/wall-street/wall-street-route.glb"),
    ]).then(([data, gltf]) => {
      if (disposed) { disposeWorld(gltf.scene); return; }
      if (data.waypoints.length < 2 || data.stops.length < 2) throw new Error("Incomplete route");
      model = gltf.scene;
      // Blender exports physical light units; this review supplies calibrated
      // browser lighting instead of adding its lights on top of the GLB sun.
      model.traverse((node) => { if (node instanceof THREE.Light) node.visible = false; });
      world.add(model);
      activeRoute = data;
      const path = data.waypoints.map((s) => new THREE.Vector3(s.position[0], .25, s.position[2]));
      routeLine = new THREE.Line(new THREE.BufferGeometry().setFromPoints(path), new THREE.LineBasicMaterial({ color: "#eec582", depthTest: false }));
      routeLine.renderOrder = 20;
      world.add(routeLine);
      marker = new THREE.Mesh(new THREE.SphereGeometry(1, 12, 8), new THREE.MeshBasicMaterial({ color: "#ffffff", depthTest: false }));
      marker.renderOrder = 21;
      world.add(marker);
      const bounds = new THREE.Box3().setFromPoints(path);
      const center = bounds.getCenter(new THREE.Vector3());
      const size = bounds.getSize(new THREE.Vector3());
      mapHeight = Math.max(size.z + 36, (size.x + 36) / Math.max(.5, container.clientWidth / container.clientHeight));
      planCamera.position.set(center.x, 160, center.z);
      planCamera.up.set(0, 0, -1);
      planCamera.lookAt(center.x, 0, center.z);
      camera.near = data.camera.near;
      camera.far = data.camera.far;
      setRoute(data);
      resize();
    }).catch(() => { if (!disposed) setError("The camera model could not load. Switch to The look, then reopen The turns to retry."); });

    renderer.setAnimationLoop((time) => {
      const dt = lastTime ? Math.min((time - lastTime) / 1000, .08) : 0;
      lastTime = time;
      if (disposed || !activeRoute || document.hidden) return;
      if (playingRef.current) {
        progressRef.current = Math.min(1, progressRef.current + dt / 44);
        dirty.current = true;
        if (time - lastUpdate > 90 || progressRef.current === 1) {
          setProgress(progressRef.current);
          lastUpdate = time;
        }
        if (progressRef.current === 1) { playingRef.current = false; setPlaying(false); }
      }
      if (!dirty.current) return;
      const sample = sampleRoute(activeRoute, progressRef.current);
      camera.position.fromArray(sample.position);
      camera.lookAt(new THREE.Vector3().fromArray(sample.lookAt));
      if (routeLine) routeLine.visible = overheadRef.current;
      if (marker) { marker.visible = overheadRef.current; marker.position.set(sample.position[0], .5, sample.position[2]); }
      renderer.render(world, overheadRef.current ? planCamera : camera);
      dirty.current = false;
    });
    resize();

    return () => {
      disposed = true;
      playingRef.current = false;
      renderer.setAnimationLoop(null);
      observer.disconnect();
      renderer.domElement.removeEventListener("webglcontextlost", onContextLost);
      disposeWorld(world);
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, []);

  const seek = (p: number) => {
    progressRef.current = p;
    setProgress(p);
    playingRef.current = false;
    setPlaying(false);
    dirty.current = true;
  };
  const togglePlay = () => {
    if (progressRef.current >= 1) seek(0);
    playingRef.current = !playingRef.current;
    setPlaying(playingRef.current);
  };
  const chooseView = (value: boolean) => { overheadRef.current = value; setOverhead(value); dirty.current = true; };
  const stopIndex = route ? route.stops.reduce((last, s, i) => s.progress <= progress + .002 ? i : last, 0) : 0;
  const stop = route?.stops[stopIndex];
  const sample = route ? sampleRoute(route, progress) : null;
  const map = route ? (() => {
    const xs = route.waypoints.map((s) => s.position[0]);
    const zs = route.waypoints.map((s) => s.position[2]);
    const minX = Math.min(...xs), minZ = Math.min(...zs);
    const width = Math.max(...xs) - minX, height = Math.max(...zs) - minZ;
    return { viewBox: `${minX - 8} ${minZ - 8} ${width + 16} ${height + 16}`, line: route.waypoints.map((s) => `${s.position[0]},${s.position[2]}`).join(" ") };
  })() : null;

  return (
    <section className="route-study" aria-label="Camera route study">
      <div className="route-viewport">
        <div className="route-canvas" ref={host} />
        <div className="route-caption"><p>One street. Two real turns.</p><span>Geometry study · materials and details are unfinished</span></div>
        {route && <>
          <div className="route-mode" aria-label="Camera view"><button type="button" aria-pressed={!overhead} onClick={() => chooseView(false)}>Street</button><button type="button" aria-pressed={overhead} onClick={() => chooseView(true)}>Overhead</button></div>
          <div className="route-current"><small>{String(stopIndex + 1).padStart(2, "0")} / 08 · camera stop</small><h1>{stop?.title}</h1></div>
          <p className="route-disclaimer">Same world. Same 1.65 m camera height.<br />No image swaps between corners.</p>
          {map && sample && <div className="route-minimap" aria-label="Camera position along the route"><svg viewBox={map.viewBox} role="img" aria-label="Two-turn path"><polyline points={map.line} fill="none" stroke="#dec299" strokeWidth="1.2" strokeLinecap="round" />{route.stops.map((s) => <circle key={s.id} cx={s.position[0]} cy={s.position[2]} r="1.6" fill="#89929e" />)}<circle cx={sample.position[0]} cy={sample.position[2]} r="2.4" fill="white" /></svg></div>}
        </>}
        {(!route || error) && <div className="route-status" role="status">{error || "Loading the camera route…"}</div>}
      </div>
      <div className="route-controls">
        <div className="route-controls-top"><button className="route-play" disabled={!route || !!error} type="button" onClick={togglePlay}>{playing ? "Pause" : progress >= 1 ? "Replay route" : "Play route"}</button><input type="range" aria-label="Camera route progress" min="0" max="1000" value={Math.round(progress * 1000)} onChange={(e) => seek(Number(e.target.value) / 1000)} disabled={!route} /><span className="route-percentage">{Math.round(progress * 100)}%</span></div>
        <nav className="route-stop-list" aria-label="Camera stops">{route?.stops.map((s, i) => <button type="button" key={s.id} aria-current={i === stopIndex ? "true" : undefined} onClick={() => seek(s.progress)}><span>{String(i + 1).padStart(2, "0")}</span>{s.title}</button>)}</nav>
      </div>
    </section>
  );
}
