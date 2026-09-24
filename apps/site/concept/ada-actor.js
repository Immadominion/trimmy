import { adaRigData } from './ada-rig-data.js';

// Source-textured website cutout rig with a shared, continuous acting master.
// The actor is decorative: only the caller owns dialogue and activity outcomes.
const WIDTH = 480;
const HEIGHT = 512;
const clamp = (n, min = 0, max = 1) => Math.max(min, Math.min(max, n));
const mix = (a, b, t) => a + (b - a) * t;
const ease = (t, start, end) => {
  const x = clamp((t - start) / (end - start));
  return x * x * (3 - 2 * x);
};
const pulse = (t, a, b, c, d) => ease(t, a, b) - ease(t, c, d);
const neutral = () => ({ head: 0, headY: 0, gazeX: 0, gazeY: 0, open: 1, arm: .67, torso: 0, torsoY: 0 });
const targets = {
  listen: neutral(),
  read: { ...neutral(), head: .042, headY: .8, gazeX: -.65, gazeY: 1, torso: -.008 },
  offer: { ...neutral(), head: .018, gazeX: .25, gazeY: .4, arm: .22 },
  correct: { ...neutral(), head: -.035, gazeX: -.45, open: .86, torso: -.015, arm: .37 },
  success: { ...neutral(), head: -.015, gazeX: -.2, torso: .008, arm: .52 },
};
const durations = { listen: 2300, read: 2550, offer: 2750, correct: 2550, success: 2550 };

function path(commands, mapY = (_x, y) => y) {
  const shape = new Path2D();
  for (const [op, ...v] of commands) {
    if (op === 'M') shape.moveTo(v[0], mapY(v[0], v[1]));
    else if (op === 'L') shape.lineTo(v[0], mapY(v[0], v[1]));
    else if (op === 'C') shape.bezierCurveTo(v[0], mapY(v[0], v[1]), v[2], mapY(v[2], v[3]), v[4], mapY(v[4], v[5]));
    else if (op === 'Z') shape.closePath();
    else throw new Error('Unsupported character path');
  }
  return shape;
}

function partBounds(commands) {
  const xs = [], ys = [];
  for (const command of commands) {
    for (let i = 1; i < command.length; i += 2) {
      xs.push(command[i]); ys.push(command[i + 1]);
    }
  }
  // Bezier curves are contained by their controls; this bound includes a gutter.
  const x = Math.floor(Math.min(...xs)) - 2;
  const y = Math.floor(Math.min(...ys)) - 2;
  return [x, y, Math.ceil(Math.max(...xs)) - x + 2, Math.ceil(Math.max(...ys)) - y + 2];
}

function compilePart(raw, image, ratio) {
  const bounds = partBounds(raw.maskPath);
  const [x, y, width, height] = bounds;
  const layer = document.createElement('canvas');
  layer.width = Math.ceil(width * ratio);
  layer.height = Math.ceil(height * ratio);
  const context = layer.getContext('2d');
  if (!context) throw new Error('Character texture context unavailable');
  context.scale(ratio, ratio);
  context.translate(-x, -y);
  context.save();
  const mask = path(raw.maskPath);
  context.clip(mask);
  if (raw.clipPath) context.clip(path(raw.clipPath));
  if (raw.fill) {
    context.fillStyle = raw.fill;
    context.globalAlpha = raw.opacity ?? 1;
    context.fill(mask);
    context.globalAlpha = 1;
  }
  const source = raw.texturePatch?.sourceRect ?? raw.sourceRect;
  if (source) {
    const destination = raw.texturePatch?.destinationRect ?? [...(raw.destinationOffset ?? [0, 0]), source[2], source[3]];
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = 'high';
    if (raw.textureRepeat) {
      const swatch = document.createElement('canvas');
      swatch.width = source[2]; swatch.height = source[3];
      const swatchContext = swatch.getContext('2d');
      swatchContext.drawImage(image, ...source, 0, 0, source[2], source[3]);
      context.fillStyle = context.createPattern(swatch, 'repeat');
      context.fill(mask);
    } else context.drawImage(image, ...source, ...destination);
  }
  if (raw.strokePath) {
    context.strokeStyle = raw.stroke;
    context.lineWidth = raw.strokeWidth ?? 1;
    context.stroke(path(raw.strokePath));
  }
  context.restore();
  if (raw.borderOverlap) {
    context.save();
    if (raw.clipPath) context.clip(path(raw.clipPath));
    context.strokeStyle = raw.fill;
    context.lineWidth = raw.borderOverlap;
    context.stroke(mask);
    context.restore();
  }
  // Subtract only from this isolated layer, never the previously painted torso.
  context.globalCompositeOperation = 'destination-out';
  for (const excluded of raw.excludePaths ?? []) {
    const excludedPath = path(excluded);
    context.fill(excludedPath);
    if (raw.excludeStroke) {
      context.lineWidth = raw.excludeStroke;
      context.stroke(excludedPath);
    }
  }
  if (raw.edgeInset) {
    context.lineWidth = raw.edgeInset;
    context.lineJoin = 'round';
    context.stroke(mask);
  }
  context.globalCompositeOperation = 'source-over';
  return { ...raw, layer, bounds, pixelRatio: ratio };
}

