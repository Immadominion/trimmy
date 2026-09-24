import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { MeshoptDecoder } from "three/addons/libs/meshopt_decoder.module.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { type WorldRoute } from "./route";
import { frameStory } from "./shots";
import { makeStoryProps } from "./storyProps";
import { disposeScene, makeDust, makeSky, makeTicker } from "./atmosphere";

type WorldState = "loading" | "ready" | "fallback";
type EraMesh = { object: THREE.Mesh; materials: THREE.Material[]; era: "modern" | "historic" | "wall" };
export type WorldEngine = {
  update(position: number, time: number, reduced: boolean, pointer: { x: number; y: number }): void;
  dispose(): void;
};
const clamp = (x: number) => Math.max(0, Math.min(1, x));
const ease = (x: number) => { const k = clamp(x); return k * k * (3 - 2 * k); };

// glTF splits multi-material objects into child meshes; classification belongs to the source node.
function sceneGroup(object: THREE.Object3D): string {
  for (let node: THREE.Object3D | null = object; node; node = node.parent) {
    const group: unknown = node.userData.scene_group;
    if (typeof group === "string" && group) return group;
    if (/^(ERA_PALISADE|HISTORIC|MODERN_STATIC|INTERIOR_STATIC|FLAG_|CROWD_)/.test(node.name)) return node.name;
  }
  return object.name;
}

