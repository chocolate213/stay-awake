const reduced = matchMedia('(prefers-reduced-motion: reduce)');
let paused = reduced.matches;
const motion = document.querySelector('#motion');
const hero = document.querySelector('.hero');
const cosmos = document.querySelector('.cosmos');
const canvas = document.querySelector('#stars');
const ctx = canvas.getContext('2d');
const product = document.querySelector('.screenshot-wrap');
const pointer = { x: 0, y: 0, targetX: 0, targetY: 0, active: false, strength: 0 };
let width = 0, height = 0, points = [], frame, scrollFrame, heroVisible = true;
const clamp = (n, min, max) => Math.min(max, Math.max(min, n));

function resize() {
  width = canvas.clientWidth;
  height = canvas.clientHeight;
  const ratio = Math.min(devicePixelRatio || 1, 2);
  canvas.width = width * ratio;
  canvas.height = height * ratio;
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
  points = Array.from({ length: Math.min(180, Math.floor(width * height / 7000)) }, () => ({
    x: Math.random() * width, y: Math.random() * height,
    r: Math.random() * 1.15 + .2, p: Math.random() * Math.PI * 2,
    depth: .3 + Math.random() * .7
  }));
  restart();
  queueScroll();
}

function draw(t) {
  ctx.clearRect(0, 0, width, height);
  pointer.x += (pointer.targetX - pointer.x) * .065;
  pointer.y += (pointer.targetY - pointer.y) * .065;
  pointer.strength += ((pointer.active && !paused ? 1 : 0) - pointer.strength) * .07;
  const strength = paused ? 0 : pointer.strength;
  if (strength > .01) {
    const glow = ctx.createRadialGradient(pointer.x, pointer.y, 0, pointer.x, pointer.y, 230);
    glow.addColorStop(0, `rgba(114,155,245,${strength * .12})`);
    glow.addColorStop(1, 'rgba(114,155,245,0)');
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, width, height);
  }
  const nearby = [];
  for (const p of points) {
    let x = p.x + (pointer.x - width / 2) * .035 * p.depth * strength;
    let y = p.y + (pointer.y - height / 2) * .035 * p.depth * strength;
    const distance = Math.hypot(x - pointer.x, y - pointer.y);
    const proximity = Math.max(0, 1 - distance / 190) * strength;
    // A gentle attraction gives nearby stars depth without obscuring the copy.
    x += (pointer.x - x) * proximity * .09;
    y += (pointer.y - y) * proximity * .09;
    ctx.beginPath();
    ctx.arc(x, y, p.r + proximity * 1.2, 0, Math.PI * 2);
    ctx.fillStyle = `rgba(181,205,255,${.15 + (Math.sin(t * .0005 + p.p) + 1) * .22 + proximity * .4})`;
    ctx.fill();
    if (proximity > .1) nearby.push({ x, y, proximity });
  }
  for (let i = 0; i < nearby.length; i++) {
    for (let j = i + 1; j < nearby.length; j++) {
      const a = nearby[i], b = nearby[j];
      const distance = Math.hypot(a.x - b.x, a.y - b.y);
      if (distance > 110) continue;
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y);
      ctx.strokeStyle = `rgba(154,191,255,${(1 - distance / 110) * Math.min(a.proximity, b.proximity) * .35})`;
      ctx.lineWidth = .6; ctx.stroke();
    }
  }
  if (!paused && !document.hidden && heroVisible) frame = requestAnimationFrame(draw);
}
function restart() { cancelAnimationFrame(frame); draw(0); }
function resetPointer() {
  pointer.active = false;
  cosmos.style.setProperty('--px', '0px');
  cosmos.style.setProperty('--py', '0px');
}
hero.addEventListener('pointermove', e => {
  if (paused || e.pointerType === 'touch') return;
  const bounds = hero.getBoundingClientRect();
  pointer.targetX = e.clientX - bounds.left;
  pointer.targetY = e.clientY - bounds.top;
  if (!pointer.active) { pointer.x = pointer.targetX; pointer.y = pointer.targetY; }
  pointer.active = true;
  if (innerWidth >= 1000) {
    cosmos.style.setProperty('--px', `${(pointer.targetX / width - .5) * 24}px`);
    cosmos.style.setProperty('--py', `${(pointer.targetY / height - .5) * 18}px`);
  }
});
hero.addEventListener('pointerleave', resetPointer);

