import { useEffect, useRef, useState } from "react";
import { useFrame } from "@/lib/useFrame";

/**
 * The sky and the title painted on it, drawn together in one WebGL layer.
 *
 * The title paints itself on: the text is drawn once into a texture and shown
 * through a noise field that spreads from the top centre with a ragged, streaky
 * edge, like ink soaking into paper. Scroll drives it, so scrolling back
 * un-paints it. Our own shader: 2D simplex noise (Ashima Arts, MIT) in two
 * bands, one stretched sideways for brush streaks and one fine for grain.
 *
 * Both sit "at infinity" in the rendered scene, so when the camera turns they
 * move by the homography the render exported. Every pixel looks itself up
 * through that mapping, which stays correct even when part of the sky is behind
 * the camera (a CSS 3D transform would clip or smear there).
 *
 * Without WebGL the title fades in on a plain canvas and the sky is left out.
 */

export type SkyTitleState = {
  /** Paint-on reveal, 0..1. */
  progress: number;
  titleOpacity: number;
  skyOpacity: number;
  /** Row-major 3x3: screen (0..1, y down) to hero-frame coordinates (0..1). */
  warp: number[];
  /** The hero frame on screen, as fractions of the screen: x, y, width, height. */
  frame: [number, number, number, number];
  /** Where the sky image sits, in hero-frame coordinates: u0, v0, u1, v1. */
  skyBox: [number, number, number, number];
};

type Props = {
  /** Draws the title in canvas pixels; `scale` is canvas pixels per CSS pixel. */
  draw: (context: CanvasRenderingContext2D, width: number, height: number, scale: number) => void;
  /** Font descriptors to load before drawing, as for document.fonts.load. */
  fonts: string[];
  /** The sky image, or undefined for the title alone. */
  sky?: string;
  /** Read every frame; null when the layer is off screen. */
  state: () => SkyTitleState | null;
  className?: string;
};

const VERT = `
attribute vec2 aPos;
varying vec2 vUv;
void main() {
  vUv = vec2(aPos.x * 0.5 + 0.5, 0.5 - aPos.y * 0.5);
  gl_Position = vec4(aPos, 0.0, 1.0);
}`;

const FRAG = `
precision highp float;
varying vec2 vUv;
uniform sampler2D uTitle;
uniform sampler2D uSky;
uniform float uHasSky;
uniform float uProgress;
uniform float uTitleOpacity;
uniform float uSkyOpacity;
uniform float uAspect;
uniform mat3 uWarp;
uniform vec4 uFrame;
uniform vec4 uSkyBox;

vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }
float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod289(i);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
  m = m * m; m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}
float fbm(vec2 p) {
  float f = 0.0, a = 0.5;
  for (int i = 0; i < 5; i++) { f += a * snoise(p); p = p * 2.03 + 17.1; a *= 0.5; }
  return f;
}

void main() {
  // Where this screen pixel looks, in the hero frame. Behind the camera: nothing.
  vec3 q = uWarp * vec3(vUv, 1.0);
  if (q.z <= 0.0) { gl_FragColor = vec4(0.0); return; }
  vec2 hero = q.xy / q.z;

  // The sky image ends at the horizon; below it there is street, never sky, so
  // whatever the street uncovers (the 1792 picture) shows through.
  vec4 sky = vec4(0.0);
  if (uHasSky > 0.5 && uSkyOpacity > 0.0) {
    vec2 s = (hero - uSkyBox.xy) / (uSkyBox.zw - uSkyBox.xy);
    if (s.y <= 1.0) sky = texture2D(uSky, clamp(s, 0.0, 1.0)) * uSkyOpacity;
  }

  // The title texture is the screen as it was at the hero pose.
  vec2 t = uFrame.xy + hero * uFrame.zw;
  vec4 ink = vec4(0.0);
  if (uTitleOpacity > 0.0 && t.x >= 0.0 && t.x <= 1.0 && t.y >= 0.0 && t.y <= 1.0) {
    ink = texture2D(uTitle, t);
    if (ink.a > 0.002 && uProgress < 1.0) {
      vec2 p = vec2(t.x * uAspect, t.y);
      // Distance from just above the top centre: 0 there, about 1 at the far corners.
      vec2 origin = vec2(0.5 * uAspect, -0.12);
      float d = length(p - origin) / length(vec2(0.5 * uAspect, 1.12));
      float streak = fbm(vec2(p.x * 2.6, p.y * 11.0));
      float grain = fbm(p * 26.0);
      float field = d - streak * 0.34 - grain * 0.08;
      float front = mix(-0.35, 1.25, uProgress);
      ink *= smoothstep(field - 0.015, field + 0.045, front);
    }
    ink *= uTitleOpacity;
  }
  gl_FragColor = ink + sky * (1.0 - ink.a);
}`;

function compile(gl: WebGLRenderingContext, type: number, src: string) {
  const shader = gl.createShader(type)!;
  gl.shaderSource(shader, src);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader) || "shader");
  return shader;
}

const same = (a: number[], b: number[]) => a.length === b.length && a.every((v, i) => Math.abs(v - b[i]!) < 1e-6);

