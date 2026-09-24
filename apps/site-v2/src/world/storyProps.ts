import * as THREE from "three";

const smooth = (n: number) => { const x = Math.max(0, Math.min(1, n)); return x * x * (3 - 2 * x); };

/** Original scenic reconstructions; these are not claimed to be surviving artifacts. */
export function makeStoryProps() {
  const object = new THREE.Group();
  const wall = new THREE.Group(); object.add(wall);
  const loader = new THREE.TextureLoader();
  const timberMap = loader.load("/world/details/walnut-base.png"); timberMap.colorSpace = THREE.SRGBColorSpace;
  const timberNormal = loader.load("/world/details/walnut-normal.png");
  const wood = new THREE.MeshStandardMaterial({ map: timberMap, normalMap: timberNormal, normalScale: new THREE.Vector2(.38, .38), color: "#afa291", roughness: .88 });
  const iron = new THREE.MeshStandardMaterial({ color: "#292827", metalness: .75, roughness: .64 });
  const brass = new THREE.MeshStandardMaterial({ color: "#bca477", metalness: .85, roughness: .36 });
  const cube = (group: THREE.Group, position: [number, number, number], dimensions: [number, number, number], material: THREE.Material) => {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(...dimensions), material); mesh.position.set(...position);
    mesh.castShadow = true; mesh.receiveShadow = true; group.add(mesh); return mesh;
  };
  // The built1653 fortification used nine-foot planks, not pointed frontier stakes.
  const planks = new THREE.InstancedMesh(new THREE.BoxGeometry(.295, 2.74, .115), wood, 64);
  const nails = new THREE.InstancedMesh(new THREE.CylinderGeometry(.015, .015, .012, 6), iron, 128);
  const matrix = new THREE.Matrix4(); const rotation = new THREE.Quaternion(); const scale = new THREE.Vector3(1, 1, 1);
  for (let i = 0; i < 64; i++) {
    const x = -47.6 + i * .305;
    matrix.compose(new THREE.Vector3(x, 1.37 + Math.sin(i * 7) * .016, 5.8), rotation, scale); planks.setMatrixAt(i, matrix);
    rotation.setFromAxisAngle(new THREE.Vector3(1, 0, 0), Math.PI / 2);
    for (let j = 0; j < 2; j++) { matrix.compose(new THREE.Vector3(x, .52 + j * 1.63, 5.733), rotation, scale); nails.setMatrixAt(i * 2 + j, matrix); }
    rotation.identity();
  }
  planks.castShadow = true; planks.receiveShadow = true; wall.add(planks, nails);
  for (const y of [.52, 2.15]) cube(wall, [-37.99, y, 5.91], [19.55, .18, .18], wood);
  for (let x = -47.6; x < -28; x += 4.57) cube(wall, [x, 1.39, 5.91], [.24, 2.78, .24], wood);
  // An inlaid line tracks the old boundary and resolves into the modern street name.
  cube(wall, [-38, .105, 4.95], [20, .016, .024], brass);
  const label = document.createElement("canvas"); label.width = 1536; label.height = 192;
  const ctx = label.getContext("2d")!; ctx.fillStyle = "#c9bfa5"; ctx.textAlign = "center";
  ctx.font = "500 66px Georgia"; ctx.fillText("W A L L   S T R E E T", 768, 118);
  const lettering = new THREE.CanvasTexture(label); lettering.colorSpace = THREE.SRGBColorSpace;
  const sign = new THREE.Mesh(new THREE.PlaneGeometry(5, .625), new THREE.MeshBasicMaterial({ map: lettering, transparent: true, opacity: .8, depthWrite: false, side: THREE.DoubleSide }));
  sign.rotation.x = -Math.PI / 2; sign.position.set(-36.9, .116, 3.72); wall.add(sign);

  const ledgerTable = new THREE.Group(); object.add(ledgerTable);
  const table = (group: THREE.Group, x: number, z: number, width: number, depth: number, top: number) => {
    cube(group, [x, top - .055, z], [width, .11, depth], wood);
    for (const dx of [-width * .4, width * .4]) for (const dz of [-depth * .37, depth * .37]) cube(group, [x + dx, (top - .11) / 2, z + dz], [.075, top - .11, .075], wood);
  };
  table(ledgerTable, -27.2, 1.6, 2.15, 1.3, 1);
  const tickerTable = new THREE.Group(); object.add(tickerTable);
  table(tickerTable, -2, 35.5, 1.55, 1.05, 1.15);
  cube(tickerTable, [-2, 1.11, 34.97], [1.55, .05, .025], brass);
  const labelLight = new THREE.SpotLight("#ffe1b1", 38, 9, .75, .75, 2);
  labelLight.position.set(-29, 5.5, -.5); labelLight.target.position.set(-27.2, 1, 1.6); object.add(labelLight, labelLight.target);
  const tickerLight = new THREE.PointLight("#ffe2b9", 20, 5, 2); tickerLight.position.set(-.5, 3.5, 34); object.add(tickerLight);
  return {
    object,
    update(p: number) {
      wall.visible = p < 2.92;
      ledgerTable.visible = p > 2.05 && p < 4.35;
      tickerTable.visible = p > 5.1 && p < 7.1;
      labelLight.intensity = 38 * smooth(1 - Math.abs(p - 3));
      tickerLight.intensity = 20 * smooth(1 - Math.abs(p - 6));
    },
  };
}
