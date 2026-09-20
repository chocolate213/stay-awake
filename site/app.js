const reduced = matchMedia('(prefers-reduced-motion: reduce)');
let manuallyPaused = false;
let paused = reduced.matches;
const motion = document.querySelector('#motion');
const hero = document.querySelector('.hero');
const cosmos = document.querySelector('.cosmos');
const canvas = document.querySelector('#stars');
const ctx = canvas.getContext('2d');
const demo = document.querySelector('.night-demo');
const pointer = { x: 0, y: 0, targetX: 0, targetY: 0, active: false, strength: 0 };
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
let width = 0, height = 0, points = [], frame, scrollFrame, heroVisible = true;

function draw(time) {
  if (!ctx) return;
  ctx.clearRect(0, 0, width, height);
  pointer.x += (pointer.targetX - pointer.x) * .065;
  pointer.y += (pointer.targetY - pointer.y) * .065;
  pointer.strength += ((pointer.active && !paused ? 1 : 0) - pointer.strength) * .07;
  const strength = paused ? 0 : pointer.strength;
  if (strength > .01) {
    const glow = ctx.createRadialGradient(pointer.x, pointer.y, 0, pointer.x, pointer.y, 240);
    glow.addColorStop(0, `rgba(118,151,223,${strength * .12})`);
    glow.addColorStop(1, 'rgba(118,151,223,0)');
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, width, height);
  }
  const nearby = [];
  for (const star of points) {
    let x = star.x + (pointer.x - width / 2) * .04 * star.depth * strength;
    let y = star.y + (pointer.y - height / 2) * .04 * star.depth * strength;
    const distance = Math.hypot(x - pointer.x, y - pointer.y);
    const proximity = Math.max(0, 1 - distance / 180) * strength;
    x += (pointer.x - x) * proximity * .08;
    y += (pointer.y - y) * proximity * .08;
    ctx.beginPath();
    ctx.arc(x, y, star.r + proximity, 0, Math.PI * 2);
    ctx.fillStyle = `rgba(182,204,247,${.1 + (Math.sin(time * .00045 + star.phase) + 1) * .16 + proximity * .45})`;
    ctx.fill();
    if (proximity > .1) nearby.push({ x, y, proximity });
  }
  for (let i = 0; i < nearby.length; i++) {
    for (let j = i + 1; j < nearby.length; j++) {
      const a = nearby[i], b = nearby[j];
      const distance = Math.hypot(a.x - b.x, a.y - b.y);
      if (distance > 105) continue;
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y);
      ctx.strokeStyle = `rgba(159,191,249,${(1 - distance / 105) * Math.min(a.proximity, b.proximity) * .4})`;
      ctx.lineWidth = .6; ctx.stroke();
    }
  }
  // A short, occasional meteor stays behind the content.
  const meteor = (time % 14000) / 1600;
  if (!paused && meteor < 1 && width > 600) {
    const x = width * .61 + meteor * 270, y = height * .09 + meteor * 145;
    const trail = ctx.createLinearGradient(x - 105, y - 56, x, y);
    trail.addColorStop(0, 'rgba(166,195,255,0)');
    trail.addColorStop(1, `rgba(199,216,255,${Math.sin(meteor * Math.PI) * .5})`);
    ctx.strokeStyle = trail; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(x - 105, y - 56); ctx.lineTo(x, y); ctx.stroke();
  }
  if (!paused && !document.hidden && heroVisible) frame = requestAnimationFrame(draw);
}
function restart() {
  cancelAnimationFrame(frame);
  draw(performance.now());
}
function resize() {
  width = canvas.clientWidth; height = canvas.clientHeight;
  if (ctx) {
    const ratio = Math.min(devicePixelRatio || 1, 2);
    canvas.width = width * ratio; canvas.height = height * ratio;
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    points = Array.from({ length: Math.min(170, Math.floor(width * height / 6500)) }, () => ({
      x: Math.random() * width, y: Math.random() * height,
      r: Math.random() * .9 + .2, phase: Math.random() * Math.PI * 2,
      depth: .25 + Math.random() * .75
    }));
  }
  restart(); queueScroll();
}
function resetPointer() {
  pointer.active = false;
  cosmos.style.setProperty('--px', '0px'); cosmos.style.setProperty('--py', '0px');
}
hero.addEventListener('pointermove', event => {
  if (paused || event.pointerType === 'touch') return;
  const bounds = hero.getBoundingClientRect();
  pointer.targetX = event.clientX - bounds.left;
  pointer.targetY = event.clientY - bounds.top;
  if (!pointer.active) { pointer.x = pointer.targetX; pointer.y = pointer.targetY; }
  pointer.active = true;
  if (innerWidth > 850) {
    cosmos.style.setProperty('--px', `${(pointer.targetX / width - .5) * 22}px`);
    cosmos.style.setProperty('--py', `${(pointer.targetY / height - .5) * 16}px`);
  }
});
hero.addEventListener('pointerleave', resetPointer);
for (const card of document.querySelectorAll('.feature-card')) {
  card.addEventListener('pointermove', event => {
    if (paused || event.pointerType === 'touch') return;
    const bounds = card.getBoundingClientRect();
    card.style.setProperty('--spot-x', `${event.clientX - bounds.left}px`);
    card.style.setProperty('--spot-y', `${event.clientY - bounds.top}px`);
  });
  card.addEventListener('pointerleave', () => {
    card.style.removeProperty('--spot-x'); card.style.removeProperty('--spot-y');
  });
}
function layoutTop(element) {
  let top = 0;
  for (; element; element = element.offsetParent) top += element.offsetTop;
  return top;
}
const manifestoLines = document.querySelectorAll('.manifesto-title > span');
function scrollEffects() {
  scrollFrame = null;
  const bounds = hero.getBoundingClientRect();
  const progress = paused ? 0 : clamp(-bounds.top / bounds.height, 0, 1);
  hero.style.setProperty('--scroll-lift', `${progress * -65}px`);
  hero.style.setProperty('--scroll-opacity', String(1 - progress * .6));
  const reveal = paused ? 1 : clamp((innerHeight - (layoutTop(demo) - scrollY)) / (innerHeight * .8), 0, 1);
  demo.style.setProperty('--demo-scale', String(.95 + .05 * reveal));
  demo.style.setProperty('--demo-tilt', `${(1 - reveal) * 5}deg`);
  for (const line of manifestoLines) {
    const amount = paused ? 1 : clamp((innerHeight * .88 - line.getBoundingClientRect().top) / (innerHeight * .32), 0, 1);
    line.style.setProperty('--word-opacity', String(.22 + .78 * amount));
  }
  const maxScroll = document.documentElement.scrollHeight - innerHeight;
  document.querySelector('.reading-progress').style.transform = `scaleX(${maxScroll > 0 ? clamp(scrollY / maxScroll, 0, 1) : 0})`;
}
function queueScroll() { if (!scrollFrame) scrollFrame = requestAnimationFrame(scrollEffects); }
addEventListener('scroll', queueScroll, { passive: true });
if ('IntersectionObserver' in window) {
  document.documentElement.classList.add('motion-ready');
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) if (entry.isIntersecting) {
      entry.target.classList.add('revealed'); observer.unobserve(entry.target);
    }
  }, { threshold: .08 });
  document.querySelectorAll('.reveal').forEach(element => observer.observe(element));
  new IntersectionObserver(entries => { heroVisible = entries[0].isIntersecting; restart(); }).observe(hero);
}
function updateMotion() {
  paused = manuallyPaused || reduced.matches;
  document.body.classList.toggle('paused', paused);
  motion.textContent = reduced.matches ? 'Reduced motion' : paused ? 'Resume motion' : 'Pause motion';
  motion.disabled = reduced.matches;
  motion.setAttribute('aria-pressed', String(paused));
  if (paused) resetPointer();
  restart(); queueScroll();
}
motion.addEventListener('click', () => { manuallyPaused = !manuallyPaused; updateMotion(); });
reduced.addEventListener('change', updateMotion);
document.addEventListener('visibilitychange', () => { restart(); tick(); });
addEventListener('resize', resize);
resize(); updateMotion();