export function createWorld(host: HTMLElement, onState: (state: WorldState) => void): WorldEngine {
  let disposed = false;
  let ready = false;
  let route: WorldRoute | null = null;
  let previousTime = 0;
  let lastPosition = -10;
  let lastRender = 0;
  let frameCount = 0;
  let measuredFrames = 0;
  let lastShadowSignature = "";
  const modelLoads: Promise<void>[] = [];
  let measuredAt = 0;
  let cachedWidth = 1;
  let cachedHeight = 1;
  const mobile = window.matchMedia("(max-width: 700px)").matches;
  let pixelRatio = Math.min(window.devicePixelRatio || 1, mobile ? 1.25 : 1.5);
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: "high-performance" });
  renderer.setPixelRatio(pixelRatio);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.2;
  renderer.shadowMap.enabled = !mobile;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  renderer.shadowMap.autoUpdate = false;
  renderer.shadowMap.needsUpdate = true;
  host.appendChild(renderer.domElement);
  const scene = new THREE.Scene();
  scene.background = new THREE.Color("#182433");
  const fog = new THREE.FogExp2("#283849", .011);
  scene.fog = fog;
  const sky = makeSky(); scene.add(sky);

  const environmentScene = new RoomEnvironment();
  const pmrem = new THREE.PMREMGenerator(renderer);
  const environment = pmrem.fromScene(environmentScene, .035);
  scene.environment = environment.texture;
  scene.environmentIntensity = .36;
  environmentScene.dispose(); pmrem.dispose();
  renderer.info.autoReset = false;

  const ambient = new THREE.HemisphereLight("#becedf", "#3f3020", 1.45);
  scene.add(ambient);
  const key = new THREE.DirectionalLight("#ffe0b4", 3.0);
  key.position.set(24, 54, -24);
  key.target.position.set(-7, 0, 22);
  key.castShadow = !mobile;
  key.shadow.mapSize.set(2048, 2048);
  Object.assign(key.shadow.camera, { left: -70, right: 70, top: 65, bottom: -65, near: .5, far: 160 });
  key.shadow.bias = -.00025;
  key.shadow.normalBias = .08;
  scene.add(key, key.target);
  const rim = new THREE.DirectionalLight("#7595b7", .85);
  rim.position.set(-25, 20, 65); scene.add(rim);
  // Room luminaires stay in world space as the camera crosses the threshold.
  const floorLight = new THREE.PointLight("#ffe1b9", 150, 35, 2);
  floorLight.position.set(-21, 7.5, 40); scene.add(floorLight);
  const floorFill = new THREE.PointLight("#bddde5", 90, 26, 2);
  floorFill.position.set(-10, 4.5, 39); scene.add(floorFill);

  const camera = new THREE.PerspectiveCamera(48, 1, .12, 230);
  const target = new THREE.Vector3();
  const pointerSmooth = new THREE.Vector2();
  const composer = new EffectComposer(renderer);
  const samples = Math.min(renderer.capabilities.maxSamples, mobile ? 2 : 4);
  composer.renderTarget1.samples = samples;
  composer.renderTarget2.samples = samples;
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(512, 512), .27, .58, 1.25);
  composer.addPass(bloom);
  composer.addPass(new OutputPass());
  const dust = makeDust(); scene.add(dust.object);
  const props = makeStoryProps(); scene.add(props.object);
  const ticker = makeTicker(); scene.add(ticker.object); ticker.object.visible = false;
  const eras: EraMesh[] = [];
  const groundMaterials: THREE.MeshStandardMaterial[] = [];
  const flags: { time: { value: number } }[] = [];
  let bull: THREE.Object3D | null = null;
  const storyModels: { object: THREE.Object3D; start: number; end: number }[] = [];
  const loader = new GLTFLoader();
  loader.setMeshoptDecoder(MeshoptDecoder);
  const abort = new AbortController();

  function resize() {
    cachedWidth = Math.max(1, host.clientWidth);
    cachedHeight = Math.max(1, host.clientHeight);
    const aspect = cachedWidth / cachedHeight;
    camera.aspect = aspect;
    camera.fov = aspect < .8 ? 65 : 48;
    camera.updateProjectionMatrix();
    renderer.setSize(cachedWidth, cachedHeight);
    composer.setSize(cachedWidth, cachedHeight);
    dust.material.uniforms.ratio!.value = pixelRatio;
    lastPosition = -10;
  }
  const observer = new ResizeObserver(resize); observer.observe(host); resize();
  const onLost = (event: Event) => { event.preventDefault(); ready = false; onState("fallback"); };
  const onRestored = () => { if (!disposed) { ready = !!route; onState(ready ? "ready" : "fallback"); lastPosition = -10; } };
  renderer.domElement.addEventListener("webglcontextlost", onLost);
  renderer.domElement.addEventListener("webglcontextrestored", onRestored);

  const json = async <T,>(path: string): Promise<T> => {
    const response = await fetch(path, { signal: abort.signal });
    if (!response.ok || !response.headers.get("content-type")?.includes("json")) throw new Error("World data unavailable");
    return await response.json() as T;
  };

  Promise.all([loader.loadAsync("/world/wall-street.glb"), json<WorldRoute>("/world/route.json")]).then(async ([gltf, data]) => {
    if (disposed) { disposeScene(gltf.scene); return; }
    if (data.waypoints.length < 2) throw new Error("Invalid camera route");
    route = data;
    gltf.scene.traverse((object) => {
      if (object instanceof THREE.Light) object.visible = false;
      if (!(object instanceof THREE.Mesh)) return;
      object.castShadow = true; object.receiveShadow = true;
      const originalMaterials = Array.isArray(object.material) ? object.material : [object.material];
      for (const mat of originalMaterials) {
        if (mat instanceof THREE.MeshStandardMaterial) {
          mat.envMapIntensity = /bronze|metal|glass/i.test(mat.name) ? .85 : .4;
          if (/Street.*granite/i.test(mat.name)) { mat.roughness = .48; mat.metalness = .16; }
          if (mat.map) mat.map.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
        }
      }
      const name = sceneGroup(object);
      // The old blockout houses distracted from the surviving historical evidence.
      // Keep them in the editable source, but use the reconstructed wall and artifacts here.
      if (/^(HISTORIC_HOUSES|CROWD_)/.test(name)) { object.visible = false; return; }
      const era = name.startsWith("ERA_PALISADE") ? "wall" : name.startsWith("HISTORIC") ? "historic" : /^(MODERN_STATIC|INTERIOR_STATIC|FLAG_|CROWD_)/.test(name) ? "modern" : null;
      if (name.startsWith("WORLD_GROUND")) {
        const materials = originalMaterials.map((mat) => {
          const copy = mat.clone();
          if (copy instanceof THREE.MeshStandardMaterial) groundMaterials.push(copy);
          return copy;
        });
        object.material = Array.isArray(object.material) ? materials : materials[0]!;
      }
      if (era) {
        const materials = originalMaterials.map((mat: THREE.Material) => { const m = mat.clone(); m.alphaHash = true; return m; });
        object.material = Array.isArray(object.material) ? materials : materials[0]!;
        eras.push({ object, materials, era });
      }
      if (name.startsWith("FLAG_")) {
        // The wind shader deforms local vertices, so an undeformed shadow would detach from the cloth.
        object.castShadow = false;
        const materials = Array.isArray(object.material) ? object.material : [object.material];
        for (const mat of materials) {
          const time = { value: 0 }; flags.push({ time });
          mat.side = THREE.DoubleSide;
          mat.onBeforeCompile = (shader: Parameters<THREE.Material["onBeforeCompile"]>[0]) => {
            shader.uniforms.windTime = time;
            shader.vertexShader = "uniform float windTime;\n" + shader.vertexShader;
            shader.vertexShader = shader.vertexShader.replace("#include <begin_vertex>", "#include <begin_vertex>\n float clothU = clamp(position.z / 2.3, 0.0, 1.0); transformed.x += sin(position.z * 3.1 + windTime * 1.15) * .11 * clothU; transformed.y += sin(position.z * 4.7 + windTime * 1.7) * .045 * clothU;");
          };
          mat.customProgramCacheKey = () => "trimmy-cloth-v2";
        }
      }
    });
    scene.add(gltf.scene);
    await Promise.all(modelLoads);
    if (disposed) return;
    camera.position.fromArray(data.waypoints[0]!.position);
    camera.lookAt(new THREE.Vector3(...data.waypoints[0]!.lookAt));
    // Compile, upload and shadow everything now, behind the opening. Models
    // that start hidden would otherwise do all of this on the first frame they
    // appear, which stalls the scroll. Lights stay as they are: their count is
    // part of every shader.
    const hidden: THREE.Object3D[] = [];
    scene.traverse((object) => {
      if (!object.visible && !(object instanceof THREE.Light)) { hidden.push(object); object.visible = true; }
    });
    await renderer.compileAsync(scene, camera);
    if (disposed) return;
    scene.traverse((object) => {
      if (!(object instanceof THREE.Mesh)) return;
      for (const mat of Array.isArray(object.material) ? object.material : [object.material]) {
        for (const value of Object.values(mat)) if (value instanceof THREE.Texture) renderer.initTexture(value);
      }
    });
    renderer.shadowMap.needsUpdate = true;
    composer.render();
    for (const object of hidden) object.visible = false;
    renderer.shadowMap.needsUpdate = true;
    ready = true;
    host.dataset.modelLoaded = "true";
    onState("ready");
    lastPosition = -10;
  }).catch((error: unknown) => {
    if (!disposed && !(error instanceof DOMException && error.name === "AbortError")) {
      console.warn("Trimmy world assets failed to load", error);
      onState("fallback");
    }
  });

  modelLoads.push(json<{ lights?: { position: [number, number, number]; color?: string; intensity?: number; distance?: number }[] }>("/world/scene-manifest.json").then((manifest) => {
    if (disposed) return;
    // Four nearby practical lights at a time are enough; emissive geometry carries the distant ones.
    const selected = (manifest.lights || []).filter((_, i) => i % 3 === 0).slice(0, 5);
    selected.forEach((source) => { const light = new THREE.PointLight(source.color || "#ffd39a", source.intensity ?? 23, source.distance ?? 15, 2); light.position.fromArray(source.position); scene.add(light); });
    lastPosition = -10;
  }).catch((error: unknown) => {
    if (!disposed && !(error instanceof DOMException && error.name === "AbortError")) console.warn("Trimmy world lighting metadata failed to load", error);
  }));

  modelLoads.push(loader.loadAsync("/world/bull.glb").then((gltf) => {
    if (disposed) { disposeScene(gltf.scene); return; }
    bull = gltf.scene;
    bull.position.set(5.8, .275, 19);
    bull.rotation.y = Math.PI;
    bull.traverse((object) => {
      if (!(object instanceof THREE.Mesh)) return;
      object.castShadow = true; object.receiveShadow = true;
      const mats = Array.isArray(object.material) ? object.material : [object.material];
      mats.forEach((mat: THREE.Material) => { if (mat instanceof THREE.MeshStandardMaterial) mat.envMapIntensity = 1.25; });
    });
    scene.add(bull);
    lastPosition = -10;
  }).catch((error: unknown) => {
    if (!disposed) console.warn("Trimmy bull asset failed to load", error);
  }));

  const loadStoryModel = (file: string, position: [number, number, number], start: number, end: number, copies?: [number, number, number][]) => {
    const loading = loader.loadAsync(`/world/${file}`).then((gltf) => {
      if (disposed) { disposeScene(gltf.scene); return; }
      gltf.scene.traverse((node) => {
        if (!(node instanceof THREE.Mesh)) return;
        node.castShadow = true; node.receiveShadow = true;
        const materials = Array.isArray(node.material) ? node.material : [node.material];
        for (const mat of materials) if (mat instanceof THREE.MeshStandardMaterial) {
          mat.envMapIntensity = /glass|brass|bronze|metal/i.test(mat.name) ? 1.1 : .65;
          if (mat.map) mat.map.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
        }
      });
      for (const at of [position, ...(copies || [])]) {
        const model = at === position ? gltf.scene : gltf.scene.clone(true);
        model.position.set(...at); model.visible = false;
        scene.add(model); storyModels.push({ object: model, start, end });
      }
      renderer.shadowMap.needsUpdate = true; lastPosition = -10;
    }).catch((error: unknown) => { if (!disposed) console.warn(`Trimmy ${file} failed to load`, error); });
    modelLoads.push(loading);
  };
  loadStoryModel("ledger.glb", [-27.2, 1, 1.6], 2.1, 4.35);
  loadStoryModel("ticker.glb", [-2, 1.15, 35.5], 5.15, 7.15);
  loadStoryModel("trading-post.glb", [-24, .10, 33], 4.65, 9, [[-30, .10, 47], [-18, .10, 51]]);

  return {
    update(pagePosition, time, reduced, pointer) {
      if (disposed || !ready || !route || document.hidden) return;
      // The stage is hidden until 5.84 (after the opening's market line); render just before it shows.
      if (pagePosition < 5.7 || pagePosition >= 9) return;
      const p = reduced ? Math.round(pagePosition) : pagePosition;
      const stationary = Math.abs(p - lastPosition) < .00001;
      if (reduced && stationary) return;
      // Keep subtle life between gestures; mobile idle rendering uses half-rate.
      if (mobile && stationary && time - lastRender < 32) return;
      const dt = previousTime ? Math.min(.1, (time - previousTime) / 1000) : 1 / 60;
      previousTime = time; lastRender = time;
      frameStory(camera, target, route, p);
      props.update(p);
      storyModels.forEach(({ object, start, end }) => { object.visible = p > start && p < end; });
      const pointerEase = 1 - Math.exp(-dt * 3);
      pointerSmooth.lerp(new THREE.Vector2(reduced ? 0 : pointer.x, reduced ? 0 : pointer.y), pointerEase);
      camera.lookAt(target);
      if (!reduced) { camera.rotateY(-pointerSmooth.x * .013); camera.rotateX(-pointerSmooth.y * .009); }
      const modern = ease((p - 4.15) / .75);
      const historic = (1 - ease((p - 4.2) / .7));
      const wall = 1 - ease((p - 2.12) / .65);
      eras.forEach(({ object, materials, era }) => {
        const opacity = era === "modern" ? modern : era === "wall" ? wall : historic;
        object.visible = opacity > .005;
        materials.forEach((mat) => { mat.opacity = opacity; });
      });
      if (bull) bull.visible = modern > .5;
      const inside = ease((p - 6.25) / .75);
      fog.density = .010 + (1 - modern) * .027 - inside * .007;
      fog.color.set("#070a0d").lerp(new THREE.Color(inside > .5 ? "#141923" : "#283849"), modern);
      sky.material.uniforms.top!.value.set("#020304").lerp(new THREE.Color("#18253b"), modern);
      sky.material.uniforms.bottom!.value.set("#080c10").lerp(new THREE.Color("#77818a"), modern);
      groundMaterials.forEach((mat) => { mat.color.set("#16191b").lerp(new THREE.Color("#ffffff"), modern); });
      scene.environmentIntensity = .35 + inside * .12;
      ambient.intensity = .88 + modern * .24 - inside * .18;
      renderer.toneMappingExposure = 1.14 + inside * .12;
      ticker.object.visible = p > 5.45 && p < 6.8;
      ticker.material.opacity = ease((p - 5.4) / .45) * (1 - ease((p - 6.7) / .4)) * .8;
      ticker.texture.offset.x = reduced ? 0 : time * .000012;
      flags.forEach(({ time: uniform }) => { uniform.value = reduced ? 0 : time / 1000; });
      dust.object.visible = !reduced;
      dust.material.uniforms.time!.value = time / 1000;
      dust.material.uniforms.strength!.value = .24 + inside * .18;
      // A moving camera does not change world-space shadows. Recompute only on era/prop visibility changes,
      // in tenths during a fade: a full shadow pass every frame of a fade stalls the scroll.
      const shadowSignature = `${modern.toFixed(1)}:${historic.toFixed(1)}:${wall.toFixed(1)}:${storyModels.map(({ object }) => +object.visible).join("")}`;
      if (shadowSignature !== lastShadowSignature) { renderer.shadowMap.needsUpdate = true; lastShadowSignature = shadowSignature; }
      renderer.info.reset();
      composer.render(dt);
      lastPosition = p;
      frameCount++;
      if (time - measuredAt > 1500) {
        host.dataset.drawCalls = String(renderer.info.render.calls);
        host.dataset.frames = String(frameCount);
        host.dataset.fps = String(Math.round((frameCount - measuredFrames) * 1000 / (time - measuredAt)));
        measuredFrames = frameCount;
        host.dataset.camera = camera.position.toArray().map((v) => v.toFixed(2)).join(",");
        measuredAt = time;
      }
    },
    dispose() {
      disposed = true; abort.abort(); observer.disconnect();
      renderer.domElement.removeEventListener("webglcontextlost", onLost);
      renderer.domElement.removeEventListener("webglcontextrestored", onRestored);
      disposeScene(scene); environment.dispose();
      bloom.dispose(); composer.passes.forEach((pass) => { if (pass !== bloom) pass.dispose(); }); composer.dispose();
      renderer.dispose(); renderer.domElement.remove();
    },
  };
}
