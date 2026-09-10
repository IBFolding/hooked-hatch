/**
 * PARASITE — hero organism.
 *
 * A writhing single-celled thing: a deforming core with lashing flagella, lit
 * acid-green from inside. Built from real geometry so it reads as alive rather
 * than as a logo. Same progressive-enhancement contract as the hook: the page
 * ships a static mark, and this only takes over once three.js has drawn.
 */
(() => {
  "use strict";
  const MOUNT = document.getElementById("organism");
  if (!MOUNT) return;
  if (window.innerWidth < 851) return;

  const ACID = 0xb9ff2c;
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  try {
    const c = document.createElement("canvas");
    if (!(window.WebGLRenderingContext && (c.getContext("webgl") || c.getContext("experimental-webgl")))) return;
  } catch (_) { return; }

  const load = (src) => new Promise((res, rej) => {
    const s = document.createElement("script");
    s.src = src; s.async = true; s.onload = res; s.onerror = () => rej(new Error("three.js blocked"));
    document.head.appendChild(s);
  });

  function build(THREE) {
    const w = MOUNT.clientWidth, h = MOUNT.clientHeight;
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(40, w / h, 0.1, 100);
    camera.position.set(0, 0, 6.2);

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    MOUNT.appendChild(renderer.domElement);

    const org = new THREE.Group();
    scene.add(org);

    // --- the cell body: a sphere we deform every frame so it never rests ---
    const bodyGeo = new THREE.IcosahedronGeometry(1.25, 5);
    const basePos = bodyGeo.attributes.position.array.slice();
    const body = new THREE.Mesh(
      bodyGeo,
      new THREE.MeshStandardMaterial({
        color: 0x1d2a18, emissive: ACID, emissiveIntensity: 0.22,
        metalness: 0.1, roughness: 0.55, transparent: true, opacity: 0.93
      })
    );
    org.add(body);

    // membrane: a second shell, slightly larger, wireframe — reads as cytoplasm
    const shell = new THREE.Mesh(
      new THREE.IcosahedronGeometry(1.42, 3),
      new THREE.MeshBasicMaterial({ color: ACID, wireframe: true, transparent: true, opacity: 0.13 })
    );
    org.add(shell);

    // nucleus: the bright thing inside that pulses like a heartbeat
    const nucleus = new THREE.Mesh(
      new THREE.IcosahedronGeometry(0.34, 3),
      new THREE.MeshBasicMaterial({ color: ACID })
    );
    org.add(nucleus);

    // --- flagella: tapered tendrils that lash ---
    const arms = [];
    for (let i = 0; i < 9; i++) {
      const pts = [];
      for (let j = 0; j <= 12; j++) pts.push(new THREE.Vector3(0, 0, 0));
      const curve = new THREE.CatmullRomCurve3(pts);
      const mesh = new THREE.Mesh(
        new THREE.TubeGeometry(curve, 26, 0.035, 6, false),
        new THREE.MeshStandardMaterial({
          color: 0x2b3a24, emissive: ACID, emissiveIntensity: 0.3, roughness: 0.6
        })
      );
      const dir = new THREE.Vector3(
        Math.cos(i * 2.1) * Math.sin(i * 1.3),
        Math.sin(i * 1.7),
        Math.cos(i * 0.9)
      ).normalize();
      arms.push({ mesh, curve, dir, phase: i * 0.7 });
      org.add(mesh);
    }

    scene.add(new THREE.AmbientLight(0x182015, 1.1));
    const key = new THREE.PointLight(ACID, 3.2, 12); key.position.set(0, 0, 0); scene.add(key);
    const rim = new THREE.DirectionalLight(0xe9eadf, 0.9); rim.position.set(-3, 2, 3); scene.add(rim);

    const target = { x: 0, y: 0 }, ptr = { x: 0, y: 0 };
    if (!reduced) window.addEventListener("pointermove", (e) => {
      target.x = (e.clientX / window.innerWidth) * 2 - 1;
      target.y = (e.clientY / window.innerHeight) * 2 - 1;
    }, { passive: true });

    window.addEventListener("resize", () => {
      const nw = MOUNT.clientWidth, nh = MOUNT.clientHeight;
      camera.aspect = nw / nh; camera.updateProjectionMatrix(); renderer.setSize(nw, nh);
    }, { passive: true });

    const pos = bodyGeo.attributes.position;
    let raf = 0;
    const t0 = performance.now();

    function frame(now) {
      const t = (now - t0) / 1000;

      // Deform the membrane with layered sines — cheap, and it never loops visibly.
      for (let i = 0; i < pos.count; i++) {
        const ix = i * 3;
        const x = basePos[ix], y = basePos[ix + 1], z = basePos[ix + 2];
        const d = 1
          + 0.085 * Math.sin(x * 3.1 + t * 1.6)
          + 0.070 * Math.sin(y * 2.7 - t * 1.2)
          + 0.055 * Math.sin(z * 3.9 + t * 2.1);
        pos.array[ix] = x * d; pos.array[ix + 1] = y * d; pos.array[ix + 2] = z * d;
      }
      pos.needsUpdate = true;

      // Flagella lash on their own phase.
      arms.forEach((a) => {
        const p = [];
        for (let j = 0; j <= 12; j++) {
          const s = j / 12;
          const len = 1.2 + s * 1.5;
          const wob = Math.sin(t * 2.4 + a.phase + s * 5.5) * 0.34 * s;
          p.push(new THREE.Vector3(
            a.dir.x * len + wob,
            a.dir.y * len + Math.cos(t * 2.0 + a.phase + s * 4.7) * 0.34 * s,
            a.dir.z * len + wob * 0.5
          ));
        }
        a.mesh.geometry.dispose();
        a.mesh.geometry = new THREE.TubeGeometry(
          new THREE.CatmullRomCurve3(p), 24, 0.038 * (1 - 0.55), 6, false
        );
      });

      const beat = 1 + Math.sin(t * 2.6) * 0.13 + Math.sin(t * 6.1) * 0.04;
      nucleus.scale.setScalar(beat);
      key.intensity = 2.6 + Math.sin(t * 2.6) * 1.0;
      shell.rotation.y = t * 0.14; shell.rotation.x = t * 0.09;

      ptr.x += (target.x - ptr.x) * 0.04; ptr.y += (target.y - ptr.y) * 0.04;
      org.rotation.y = t * 0.18 + ptr.x * 0.5;
      org.rotation.x = Math.sin(t * 0.4) * 0.16 + ptr.y * 0.3;

      renderer.render(scene, camera);
      raf = requestAnimationFrame(frame);
    }

    if (reduced) { renderer.render(scene, camera); }
    else raf = requestAnimationFrame(frame);

    new IntersectionObserver((es) => es.forEach((e) => {
      if (e.isIntersecting && !raf && !reduced) raf = requestAnimationFrame(frame);
      else if (!e.isIntersecting && raf) { cancelAnimationFrame(raf); raf = 0; }
    }), { threshold: 0.01 }).observe(MOUNT);

    document.addEventListener("visibilitychange", () => {
      if (document.hidden && raf) { cancelAnimationFrame(raf); raf = 0; }
      else if (!document.hidden && !raf && !reduced) raf = requestAnimationFrame(frame);
    });

    MOUNT.classList.add("ready");
  }

  load("https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js")
    .then(() => build(window.THREE))
    .catch((e) => console.warn("organism staying 2D:", e.message));
})();