function compileDrawing(raw, image, ratio) {
  const parts = raw.parts.map(part => compilePart(part, image, ratio));
  const eyes = raw.eyes.map(eye => ({
    ...eye,
    aperture: path(eye.aperturePath),
    upper: path(eye.upperLidPath),
    repairPart: compilePart({ ...eye.repair, fill: eye.repair.fallbackFill }, image, ratio),
  }));
  return { parts, eyes, head: parts.find(part => part.id === 'head') };
}

function headTransform(context, pivot, pose) {
  context.translate(pivot[0], pivot[1] + pose.headY);
  context.rotate(clamp(pose.head, -Math.PI / 60, Math.PI / 60));
  context.translate(-pivot[0], -pivot[1]);
}

function bodyTransform(context, pose) {
  context.translate(229, 487 + pose.torsoY);
  context.rotate(pose.torso);
  context.translate(-229, -487);
}

function drawPart(context, part) {
  const [x, y] = part.bounds;
  context.drawImage(part.layer, x, y, part.layer.width / part.pixelRatio, part.layer.height / part.pixelRatio);
}

function eyePath(eye, commands, openness) {
  const first = eye.upperLidPath[0];
  const last = eye.upperLidPath.at(-1);
  const a = first.slice(1), b = last.slice(-2);
  return path(commands, (x, y) => {
    const t = clamp((x - a[0]) / (b[0] - a[0]));
    const closed = a[1] + (b[1] - a[1]) * t + (eye.blink.closedBow ?? 3) * 4 * t * (1 - t);
    return closed + (y - closed) * openness;
  });
}

function drawEye(context, eye, pose) {
  drawPart(context, eye.repairPart);
  const open = clamp(pose.open);
  if (open > .001) {
    const aperture = open === 1 ? eye.aperture : eyePath(eye, eye.aperturePath, open);
    context.save();
    context.clip(aperture);
    context.fillStyle = eye.whiteFill;
    context.fill(aperture);
    const iris = eye.iris;
    context.beginPath();
    context.ellipse(
      iris.center[0] + clamp(pose.gazeX, -1, 1) * iris.maxGazeOffset[0],
      iris.center[1] + clamp(pose.gazeY, -1, 1) * iris.maxGazeOffset[1],
      iris.radiusX, iris.radiusY, 0, 0, Math.PI * 2,
    );
    context.fillStyle = iris.fill;
    context.fill();
    context.restore();
  }
  context.strokeStyle = eye.lidStroke;
  context.lineWidth = eye.lidStrokeWidth;
  context.lineCap = 'round';
  context.stroke(open === 1 ? eye.upper : eyePath(eye, eye.upperLidPath, open));
}

