import * as THREE from "three";

export function makeSky() {
  const sky = new THREE.Mesh(new THREE.SphereGeometry(190, 32, 20), new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false,
    uniforms: { top: { value: new THREE.Color("#18253b") }, bottom: { value: new THREE.Color("#77818a") } },
    vertexShader: `varying vec3 vDirection; void main(){vDirection=position;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}`,
    fragmentShader: `varying vec3 vDirection; uniform vec3 top; uniform vec3 bottom; void main(){float h=normalize(vDirection).y;gl_FragColor=vec4(mix(bottom,top,smoothstep(-.07,.7,h)),1.);}`,
  }));
  sky.renderOrder = -10;
  return sky;
}

export function makeDust() {
  const count = 170;
  const positions = new Float32Array(count * 3);
  const seeds = new Float32Array(count);
  let seed = 1977;
  const random = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
  for (let i = 0; i < count; i++) {
    positions[i * 3] = -43 + random() * 57;
    positions[i * 3 + 1] = .8 + random() * 15;
    positions[i * 3 + 2] = -6 + random() * 53;
    seeds[i] = random() * 10;
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  geo.setAttribute("seed", new THREE.BufferAttribute(seeds, 1));
  const material = new THREE.ShaderMaterial({
    uniforms: { time: { value: 0 }, strength: { value: .5 }, ratio: { value: 1 } },
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: `attribute float seed; uniform float time; uniform float ratio; varying float vGlow; void main(){vec3 p=position;p.x+=sin(time*.12+seed)*.23;p.y+=sin(time*.2+seed)*.28;vec4 mv=modelViewMatrix*vec4(p,1.);gl_Position=projectionMatrix*mv;gl_PointSize=clamp(30./max(2.,-mv.z),1.,3.5)*ratio;vGlow=(.35+.65*pow(max(0.,sin(time*.4+seed)),4.))*(1.-smoothstep(5.,60.,-mv.z));}`,
    fragmentShader: `uniform float strength; varying float vGlow; void main(){float d=length(gl_PointCoord-.5);float a=exp(-d*d*22.)*vGlow*strength;gl_FragColor=vec4(1.,.82,.52,a);}`,
  });
  const object = new THREE.Points(geo, material);
  object.frustumCulled = false;
  return { object, material };
}

export function makeTicker() {
  const canvas = document.createElement("canvas");
  canvas.width = 2048; canvas.height = 128;
  const ctx = canvas.getContext("2d")!;
  ctx.fillStyle = "#c9c3ad"; ctx.fillRect(0, 0, 2048, 128);
  ctx.fillStyle = "#393c36"; ctx.font = "bold 38px monospace"; ctx.textBaseline = "middle";
  ctx.fillText("TR  104  3/4     NY  89  1/8     1792     TR  108  1/2     WS  91  7/8", 25, 68);
  ctx.strokeStyle = "#8f927b"; ctx.setLineDash([4, 7]);
  ctx.beginPath(); ctx.moveTo(0, 10); ctx.lineTo(2048, 10); ctx.moveTo(0, 117); ctx.lineTo(2048, 117); ctx.stroke();
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.wrapS = THREE.RepeatWrapping;
  texture.repeat.set(2, 1);
  const path = new THREE.CatmullRomCurve3([
    new THREE.Vector3(-2, 1.58, 35.15), new THREE.Vector3(-1.5, 1.57, 34.96),
    new THREE.Vector3(-1.18, 1.2, 34.9), new THREE.Vector3(-1.1, .7, 34.76),
    new THREE.Vector3(-.65, .23, 34.5), new THREE.Vector3(.1, .2, 34.7),
  ]);
  const geo = new THREE.PlaneGeometry(3, .075, 100, 1);
  const attr = geo.getAttribute("position");
  for (let i = 0; i < attr.count; i++) {
    const t = (attr.getX(i) + 1.5) / 3;
    const edge = attr.getY(i);
    const point = path.getPoint(t);
    const tangent = path.getTangent(t);
    const twist = .25 + Math.sin(t * 5) * .65;
    attr.setXYZ(i, point.x + tangent.z * edge * Math.sin(twist), point.y + edge * Math.cos(twist), point.z - tangent.x * edge * Math.sin(twist));
  }
  geo.computeVertexNormals();
  const material = new THREE.MeshStandardMaterial({ map: texture, color: "#e5dac0", roughness: .7, side: THREE.DoubleSide, transparent: true });
  const object = new THREE.Mesh(geo, material);
  return { object, material, texture };
}

export function disposeScene(scene: THREE.Object3D) {
  const textures = new Set<THREE.Texture>();
  const geometries = new Set<THREE.BufferGeometry>();
  const materials = new Set<THREE.Material>();
  scene.traverse((node) => {
    if (!(node instanceof THREE.Mesh || node instanceof THREE.Points || node instanceof THREE.Line)) return;
    geometries.add(node.geometry);
    (Array.isArray(node.material) ? node.material : [node.material]).forEach((mat: THREE.Material) => {
      materials.add(mat);
      for (const value of Object.values(mat)) if (value instanceof THREE.Texture) textures.add(value);
    });
  });
  textures.forEach((t) => t.dispose());
  materials.forEach((m) => m.dispose());
  geometries.forEach((g) => g.dispose());
}
