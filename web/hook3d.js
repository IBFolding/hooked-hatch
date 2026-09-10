/**
 * HOOKED — 3D hero hook.
 *
 * A machined steel hook hanging in the dark, swaying like it is suspended in
 * water, lit by a hard key and an acid-green rim. Built as real geometry (torus
 * eye, swept tube, forged barb) rather than an extruded flat SVG, so it reads as
 * an object rather than a sticker.
 *
 * Progressive enhancement: the page ships the SVG mark and this only replaces it
 * once three.js has loaded and a WebGL context actually exists. Honours
 * prefers-reduced-motion by rendering a single still frame.
 */
(() => {
  "use strict";

  const MOUNT_ID = "hero-hook-3d";
  const SVG_SELECTOR = "img.hero-hook";
  const THREE_URL = "https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js";

  const ACID = 0xb9ff2c;
  const BONE = 0xe9eadf;

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const mount = document.getElementById(MOUNT_ID);
  const svg = document.querySelector(SVG_SELECTOR);
  if (!mount) return;

  // Don't pay for 600KB on a phone, where the mark is hidden anyway.
  if (window.innerWidth < 851) return;

  function webglAvailable() {
    try {
      const c = document.createElement("canvas");
      return !!(window.WebGLRenderingContext && (c.getContext("webgl") || c.getContext("experimental-webgl")));
    } catch (_) {
      return false;
    }
  }
  if (!webglAvailable()) return;

  function load(src) {
    return new Promise((res, rej) => {
      const s = document.createElement("script");
      s.src = src;
      s.async = true;
      s.onload = res;
      s.onerror = () => rej(new Error("three.js failed to load"));
      document.head.appendChild(s);
    });
  }

  /** The hook's centre-line, swept as a tube. */
  function hookCurve(THREE) {
    const pts = [];
    const shankX = 0.34;
    const bendY = 0.10;
    const r = 0.34;

    // shank, top to bottom
    for (let i = 0; i <= 8; i++) {
      pts.push(new THREE.Vector3(shankX, 1.16 - (1.06 * i) / 8, 0));
    }
    // the bend: a half turn under the shank
    for (let i = 1; i <= 22; i++) {
      const a = (Math.PI * i) / 22; // 0 -> PI
      pts.push(new THREE.Vector3(Math.cos(a) * r, bendY - Math.sin(a) * r, 0));
    }
    // the point, angled away from the shank so it never reads as a letter J
    for (let i = 1; i <= 8; i++) {
      const t = i / 8;
      pts.push(new THREE.Vector3(-r - 0.13 * t, bendY + 0.78 * t, 0));
    }
    return new THREE.CatmullRomCurve3(pts, false, "catmullrom", 0.4);
  }

  function build(THREE) {
    const w = mount.clientWidth || 520;
    const h = mount.clientHeight || 620;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(34, w / h, 0.1, 100);
    camera.position.set(0, 0.02, 5.5);

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    mount.appendChild(renderer.domElement);

    const steel = new THREE.MeshStandardMaterial({
      color: 0x9aa39a,
      metalness: 0.94,
      roughness: 0.34
    });

    // Everything hangs off this pivot, so the sway rotates about the eye.
    const pivot = new THREE.Group();
    pivot.position.y = 1.34;
    scene.add(pivot);

    const hook = new THREE.Group();
    hook.position.set(0.04, -1.34, 0);
    pivot.add(hook);

    // eye
    const eye = new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.072, 20, 48), steel);
    eye.position.set(0.34, 1.34, 0);
    hook.add(eye);

    // shank + bend + point
    const body = new THREE.Mesh(new THREE.TubeGeometry(hookCurve(THREE), 220, 0.075, 18, false), steel);
    hook.add(body);

    // forged barb at the tip
    const barb = new THREE.Mesh(new THREE.ConeGeometry(0.093, 0.34, 22), steel);
    barb.position.set(-0.485, 0.98, 0);
    barb.rotation.z = -0.155;
    hook.add(barb);

    // --- light: hard key, acid rim, cold fill -----------------------------
    scene.add(new THREE.AmbientLight(0x2a3128, 1.0));

    const key = new THREE.DirectionalLight(BONE, 2.1);
    key.position.set(2.6, 3.2, 2.4);
    scene.add(key);

    const rim = new THREE.DirectionalLight(ACID, 2.6);
    rim.position.set(-3.0, 0.6, -1.6);
    scene.add(rim);

    const glow = new THREE.PointLight(ACID, 1.5, 7);
    glow.position.set(-1.5, -0.7, 1.9);
    scene.add(glow);

    const fill = new THREE.DirectionalLight(0x5d6b5a, 0.5);
    fill.position.set(-1.4, -2.2, 1.2);
    scene.add(fill);

    // --- motion -----------------------------------------------------------
    const pointer = { x: 0, y: 0 };
    const target = { x: 0, y: 0 };
    if (!reduced) {
      window.addEventListener("pointermove", (e) => {
        target.x = (e.clientX / window.innerWidth) * 2 - 1;
        target.y = (e.clientY / window.innerHeight) * 2 - 1;
      }, { passive: true });
    }

    function resize() {
      const nw = mount.clientWidth || w;
      const nh = mount.clientHeight || h;
      camera.aspect = nw / nh;
      camera.updateProjectionMatrix();
      renderer.setSize(nw, nh);
    }
    window.addEventListener("resize", resize, { passive: true });

    let raf = 0;
    const start = performance.now();

    function frame(now) {
      const t = (now - start) / 1000;

      // Pendulum: two detuned sines so the sway never looks looped.
      const sway = Math.sin(t * 0.62) * 0.085 + Math.sin(t * 0.27) * 0.045;
      pointer.x += (target.x - pointer.x) * 0.045;
      pointer.y += (target.y - pointer.y) * 0.045;

      pivot.rotation.z = sway + pointer.x * 0.10;
      pivot.rotation.y = Math.sin(t * 0.34) * 0.18 + pointer.x * 0.26;
      pivot.rotation.x = pointer.y * 0.16;
      hook.position.y = -1.34 + Math.sin(t * 0.5) * 0.045;

      renderer.render(scene, camera);
      raf = requestAnimationFrame(frame);
    }

    if (reduced) {
      pivot.rotation.y = 0.22;
      renderer.render(scene, camera);
    } else {
      raf = requestAnimationFrame(frame);
    }

    // Stop burning frames when the hero is off screen or the tab is hidden.
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (en.isIntersecting && !raf && !reduced) raf = requestAnimationFrame(frame);
        else if (!en.isIntersecting && raf) { cancelAnimationFrame(raf); raf = 0; }
      });
    }, { threshold: 0.01 });
    io.observe(mount);

    document.addEventListener("visibilitychange", () => {
      if (document.hidden && raf) { cancelAnimationFrame(raf); raf = 0; }
      else if (!document.hidden && !raf && !reduced) raf = requestAnimationFrame(frame);
    });

    // Only now retire the flat mark, so there is never an empty gap.
    mount.classList.add("ready");
    if (svg) svg.style.display = "none";
  }

  load(THREE_URL)
    .then(() => build(window.THREE))
    .catch((e) => console.warn("hero hook staying 2D:", e.message));
})();