function performancePose(from, beat, time) {
  const target = targets[beat];
  if (time >= 1) return { ...target };
  const eyes = ease(time, .015, .18);
  const head = ease(time, .09, .39);
  const arm = ease(time, .07, .28);
  const body = ease(time, .055, .34);
  const nod = beat === 'success' ? pulse(time, .19, .33, .40, .64) : 0;
  const acknowledge = beat === 'listen' ? pulse(time, .12, .28, .34, .57) : 0;
  const offer = beat === 'offer' ? pulse(time, .025, .17, .34, .67) : 0;
  const consider = beat === 'correct' ? pulse(time, .09, .23, .37, .64) : 0;
  const glance = beat === 'listen' ? pulse(time, .03, .12, .28, .46) : 0;
  const blink = pulse(time, .49, .515, .535, .575);
  return {
    head: mix(from.head, target.head, head) + nod * .04 - acknowledge * .018 + offer * .027 - consider * .017,
    headY: mix(from.headY, target.headY, head) + nod * 1.8 + offer * .9,
    gazeX: mix(from.gazeX, target.gazeX, eyes) - glance * .4 + offer * .35,
    gazeY: mix(from.gazeY, target.gazeY, eyes) + offer * .65,
    open: mix(from.open, target.open, eyes) * (1 - blink),
    arm: mix(from.arm, target.arm, arm) - offer * .27 - consider * .13 + nod * .1,
    torso: mix(from.torso, target.torso, body) + offer * .024 - nod * .016 + consider * .009,
    torsoY: mix(from.torsoY, target.torsoY, body) + offer * 1.3 - acknowledge * .7,
  };
}

function loadAtlas() {
  return new Promise((resolve, reject) => {
    const image = new Image();
    const timeout = setTimeout(() => { image.onload = image.onerror = null; reject(new Error('Character texture timed out')); }, 15000);
    image.onload = () => { clearTimeout(timeout); resolve(image); };
    image.onerror = () => { clearTimeout(timeout); reject(new Error('Character texture unavailable')); };
    image.decoding = 'async';
    image.src = new URL('./assets/ada-atlas.webp', import.meta.url).href;
  });
}

