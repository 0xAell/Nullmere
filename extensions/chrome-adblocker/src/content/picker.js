// The element picker, put into the page in front when the popup asks for
// it, and gone when it is done. The pointer shows what it is over; a click
// chooses it; a few ways of naming it are offered, each with how many
// elements on the page it names, the chosen one's shown as it would be
// hidden; Hide it keeps it as one of your own filters for this site, and
// it is hidden at once. Wider chooses what holds it. Escape, or Cancel,
// stops, and nothing is kept.
//
// A classic script, run in the extension's own world: the page sees only
// the picker's element while it is there.

(() => {
  if (globalThis.stillwaterPicker) return;
  globalThis.stillwaterPicker = true;

  const host = document.createElement('div');
  host.dataset.stillwaterPicker = '';
  // Open, so the browser tests can press its buttons; it is there only while one picks.
  const root = host.attachShadow({ mode: 'open' });
  root.innerHTML = `
    <style>
      :host { all: initial; }
      .box { position: fixed; pointer-events: none; z-index: 2147483646; border: 2px solid #9fc0ef; background: rgb(159 192 239 / 0.18); border-radius: 3px; }
      .box.match { border-style: dashed; background: rgb(159 192 239 / 0.08); }
      .panel { position: fixed; right: 16px; bottom: 16px; z-index: 2147483647; width: 340px; box-sizing: border-box; padding: 16px 18px;
        background: #0b1220; color: #e4eaf2; border: 1px solid #2a3a58; border-radius: 12px; box-shadow: 0 12px 40px rgb(0 0 0 / 0.5);
        font: 13px/1.5 -apple-system, system-ui, sans-serif; }
      h2 { margin: 0 0 6px; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; font-weight: 500; color: #9fb3d1; }
      p { margin: 0 0 10px; color: #b6c3d6; }
      label { display: flex; gap: 8px; align-items: baseline; padding: 4px 0; cursor: pointer; }
      code { font: 12px ui-monospace, Menlo, monospace; color: #e4eaf2; overflow-wrap: anywhere; }
      input { accent-color: #9fc0ef; margin: 0; }
      .count { color: #8da0bd; white-space: nowrap; margin-left: auto; padding-left: 8px; }
      .acts { display: flex; gap: 8px; justify-content: flex-end; margin-top: 12px; }
      button { font: 11px -apple-system, system-ui, sans-serif; letter-spacing: 0.14em; text-transform: uppercase; padding: 7px 12px;
        border-radius: 999px; border: 1px solid #2a3a58; background: transparent; color: #e4eaf2; cursor: pointer; }
      button.go { background: #1b2a44; border-color: #4a6a9a; }
      button:focus-visible { outline: 2px solid #9fc0ef; outline-offset: 2px; }
    </style>
    <div class="panel" role="dialog" aria-label="Hide an element">
      <h2>Hide an element</h2>
      <p class="said">Point at what you would hide, and click it. Escape stops.</p>
      <div class="ways" role="radiogroup" aria-label="Ways of naming it"></div>
      <div class="acts" hidden>
        <button type="button" class="wider">Wider</button>
        <button type="button" class="cancel">Cancel</button>
        <button type="button" class="go">Hide it</button>
      </div>
    </div>`;
  const said = root.querySelector('.said');
  const ways = root.querySelector('.ways');
  const acts = root.querySelector('.acts');
  const boxes = [];
  (document.body ?? document.documentElement).appendChild(host);

  let over = null;
  let chosen = null;
  let options = [];

  /** Boxes drawn over the elements given, the first solid, the rest dashed. */
  function outline(elements) {
    while (boxes.length) boxes.pop().remove();
    for (const [index, element] of elements.slice(0, 60).entries()) {
      const rect = element.getBoundingClientRect();
      const box = document.createElement('div');
      box.className = index ? 'box match' : 'box';
      Object.assign(box.style, { left: `${rect.left}px`, top: `${rect.top}px`, width: `${rect.width}px`, height: `${rect.height}px` });
      root.appendChild(box);
      boxes.push(box);
    }
  }

  const named = (name) => /^[A-Za-z_][\w-]*$/.test(name) && !/\d{4,}/.test(name) && name.length <= 40;

  /** Where an element stands under its parent, as a selector that needs only the tags. */
  function step(element) {
    const tag = element.localName;
    const same = element.parentElement ? [...element.parentElement.children].filter((child) => child.localName === tag) : [element];
    return same.length > 1 ? `${tag}:nth-of-type(${same.indexOf(element) + 1})` : tag;
  }

  /** Ways of naming an element, the plainest first: by id, by its classes, by where it stands. */
  function waysOf(element) {
    const found = [];
    if (element.id && named(element.id)) found.push(`#${CSS.escape(element.id)}`);
    const classes = [...element.classList].filter(named);
    if (classes.length) found.push(`${element.localName}${classes.map((name) => `.${CSS.escape(name)}`).join('')}`);
    if (classes.length > 1) found.push(`.${CSS.escape(classes[0])}`);
    // Where it stands: from the nearest holder with an id, or from the body.
    const path = [];
    for (let at = element; at && at !== document.body && at !== document.documentElement; at = at.parentElement) {
      if (at !== element && at.id && named(at.id)) {
        path.unshift(`#${CSS.escape(at.id)}`);
        break;
      }
      path.unshift(step(at));
    }
    if (path.length) found.push(path.join(' > '));
    return [...new Set(found)].filter((selector) => {
      try {
        return element.matches(selector);
      } catch {
        return false;
      }
    });
  }

  const matching = (selector) => [...document.querySelectorAll(selector)].filter((element) => !host.contains(element));

  /** The ways of naming the element chosen, with how many each names; the first chosen. */
  function offer(element) {
    chosen = element;
    options = waysOf(element);
    ways.replaceChildren(
      ...options.map((selector, index) => {
        const label = document.createElement('label');
        const radio = Object.assign(document.createElement('input'), { type: 'radio', name: 'way', value: String(index), checked: index === 0 });
        const code = Object.assign(document.createElement('code'), { textContent: selector });
        const count = matching(selector).length;
        const each = Object.assign(document.createElement('span'), { className: 'count', textContent: `${count} on this page` });
        radio.addEventListener('change', () => outline(matching(selector)));
        label.append(radio, code, each);
        return label;
      }),
    );
    said.textContent = options.length ? 'Choose how to name it. What it names is outlined.' : 'This has no name to keep: try Wider.';
    acts.hidden = false;
    root.querySelector('.go').disabled = !options.length;
    outline(options.length ? matching(options[0]) : [element]);
    root.querySelector(options.length ? '.go' : '.wider').focus();
  }

  function stop() {
    for (const [type, listener] of listeners) window.removeEventListener(type, listener, true);
    while (boxes.length) boxes.pop().remove();
    host.remove();
    delete globalThis.stillwaterPicker;
  }

  const inside = (event) => event.composedPath().includes(host);

  const listeners = [
    ['mousemove', (event) => {
      if (chosen || inside(event)) return;
      const target = document.elementsFromPoint(event.clientX, event.clientY).find((element) => !host.contains(element) && element !== host);
      if (target && target !== over && target !== document.documentElement && target !== document.body) {
        over = target;
        outline([target]);
      }
    }],
    ['click', (event) => {
      if (inside(event)) return;
      event.preventDefault();
      event.stopPropagation();
      if (!chosen && over) offer(over);
    }],
    ['mousedown', (event) => {
      if (!inside(event)) {
        event.preventDefault();
        event.stopPropagation();
      }
    }],
    ['keydown', (event) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        stop();
      }
    }],
  ];
  for (const [type, listener] of listeners) window.addEventListener(type, listener, true);

  root.querySelector('.cancel').addEventListener('click', stop);
  root.querySelector('.wider').addEventListener('click', () => {
    const parent = chosen?.parentElement;
    if (parent && parent !== document.body && parent !== document.documentElement) offer(parent);
  });
  root.querySelector('.go').addEventListener('click', async () => {
    const picked = root.querySelector('input[name="way"]:checked');
    const selector = options[Number(picked?.value)];
    if (!selector) return;
    try {
      const answer = await chrome.runtime.sendMessage({ type: 'picker:hide', selector });
      if (answer?.error) {
        said.textContent = answer.error;
        return;
      }
      stop();
    } catch (error) {
      said.textContent = `Stillwater could not keep it: ${error.message ?? error}`;
    }
  });
})();