// Native scrolling stays in control; visual progress is sampled once per frame.
function scrollEffects() {
  scrollFrame = null;
  const box = hero.getBoundingClientRect();
  const progress = paused ? 0 : clamp(-box.top / box.height, 0, 1);
  hero.style.setProperty('--scroll-lift', `${progress * -75}px`);
  hero.style.setProperty('--scroll-opacity', String(1 - progress * .65));
  // Layout offsets exclude the animated transform, preventing feedback while scrolling.
  let productTop = 0;
  for (let element = product; element; element = element.offsetParent) productTop += element.offsetTop;
  const reveal = paused ? 1 : clamp((innerHeight - (productTop - scrollY)) / (innerHeight * .85), 0, 1);
  product.style.setProperty('--product-scale', String(.9 + .1 * reveal));
  product.style.setProperty('--product-tilt', `${(1 - reveal) * 9}deg`);
}
function queueScroll() { if (!scrollFrame) scrollFrame = requestAnimationFrame(scrollEffects); }
window.addEventListener('scroll', queueScroll, { passive: true });
const revealTargets = document.querySelectorAll('.manifesto > *, .features article, .product-heading > *, .install > *, .honest-note');
const revealObserver = new IntersectionObserver(entries => {
  for (const entry of entries) {
    if (entry.isIntersecting) { entry.target.classList.add('revealed'); revealObserver.unobserve(entry.target); }
  }
}, { threshold: .08 });
for (const element of revealTargets) {
  element.classList.add('scroll-reveal');
  revealObserver.observe(element);
}
new IntersectionObserver(entries => {
  heroVisible = entries[0].isIntersecting;
  restart();
}).observe(hero);
function updateMotion() {
  document.body.classList.toggle('paused', paused);
  motion.textContent = paused ? 'Resume motion' : 'Pause motion';
  motion.setAttribute('aria-pressed', String(paused));
  if (paused) resetPointer();
  restart(); queueScroll();
}
motion.addEventListener('click', () => { paused = !paused; updateMotion(); });
reduced.addEventListener('change', e => { paused = e.matches; updateMotion(); });
document.addEventListener('visibilitychange', updateMotion);
window.addEventListener('resize', resize);
resize(); updateMotion();
let end=Date.now()+7200000,total=7200;function tick(){const n=Math.max(0,Math.ceil((end-Date.now())/1000));document.querySelector('#timer').textContent=[Math.floor(n/3600),Math.floor(n%3600/60),n%60].map(v=>String(v).padStart(2,'0')).join(':');document.querySelector('#progress').style.width=`${n/total*100}%`;if(!n)document.querySelector('#session-state').textContent='Session complete';}setInterval(tick,1000);tick();document.querySelector('#extend').addEventListener('click',()=>{end=Math.max(end,Date.now())+1800000;total=Math.ceil((end-Date.now())/1000);tick();});
const tasks=['Running the test suite...','Building your next idea...','Working through the details...','Making steady progress...'];let taskIndex=0;setInterval(()=>{if(!paused&&!document.hidden)document.querySelector('#agent-task').textContent=tasks[++taskIndex%tasks.length];},4200);
document.querySelector('#copy').addEventListener('click',async()=>{const prompt='Install Stay Awake on my Mac. Read and follow the For AI Agents section at https://github.com/chocolate213/stay-awake#for-ai-agents. Verify the download checksum and app signature before installation.';const status=document.querySelector('#copy-status');try{await navigator.clipboard.writeText(prompt);status.textContent='Copied. Paste it into your local agent.';}catch{status.textContent='Copy this prompt: '+prompt;}});
