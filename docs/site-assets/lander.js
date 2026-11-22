// Copy buttons.
document.querySelectorAll('[data-copy]').forEach(button => {
  button.addEventListener('click', async () => {
    const status = document.getElementById('copy-status');
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      button.textContent = 'Copied';
      status.textContent = 'Command copied to clipboard.';
      setTimeout(() => { button.textContent = 'Copy'; }, 1800);
    } catch {
      button.textContent = 'Select text';
      status.textContent = 'Copy unavailable. Select and copy the command below.';
    }
  });
});

// The hero island: idle, wings while "playing", the cursor hovers and the island opens on Music, then on Calendar,
// then a small banner when a device connects.
// Like the app, nothing runs while nobody is looking: the loop stops when the drawing is off screen,
// the tab is hidden, or the visitor asked for reduced motion (then it rests open, and the buttons still work).
(() => {
  const screen = document.getElementById('screen');
  if (!screen) return;
  const buttons = [...document.querySelectorAll('[data-show]')];
  const note = document.getElementById('stage-note');
  const fill = document.getElementById('prog-fill');
  const tEl = document.getElementById('t-el');
  const tRem = document.getElementById('t-rem');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const DURATION = 217;
  let position = 84;
  let timer = 0, ticker = 0, step = 0;
  let visible = true, manual = false, hovering = false, before = 'open';

  const notes = {
    idle: 'Idle: flush with the notch, nothing drawn.',
    live: 'Spotify is playing: the wings are out.',
    open: 'Hovered: the island opens on Music.',
    calendar: 'The Calendar tab: today, and what\u2019s due.',
    peek: 'AirPods connect: a banner, then it folds away.'
  };
  const fmt = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
  function paintTime() {
    fill.style.width = `${(position / DURATION) * 100}%`;
    tEl.textContent = fmt(position);
    tRem.textContent = `-${fmt(DURATION - position)}`;
  }
  // The progress bar ticks once a second, and only while the island is open (as in the app).
  function setTicking(on) {
    clearInterval(ticker);
    ticker = 0;
    if (on && !reduced.matches) ticker = setInterval(() => { position = (position + 1) % DURATION; paintTime(); }, 1000);
  }
  function show(state, cursor = 'none') {
    screen.dataset.state = state;
    screen.dataset.cursor = cursor;
    buttons.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.show === state)));
    note.textContent = notes[state];
    setTicking(state === 'open' && visible);
  }

  // [state, cursor, how long to hold it]
  const script = [
    ['idle', 'none', 2000],
    ['live', 'none', 2400],
    ['live', 'near', 1000],
    ['open', 'on', 4200],
    ['calendar', 'on', 4600],
    ['live', 'near', 900],
    ['live', 'none', 1200],
    ['peek', 'none', 3000],
    ['idle', 'none', 1400]
  ];
  function run() {
    clearTimeout(timer);
    if (manual || hovering || !visible || reduced.matches || document.hidden) return;
    const [state, cursor, hold] = script[step];
    show(state, cursor);
    step = (step + 1) % script.length;
    timer = setTimeout(run, hold);
  }
  function stop() { clearTimeout(timer); setTicking(false); }

  buttons.forEach(b => b.addEventListener('click', () => {
    manual = true;
    stop();
    show(b.dataset.show);
  }));
  // Hover the drawn notch to open it, like the real one.
  const island = document.getElementById('island');
  island.addEventListener('pointerenter', () => { before = screen.dataset.state; hovering = true; stop(); show('open'); });
  island.addEventListener('pointerleave', () => {
    hovering = false;
    if (manual || reduced.matches) { show(manual ? before : 'open'); return; }
    show('live');
    step = 6;
    timer = setTimeout(run, 900);
  });

  new IntersectionObserver(entries => {
    visible = entries[0].isIntersecting;
    if (visible) run(); else stop();
  }).observe(screen);
  document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); else run(); });
  reduced.addEventListener?.('change', () => { if (reduced.matches) { screen.classList.add('still'); stop(); show('open'); } else { screen.classList.remove('still'); run(); } });

  paintTime();
  if (reduced.matches) { screen.classList.add('still'); show('open'); } else run();
})();
