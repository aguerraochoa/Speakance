"use client";

import { useEffect, useRef } from "react";

type Particle = {
  x: number;
  y: number;
  vx: number;
  vy: number;
  r: number;
  alpha: number;
};

const PARTICLE_COUNT_DESKTOP = 34;
const PARTICLE_COUNT_MOBILE = 20;

export default function AmbientParticles() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let raf = 0;
    let width = 0;
    let height = 0;
    let dpr = 1;
    let particles: Particle[] = [];

    const randomRange = (min: number, max: number) => Math.random() * (max - min) + min;

    const makeParticle = (): Particle => ({
      x: Math.random() * width,
      y: Math.random() * height,
      vx: randomRange(-0.08, 0.08),
      vy: randomRange(-0.06, 0.06),
      r: randomRange(1.2, 4.8),
      alpha: randomRange(0.18, 0.55)
    });

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      width = rect.width;
      height = rect.height;
      dpr = Math.min(window.devicePixelRatio || 1, 2);

      canvas.width = Math.max(1, Math.floor(width * dpr));
      canvas.height = Math.max(1, Math.floor(height * dpr));
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      const targetCount = width < 700 ? PARTICLE_COUNT_MOBILE : PARTICLE_COUNT_DESKTOP;
      particles = Array.from({ length: targetCount }, makeParticle);
      drawFrame();
    };

    const drawFrame = () => {
      ctx.clearRect(0, 0, width, height);

      // soft background haze spots (depth, not a gradient page background)
      const hazes = [
        { x: width * 0.15, y: height * 0.2, r: 120, a: 0.06 },
        { x: width * 0.82, y: height * 0.16, r: 160, a: 0.08 },
        { x: width * 0.74, y: height * 0.78, r: 140, a: 0.05 }
      ];
      for (const haze of hazes) {
        const g = ctx.createRadialGradient(haze.x, haze.y, 0, haze.x, haze.y, haze.r);
        g.addColorStop(0, `rgba(68, 89, 252, ${haze.a})`);
        g.addColorStop(0.55, `rgba(42, 164, 232, ${haze.a * 0.55})`);
        g.addColorStop(1, "rgba(255,255,255,0)");
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(haze.x, haze.y, haze.r, 0, Math.PI * 2);
        ctx.fill();
      }

      // faint connecting lines for nearby particles (very subtle)
      for (let i = 0; i < particles.length; i += 1) {
        const a = particles[i];
        for (let j = i + 1; j < particles.length; j += 1) {
          const b = particles[j];
          const dx = a.x - b.x;
          const dy = a.y - b.y;
          const dist = Math.hypot(dx, dy);
          if (dist > 120) continue;
          const alpha = (1 - dist / 120) * 0.08;
          ctx.strokeStyle = `rgba(70, 92, 255, ${alpha.toFixed(3)})`;
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.moveTo(a.x, a.y);
          ctx.lineTo(b.x, b.y);
          ctx.stroke();
        }
      }

      // particles with a soft glow + core
      for (const p of particles) {
        const glow = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.r * 5.5);
        glow.addColorStop(0, `rgba(68, 89, 252, ${(p.alpha * 0.65).toFixed(3)})`);
        glow.addColorStop(0.4, `rgba(42, 164, 232, ${(p.alpha * 0.28).toFixed(3)})`);
        glow.addColorStop(1, "rgba(255,255,255,0)");
        ctx.fillStyle = glow;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r * 5.5, 0, Math.PI * 2);
        ctx.fill();

        ctx.fillStyle = `rgba(92, 112, 255, ${(p.alpha * 0.9).toFixed(3)})`;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fill();
      }
    };

    const tick = () => {
      for (const p of particles) {
        p.x += p.vx;
        p.y += p.vy;

        if (p.x < -20) p.x = width + 20;
        if (p.x > width + 20) p.x = -20;
        if (p.y < -20) p.y = height + 20;
        if (p.y > height + 20) p.y = -20;
      }

      drawFrame();
      raf = window.requestAnimationFrame(tick);
    };

    resize();
    window.addEventListener("resize", resize);

    if (!reducedMotion) {
      raf = window.requestAnimationFrame(tick);
    }

    return () => {
      window.removeEventListener("resize", resize);
      if (raf) window.cancelAnimationFrame(raf);
    };
  }, []);

  return <canvas ref={canvasRef} className="ambientCanvas" aria-hidden="true" />;
}