export function PaintTitle({ draw: drawTitle, fonts, sky, state, className = "" }: Props) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const fallback = useRef<HTMLCanvasElement>(null);
  const render = useRef<((s: SkyTitleState) => void) | null>(null);
  const read = useRef(state);
  read.current = state;
  const [webgl, setWebgl] = useState(true);

  useEffect(() => {
    const el = canvas.current;
    if (!el) return;
    const gl = el.getContext("webgl", { premultipliedAlpha: true, alpha: true, antialias: false });
    if (!gl || gl.isContextLost()) { setWebgl(false); return; }

    let program: WebGLProgram;
    try {
      program = gl.createProgram()!;
      gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, VERT));
      gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, FRAG));
      gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error("link");
    } catch {
      setWebgl(false);
      return;
    }
    gl.useProgram(program);
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    const aPos = gl.getAttribLocation(program, "aPos");
    gl.enableVertexAttribArray(aPos);
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);
    const u = (name: string) => gl.getUniformLocation(program, name);
    const uniforms = {
      progress: u("uProgress"), titleOpacity: u("uTitleOpacity"), skyOpacity: u("uSkyOpacity"),
      aspect: u("uAspect"), warp: u("uWarp"), frame: u("uFrame"), skyBox: u("uSkyBox"), hasSky: u("uHasSky"),
    };
    gl.uniform1i(u("uTitle"), 0);
    gl.uniform1i(u("uSky"), 1);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    const texture = () => {
      const t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      return t;
    };
    const titleTexture = texture();
    const skyTexture = texture();
    gl.uniform1f(uniforms.hasSky, 0);

    const ink = document.createElement("canvas");
    let last: SkyTitleState | null = null;
    let dirty = true;
    let ready = false;
    let disposed = false;

    // Type is drawn at device resolution and uploaded once per size.
    const rasterize = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = Math.max(1, Math.round(el.clientWidth * dpr));
      const h = Math.max(1, Math.round(el.clientHeight * dpr));
      el.width = w; el.height = h; ink.width = w; ink.height = h;
      const c = ink.getContext("2d")!;
      c.clearRect(0, 0, w, h);
      drawTitle(c, w, h, dpr);
      gl.viewport(0, 0, w, h);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, titleTexture);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, ink);
      gl.uniform1f(uniforms.aspect, w / h);
      ready = true;
      dirty = true;
    };

    if (sky) {
      const image = new Image();
      image.decoding = "async";
      image.onload = () => {
        if (disposed) return;
        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, skyTexture);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
        gl.uniform1f(uniforms.hasSky, 1);
        dirty = true;
      };
      image.src = sky;
    }

    render.current = (s: SkyTitleState) => {
      if (!ready) return;
      if (!dirty && last && last.progress === s.progress && last.titleOpacity === s.titleOpacity
        && last.skyOpacity === s.skyOpacity && same(last.warp, s.warp) && same(last.frame, s.frame) && same(last.skyBox, s.skyBox)) return;
      last = { ...s, warp: [...s.warp], frame: [...s.frame] as SkyTitleState["frame"], skyBox: [...s.skyBox] as SkyTitleState["skyBox"] };
      dirty = false;
      const m = s.warp;
      gl.uniformMatrix3fv(uniforms.warp, false, [m[0]!, m[3]!, m[6]!, m[1]!, m[4]!, m[7]!, m[2]!, m[5]!, m[8]!]);
      gl.uniform4fv(uniforms.frame, s.frame);
      gl.uniform4fv(uniforms.skyBox, s.skyBox);
      gl.uniform1f(uniforms.progress, s.progress);
      gl.uniform1f(uniforms.titleOpacity, s.titleOpacity);
      gl.uniform1f(uniforms.skyOpacity, s.skyOpacity);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, titleTexture);
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, skyTexture);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    };

    // The fonts have to be in before the type goes into the texture.
    Promise.all(fonts.map((font) => document.fonts.load(font)))
      .catch(() => undefined)
      .then(() => { if (!disposed) rasterize(); });

    const observer = new ResizeObserver(() => { if (ready) rasterize(); });
    observer.observe(el);

    return () => {
      disposed = true;
      render.current = null;
      observer.disconnect();
      // Free what this run made, but keep the context: the canvas can mount
      // again (React does it twice in development) and would get a dead one.
      gl.deleteTexture(titleTexture);
      gl.deleteTexture(skyTexture);
      gl.deleteBuffer(buffer);
      gl.deleteProgram(program);
    };
  }, [drawTitle, fonts, sky]);

  // Without WebGL: the title alone on a plain canvas, faded by opacity.
  useEffect(() => {
    const el = fallback.current;
    if (webgl || !el) return;
    let disposed = false;
    const paint = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      el.width = Math.max(1, Math.round(el.clientWidth * dpr));
      el.height = Math.max(1, Math.round(el.clientHeight * dpr));
      const c = el.getContext("2d");
      if (!c) return;
      c.clearRect(0, 0, el.width, el.height);
      drawTitle(c, el.width, el.height, dpr);
    };
    Promise.all(fonts.map((font) => document.fonts.load(font))).catch(() => undefined).then(() => { if (!disposed) paint(); });
    const observer = new ResizeObserver(paint);
    observer.observe(el);
    return () => { disposed = true; observer.disconnect(); };
  }, [webgl, drawTitle, fonts]);

  useFrame(() => {
    const s = read.current();
    if (!s) return;
    if (webgl) render.current?.(s);
    else if (fallback.current) fallback.current.style.opacity = String(s.progress * s.titleOpacity);
  });

  return (
    <div className={className} aria-hidden="true">
      {webgl ? <canvas key="paint" ref={canvas} /> : <canvas key="plain" ref={fallback} style={{ opacity: 0 }} />}
    </div>
  );
}
