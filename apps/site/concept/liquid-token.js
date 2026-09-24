/** Retained-image elastic deformation. Finite springs; no DOM transforms or external code. */
const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
const spring = value => ({value, velocity: 0, target: value});
const atRest = node => Math.abs(node.velocity) < .0015 && Math.abs(node.value - node.target) < .00035;
const vertexSource = `
attribute vec2 a_position;
varying vec2 v_uv;
void main() {
  v_uv = a_position * .5 + .5;
  gl_Position = vec4(a_position, 0., 1.);
}`;
const fragmentSource = `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_texture;
uniform vec2 u_pointer;
uniform vec2 u_pull;
uniform float u_hover;
uniform float u_press;
uniform float u_wobble;
uniform float u_time;
void main() {
  vec2 p = v_uv - .5;
  float squeeze = u_press * .085 + u_wobble * .055;
  p /= vec2(1. + squeeze, 1. - squeeze);
  vec2 delta = p + .5 - u_pointer;
  float distance = length(delta);
  float falloff = exp(-dot(delta, delta) * 12.);
  p -= u_pull * falloff * .060;
  p += delta * falloff * u_press * .105;
  float wave = sin(distance * 21. - u_time * 8.) * u_wobble * .018;
  p -= (delta / max(distance, .08)) * wave * exp(-distance * 2.5);
  p.x -= sin((p.y + .5) * 5.8 + u_time * 1.6) * u_wobble * .017;
  vec2 uv = p + .5;
  vec4 color = texture2D(u_texture, clamp(uv, .001, .999));
  float sheen = exp(-dot(delta, delta) * 28.) * u_hover * .028;
  color.rgb += vec3(.75, .66, 1.) * sheen * color.a;
  gl_FragColor = color;
}`;
function webGLRenderer(canvas, image) {
  const gl = canvas.getContext('webgl', {alpha: true, premultipliedAlpha: true, antialias: false, preserveDrawingBuffer: false, powerPreference: 'low-power'});
  if (!gl) return null;
  const compiled = [];
  const compile = (type, source) => {
    const shader = gl.createShader(type);
    if (!shader) throw new Error('Token shader unavailable');
    compiled.push(shader); gl.shaderSource(shader, source); gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error('Token shader compilation failed');
    return shader;
  };
  const program = gl.createProgram();
  let buffer, texture;
  try {
    gl.attachShader(program, compile(gl.VERTEX_SHADER, vertexSource));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragmentSource));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error('Token program linking failed');
    gl.useProgram(program);
    buffer = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, -1,1, 1,-1, 1,1]), gl.STATIC_DRAW);
    const position = gl.getAttribLocation(program, 'a_position');
    gl.enableVertexAttribArray(position); gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
    texture = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true); gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
    gl.uniform1i(gl.getUniformLocation(program, 'u_texture'), 0);
  } catch (error) {
    compiled.forEach(shader => gl.deleteShader(shader));
    if (buffer) gl.deleteBuffer(buffer); if (texture) gl.deleteTexture(texture); if (program) gl.deleteProgram(program);
    throw error;
  }
  compiled.forEach(shader => gl.deleteShader(shader));
  const uniforms = Object.fromEntries(['pointer', 'pull', 'hover', 'press', 'wobble', 'time'].map(name => [name, gl.getUniformLocation(program, `u_${name}`)]));
  return {
    kind: 'webgl', minimumFrame: 1000 / 60,
    draw(state) {
      gl.viewport(0, 0, canvas.width, canvas.height); gl.useProgram(program);
      gl.uniform2f(uniforms.pointer, state.pointerX, state.pointerY); gl.uniform2f(uniforms.pull, state.pullX, state.pullY);
      gl.uniform1f(uniforms.hover, state.hover); gl.uniform1f(uniforms.press, state.press);
      gl.uniform1f(uniforms.wobble, state.wobble); gl.uniform1f(uniforms.time, state.time);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    },
    destroy() { gl.deleteBuffer(buffer); gl.deleteTexture(texture); gl.deleteProgram(program); },
  };
}
function canvasRenderer(canvas, image) {
  const context = canvas.getContext('2d', {alpha: true});
  if (!context) return null;
  const resolution = 256;
  const source = document.createElement('canvas'); source.width = source.height = resolution;
  const sourceContext = source.getContext('2d', {willReadFrequently: true});
  if (!sourceContext) return null;
  sourceContext.drawImage(image, 0, 0, resolution, resolution);
  const pixels = sourceContext.getImageData(0, 0, resolution, resolution).data;
  // Premultiplied bilinear interpolation keeps translucent edges free of dark seams.
  const premultiplied = new Float32Array(pixels.length);
  for (let i = 0; i < pixels.length; i += 4) {
    const alpha = pixels[i + 3] / 255;
    premultiplied[i] = pixels[i] * alpha; premultiplied[i + 1] = pixels[i + 1] * alpha;
    premultiplied[i + 2] = pixels[i + 2] * alpha; premultiplied[i + 3] = pixels[i + 3];
  }
  const output = sourceContext.createImageData(resolution, resolution), target = output.data;
  const coordinate = new Float32Array(resolution);
  for (let i = 0; i < resolution; i++) coordinate[i] = (i + .5) / resolution;
  return {
    kind: 'canvas2d', minimumFrame: 1000 / 30,
    draw(state) {
      context.clearRect(0, 0, canvas.width, canvas.height);
      if (Math.abs(state.wobble) + Math.abs(state.press) + Math.abs(state.hover) + Math.abs(state.pullX) + Math.abs(state.pullY) < .0001) {
        context.drawImage(image, 0, 0, canvas.width, canvas.height); return;
      }
      const squeeze = state.press * .085 + state.wobble * .055;
      for (let y = 0; y < resolution; y++) {
        const py = (1 - coordinate[y] - .5) / (1 - squeeze);
        for (let x = 0; x < resolution; x++) {
          let px = (coordinate[x] - .5) / (1 + squeeze), warpedY = py;
          const dx = px + .5 - state.pointerX, dy = py + .5 - state.pointerY;
          const distance2 = dx * dx + dy * dy, distance = Math.sqrt(distance2), falloff = Math.exp(-distance2 * 12);
          px -= state.pullX * falloff * .060; warpedY -= state.pullY * falloff * .060;
          px += dx * falloff * state.press * .105; warpedY += dy * falloff * state.press * .105;
          const wave = Math.sin(distance * 21 - state.time * 8) * state.wobble * .018 * Math.exp(-distance * 2.5) / Math.max(distance, .08);
          px -= dx * wave; warpedY -= dy * wave;
          px -= Math.sin((warpedY + .5) * 5.8 + state.time * 1.6) * state.wobble * .017;
          const sx = clamp((px + .5) * resolution - .5, 0, resolution - 1.001), sy = clamp((.5 - warpedY) * resolution - .5, 0, resolution - 1.001);
          const ix = Math.floor(sx), iy = Math.floor(sy), fx = sx - ix, fy = sy - iy;
          const a = (iy * resolution + ix) * 4, b = a+4, c = a+resolution*4, d = c+4;
          const wa = (1-fx)*(1-fy), wb = fx*(1-fy), wc = (1-fx)*fy, wd = fx*fy;
          const out = (y * resolution + x) * 4;
          const alpha = premultiplied[a+3]*wa + premultiplied[b+3]*wb + premultiplied[c+3]*wc + premultiplied[d+3]*wd;
          target[out+3] = alpha;
          const sheen = Math.exp(-distance2 * 28) * state.hover * .028 * 255;
          for (let channel = 0; channel < 3; channel++) {
            const value = premultiplied[a+channel]*wa + premultiplied[b+channel]*wb + premultiplied[c+channel]*wc + premultiplied[d+channel]*wd;
            target[out+channel] = alpha > 0 ? value * 255 / alpha + sheen * (channel === 0 ? .75 : channel === 1 ? .66 : 1) : 0;
          }
        }
      }
      sourceContext.putImageData(output, 0, 0);
      context.imageSmoothingEnabled = true; context.imageSmoothingQuality = 'high';
      context.drawImage(source, 0, 0, canvas.width, canvas.height);
    },
    destroy() { source.width = source.height = 1; },
  };
}
/** Initialize once; call play() for an explicit replay, never on an interval. */
export async function createLiquidToken({button, canvas, image, reducedMotion = false, interactive = true}) {
  if (!button || !canvas || !image) throw new TypeError('Token elements are required');
  if (!image.complete || !image.naturalWidth) await image.decode();
  if (!image.naturalWidth) throw new Error('Token image is unavailable');
  let renderer;
  try { renderer = webGLRenderer(canvas, image) || canvasRenderer(canvas, image); } catch { renderer = null; }
  let reduced = Boolean(reducedMotion), destroyed = false, contextLost = false, visible = true;
  let frame = 0, lastFrame = 0, lastInput = 0, elapsed = 0, lastDraw = 0;
  let framesRendered = 0, maxRenderTime = 0, totalRenderTime = 0;
  let activePointer = null, lastPointerRelease = -Infinity, pointerX = .5, pointerY = .5;
  const springs = {pullX: spring(0), pullY: spring(0), hover: spring(0), press: spring(0), wobble: spring(0)};
  const listeners = [];
  const listen = (element, name, handler, options) => {
    element.addEventListener(name, handler, options);
    listeners.push(() => element.removeEventListener(name, handler, options));
  };
  const snapshot = () => ({pointerX, pointerY, time: elapsed, ...Object.fromEntries(Object.entries(springs).map(([name, node]) => [name, node.value]))});
  function draw() {
    if (!renderer || destroyed || contextLost) return;
    const started = performance.now(); renderer.draw(snapshot());
    const cost = performance.now() - started;
    maxRenderTime = Math.max(maxRenderTime, cost); totalRenderTime += cost; framesRendered++;
  }
  function stop(reset = false) {
    if (frame) cancelAnimationFrame(frame);
    frame = 0; lastFrame = 0; lastDraw = 0;
    if (reset) {
      for (const node of Object.values(springs)) node.value = node.velocity = node.target = 0;
      activePointer = null; draw();
    }
  }
  function frameTick(now) {
    frame = 0;
    if (destroyed || reduced || contextLost || !visible || document.hidden || !renderer) return;
    const dt = Math.min((now - (lastFrame || now - 16.67)) / 1000, .034);
    lastFrame = now; elapsed += dt;
    for (const [name, node] of Object.entries(springs)) {
      const stiffness = name === 'wobble' ? 120 : 175, damping = name === 'wobble' ? 10 : 17;
      for (let part = 0; part < 2; part++) {
        node.velocity += (stiffness * (node.target - node.value) - damping * node.velocity) * dt / 2;
        node.value += node.velocity * dt / 2;
      }
    }
    const settled = Object.values(springs).every(atRest) || now - lastInput > 2400;
    if (settled) for (const node of Object.values(springs)) { node.value = node.target; node.velocity = 0; }
    if (settled || now - lastDraw >= renderer.minimumFrame - 1) { draw(); lastDraw = now; }
    if (!settled) frame = requestAnimationFrame(frameTick);
    else { lastFrame = 0; lastDraw = 0; }
  }
  function wake() {
    if (destroyed || reduced || contextLost || !visible || document.hidden || !renderer) return false;
    lastInput = performance.now(); if (!frame) frame = requestAnimationFrame(frameTick); return true;
  }
  function play() { if (wake()) { springs.wobble.value = .88; springs.wobble.velocity = 2.1; } }
  function point(event) {
    const rect = button.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    pointerX = clamp((event.clientX - rect.left) / rect.width, .12, .88);
    pointerY = 1 - clamp((event.clientY - rect.top) / rect.height, .12, .88);
    springs.pullX.target = (pointerX - .5) * 2; springs.pullY.target = (pointerY - .5) * 2;
  }
  function release(event) {
    if (activePointer !== event.pointerId) return;
    activePointer = null; lastPointerRelease = performance.now();
    springs.press.target = 0; springs.wobble.value = -.72; springs.wobble.velocity = 1.7;
    if (event.pointerType !== 'mouse') { springs.hover.target = 0; springs.pullX.target = springs.pullY.target = 0; }
    wake();
  }
  function resize() {
    if (destroyed) return;
    const rect = button.getBoundingClientRect();
    const side = clamp(Math.ceil(Math.max(rect.width, rect.height) * Math.min(devicePixelRatio || 1, 2)), 128, 700);
    if (canvas.width !== side || canvas.height !== side) { canvas.width = canvas.height = side; draw(); }
  }
  let intersection, resizeObserver;
  if (renderer) {
    canvas.hidden = false; image.hidden = true;
    if ('disabled' in button) button.disabled = false;
    resize(); draw();
    if (interactive) {
      listen(button, 'pointerenter', event => {
        if (reduced || event.pointerType !== 'mouse') return;
        point(event); springs.hover.target = 1; wake();
      }, {passive: true});
      listen(button, 'pointermove', event => {
        if (reduced || event.pointerType !== 'mouse' && activePointer !== event.pointerId) return;
        point(event); springs.hover.target = 1; wake();
      }, {passive: true});
      listen(button, 'pointerdown', event => {
        if (reduced || event.button !== 0 || !event.isPrimary) return;
        activePointer = event.pointerId; point(event); springs.hover.target = 1; springs.press.target = 1; wake();
      }, {passive: true});
      listen(window, 'pointerup', release, {passive: true});
      listen(window, 'pointercancel', release, {passive: true});
      listen(button, 'pointerleave', () => { springs.hover.target = 0; springs.pullX.target = springs.pullY.target = 0; wake(); }, {passive: true});
      listen(button, 'click', event => { if (event.detail === 0 || performance.now() - lastPointerRelease > 400) play(); });
    }
    listen(document, 'visibilitychange', () => { if (document.hidden) stop(true); });
    listen(window, 'blur', () => stop(true));
    listen(canvas, 'webglcontextlost', event => {
      event.preventDefault(); contextLost = true; stop(true);
      canvas.hidden = true; image.hidden = false; button.disabled = true;
    });
    listen(canvas, 'webglcontextrestored', () => {
      if (destroyed) return;
      try {
        renderer = webGLRenderer(canvas, image); contextLost = !renderer;
        canvas.hidden = !renderer; image.hidden = Boolean(renderer); button.disabled = !renderer; stop(true);
      } catch { contextLost = true; canvas.hidden = true; image.hidden = false; button.disabled = true; }
    });
    if ('IntersectionObserver' in window) {
      intersection = new IntersectionObserver(entries => { visible = entries[0].isIntersecting; if (!visible) stop(true); }, {threshold: 0});
      intersection.observe(button);
    }
    if ('ResizeObserver' in window) { resizeObserver = new ResizeObserver(resize); resizeObserver.observe(button); }
    else listen(window, 'resize', resize, {passive: true});
  } else { canvas.hidden = true; image.hidden = false; button.disabled = true; }
  return {
    play,
    setReducedMotion(value) { reduced = Boolean(value); if (reduced) stop(true); },
    getState: () => ({
      renderer: renderer?.kind || 'poster', frameActive: frame !== 0, reducedMotion: reduced, visible, contextLost, destroyed, framesRendered,
      renderSize: canvas.width, softwareSampleSize: renderer?.kind === 'canvas2d' ? 256 : null,
      maxRenderTimeMs: Math.round(maxRenderTime * 100) / 100,
      averageRenderTimeMs: framesRendered ? Math.round(totalRenderTime / framesRendered * 100) / 100 : 0,
      // Timing measures JS submission, not GPU completion or delivered frame rate.
      springEnergy: Number(Object.values(springs).reduce((sum, node) => sum + Math.abs(node.velocity) + Math.abs(node.value-node.target), 0).toFixed(4)),
    }),
    destroy() {
      if (destroyed) return; stop(true); destroyed = true;
      listeners.forEach(remove => remove()); intersection?.disconnect(); resizeObserver?.disconnect();
      renderer?.destroy(); canvas.hidden = true; image.hidden = false; button.disabled = true;
    },
  };
}