/** Create a decorative, finite actor; initialization failure hides the canvas. */
export async function createAdaActor(canvas) {
  let frame = 0;
  let destroyed = false;
  let reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let observer = null;
  let resizeObserver = null;
  let visibilityHandler = null;
  let parts = [];
  const cancel = () => { cancelAnimationFrame(frame); frame = 0; };
  const failed = { play() {}, setReducedMotion() {}, destroy() { cancel(); } };
  try {
    const context = canvas.getContext('2d', { alpha: true });
    if (!context) throw new Error('Character canvas unavailable');
    canvas.setAttribute('aria-hidden', 'true');
    canvas.dataset.adaStatus = 'loading';
    const image = await loadAtlas();
    if (image.naturalWidth !== 1536 || image.naturalHeight !== 1024) throw new Error('Unexpected character atlas');
    const ratio = Math.min(window.devicePixelRatio || 1, 1.5);
    const drawing = compileDrawing(adaRigData.website, image, ratio);
    parts = [...drawing.parts, ...drawing.eyes.map(eye => eye.repairPart)];
    let beat = 'listen';
    let pose = neutral();
    let active = false;
    let visible = true;
    let framesRendered = 0;
    const inViewport = () => {
      const bounds = canvas.getBoundingClientRect();
      return bounds.bottom > 0 && bounds.top < window.innerHeight && bounds.right > 0 && bounds.left < window.innerWidth && bounds.width > 0 && bounds.height > 0;
    };

    function paint() {
      if (destroyed) return;
      context.setTransform(1, 0, 0, 1, 0, 0);
      context.clearRect(0, 0, canvas.width, canvas.height);
      context.setTransform(canvas.width / WIDTH, 0, 0, canvas.height / HEIGHT, 0, 0);
      // Give the lifted fingers room inside the shared 480-pixel scene.
      context.translate(16, 0);
      bodyTransform(context, pose);
      for (const part of drawing.parts) {
        context.save();
        if (part.parentId === 'head') headTransform(context, drawing.head.pivot, pose);
        if (part.id === 'head') headTransform(context, part.pivot, pose);
        if (part.id === 'forearm') {
          context.translate(...part.pivot);
          context.rotate(clamp(pose.arm, -.2, .9));
          context.translate(-part.pivot[0], -part.pivot[1]);
        }
        drawPart(context, part);
        context.restore();
      }
      context.save();
      headTransform(context, drawing.head.pivot, pose);
      for (const eye of drawing.eyes) drawEye(context, eye, pose);
      context.restore();
      framesRendered++;
    }

    function resize() {
      if (destroyed) return;
      const cssWidth = canvas.getBoundingClientRect().width || WIDTH;
      const resolution = Math.min(ratio, Math.max(.5, cssWidth / WIDTH * ratio));
      const width = Math.round(WIDTH * resolution), height = Math.round(HEIGHT * resolution);
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }
      paint();
    }

    function settle() {
      cancel();
      active = false;
      pose = { ...targets[beat] };
      canvas.dataset.adaMotion = 'settled';
      paint();
    }

    function play(nextBeat) {
      if (destroyed || !Object.hasOwn(targets, nextBeat)) return;
      cancel();
      const from = { ...pose };
      beat = nextBeat;
      canvas.dataset.adaState = beat;
      visible = inViewport();
      if (reduced || document.hidden || !visible) { settle(); return; }
      active = true;
      canvas.dataset.adaMotion = 'playing';
      const start = performance.now();
      function tick(now) {
        frame = 0;
        if (destroyed) return;
        if (reduced || document.hidden || !visible) { settle(); return; }
        const time = clamp((now - start) / durations[beat]);
        pose = performancePose(from, beat, time);
        paint();
        if (time < 1) frame = requestAnimationFrame(tick);
        else { active = false; canvas.dataset.adaMotion = 'settled'; }
      }
      tick(start);
    }

    function destroy() {
      if (destroyed) return;
      cancel();
      active = false;
      destroyed = true;
      observer?.disconnect();
      resizeObserver?.disconnect();
      document.removeEventListener('visibilitychange', visibilityHandler);
      for (const part of parts) { part.layer.width = 0; part.layer.height = 0; }
      parts = [];
      canvas.dataset.adaMotion = 'destroyed';
    }

    visibilityHandler = () => { if (document.hidden && active) settle(); };
    document.addEventListener('visibilitychange', visibilityHandler);
    if ('IntersectionObserver' in window) {
      observer = new IntersectionObserver(entries => {
        visible = entries[0]?.isIntersecting ?? false;
        if (!visible && active) settle();
      });
      observer.observe(canvas);
    }
    if ('ResizeObserver' in window) {
      resizeObserver = new ResizeObserver(resize);
      resizeObserver.observe(canvas);
    }
    resize();
    canvas.hidden = false;
    canvas.dataset.adaStatus = 'ready';
    canvas.dataset.adaState = beat;
    canvas.dataset.adaMotion = 'settled';
    return {
      play,
      setReducedMotion(value) {
        if (destroyed) return;
        reduced = Boolean(value);
        if (reduced) settle();
      },
      destroy,
      getState() {
        return { beat, active, frameActive: Boolean(frame), visible, reducedMotion: reduced, destroyed, framesRendered, pose: { ...pose } };
      },
    };
  } catch {
    cancel();
    observer?.disconnect();
    resizeObserver?.disconnect();
    if (visibilityHandler) document.removeEventListener('visibilitychange', visibilityHandler);
    for (const part of parts) { part.layer.width = 0; part.layer.height = 0; }
    if (canvas) { canvas.hidden = true; canvas.dataset.adaStatus = 'failed'; }
    return failed;
  }
}