let mode = 'timed';
let end = Date.now() + 7200000;
let total = 7200;
const timer = document.querySelector('#timer');
const unit = document.querySelector('#timer-unit');
const state = document.querySelector('#session-state');
const extend = document.querySelector('#extend');
const task = document.querySelector('#agent-task');
const tasks = ['Running the test suite', 'Building your next idea', 'Working through the details', 'Making steady progress'];
let taskIndex = 0;
function tick() {
  if (mode !== 'timed') return;
  const remaining = Math.max(0, Math.ceil((end - Date.now()) / 1000));
  if (!remaining) { setSession('off'); return; }
  timer.textContent = [Math.floor(remaining / 3600), Math.floor(remaining % 3600 / 60), remaining % 60].map(n => String(n).padStart(2, '0')).join(':');
  document.querySelector('#progress').style.width = `${clamp(remaining / total, 0, 1) * 100}%`;
}
function setSession(value) {
  mode = value === 'off' ? 'off' : value === 'on' ? 'on' : 'timed';
  demo.dataset.mode = mode;
  document.querySelectorAll('[data-session]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.session === value)));
  extend.disabled = mode !== 'timed';
  const off = mode === 'off';
  document.querySelector('#session-caption').textContent = off ? 'Back to your Mac’s normal sleep settings.' : mode === 'on' ? 'Keep going until you say stop.' : 'A little longer. A lot more done.';
  unit.textContent = mode === 'timed' ? 'remaining' : off ? 'session stopped' : 'until stopped';
  state.replaceChildren();
  if (!off) {
    const dot = document.createElement('i'); dot.className = 'live-dot'; state.append(dot);
  }
  state.append(document.createTextNode(off ? 'Idle sleep allowed' : 'Preventing idle sleep'));
  document.querySelector('#console-status').textContent = off ? 'WAKE LOCK OFF' : 'RUNNING';
  document.querySelector('#console-footer').textContent = off ? 'Your Mac may now enter idle sleep.' : 'Room for the next iteration.';
  task.textContent = off ? 'Sleep follows your system settings' : tasks[taskIndex];
  if (mode === 'timed') {
    total = Number(value) * 3600; end = Date.now() + total * 1000; tick();
  } else {
    timer.textContent = off ? 'Off' : 'On';
    document.querySelector('#progress').style.width = off ? '0%' : '100%';
  }
}
document.querySelectorAll('[data-session]').forEach(button => button.addEventListener('click', () => setSession(button.dataset.session)));
extend.addEventListener('click', () => {
  if (mode !== 'timed') return;
  end = Math.max(end, Date.now()) + 1800000; total += 1800;
  document.querySelectorAll('[data-session]').forEach(button => button.setAttribute('aria-pressed', 'false'));
  document.querySelector('#session-caption').textContent = 'Another 30 minutes for your next idea.';
  tick();
});
setInterval(tick, 1000); tick();
setInterval(() => {
  if (!paused && !document.hidden && mode !== 'off') task.textContent = tasks[++taskIndex % tasks.length];
}, 4200);

document.querySelector('#copy').addEventListener('click', async () => {
  const prompt = 'Install Stay Awake on my Mac. Read and follow the For AI Agents section at https://github.com/chocolate213/stay-awake#for-ai-agents. Verify the download checksum and app signature before installation.';
  const status = document.querySelector('#copy-status');
  try {
    await navigator.clipboard.writeText(prompt);
    status.textContent = 'Copied. Paste it into your local agent.';
  } catch {
    status.textContent = 'Copy this prompt: ' + prompt;
  }
});
