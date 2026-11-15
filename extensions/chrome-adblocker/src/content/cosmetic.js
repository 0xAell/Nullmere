// Runs in every frame as it begins. Asks the service worker what to hide
// here, then tells it which classes and ids the document has, so that of
// the thousands of generic filters only those that could match are ever
// given to the page. Filters that pick an element by the words in it are
// followed here, since no style sheet can.

(() => {
  let host = location.hostname;
  if (!host) {
    // A frame with no address of its own (about:blank, srcdoc) is its parent's.
    try {
      host = new URL(self.origin).hostname;
    } catch {
      host = '';
    }
  }
  if (!host) return;

  const LONGEST = 128;
  const seen = new Set();
  let waiting = [];
  let timer = 0;
  let observer = null;

  /** Asks the worker; null if it can't be reached (the extension was reloaded or removed). */
  async function ask(message) {
    try {
      return await chrome.runtime.sendMessage(message);
    } catch {
      observer?.disconnect();
      return null;
    }
  }

  // --- The classes and ids the document has -------------------------------

  function note(token) {
    if (token.length > LONGEST || seen.has(token)) return;
    seen.add(token);
    waiting.push(token);
  }

  function look(element) {
    if (element.id) note(`#${element.id}`);
    const classes = element.classList;
    for (let i = 0; i < classes.length; i++) note(`.${classes[i]}`);
  }

  function survey(root) {
    if (root.nodeType !== Node.ELEMENT_NODE) return;
    look(root);
    for (const element of root.querySelectorAll('[id],[class]')) look(element);
  }

  function send() {
    timer = 0;
    if (!waiting.length) return;
    const tokens = waiting;
    waiting = [];
    ask({ type: 'cosmetic:tokens', host, tokens });
  }

  function soon() {
    if (waiting.length && !timer) timer = setTimeout(send, 40);
  }

  // --- Filters that pick an element by its words ---------------------------
  // Each is a plan of steps (tools/lib/procedural.js): { css } finds
  // elements, { text } and { re } keep those whose words match, { has }
  // keeps those in which its own steps find something.

  /** A selector's leading compound and what follows it from its first combinator on. */
  function split(css) {
    let depth = 0;
    let quote = '';
    for (let i = 0; i < css.length; i++) {
      const c = css[i];
      if (c === '\\') {
        i++;
      } else if (quote) {
        if (c === quote) quote = '';
      } else if (c === '"' || c === "'") {
        quote = c;
      } else if (c === '(' || c === '[') {
        depth++;
      } else if (c === ')' || c === ']') {
        depth--;
      } else if (depth === 0 && (c === ' ' || c === '>' || c === '+' || c === '~')) {
        return [css.slice(0, i), css.slice(i)];
      }
    }
    return [css, ''];
  }

  /** What a selector finds going on from an element: its children, descendants or later siblings. */
  function onward(element, css) {
    const rest = css.trimStart();
    const lead = rest[0];
    if (lead !== '+' && lead !== '~') return [...element.querySelectorAll(`:scope ${rest}`)];
    const [compound, more] = split(rest.slice(1).trimStart());
    const found = [];
    for (let sibling = element.nextElementSibling; sibling; sibling = sibling.nextElementSibling) {
      if (!compound || sibling.matches(compound)) found.push(...(more ? onward(sibling, more) : [sibling]));
      if (lead === '+') break;
    }
    return found;
  }

  /** The elements a plan's steps find, in the document or going on from `root`. */
  function follow(steps, root) {
    let found = null;
    for (const step of steps) {
      if (step.css !== undefined) {
        if (found === null) {
          found = root ? onward(root, step.css) : [...document.querySelectorAll(step.css)];
        } else {
          const [compound, more] = split(step.css);
          const next = new Set();
          for (const element of found) {
            if (compound && !element.matches(compound)) continue;
            for (const reached of more ? onward(element, more) : [element]) next.add(reached);
          }
          found = [...next];
        }
      } else if (step.text !== undefined) {
        found = found.filter((element) => element.textContent.includes(step.text));
      } else if (step.re !== undefined) {
        const expression = new RegExp(step.re, step.flags);
        found = found.filter((element) => expression.test(element.textContent));
      } else if (step.has) {
        found = found.filter((element) => follow(step.has, element).length > 0);
      }
      if (!found || !found.length) return [];
    }
    return found ?? [];
  }

  let plans = [];
  let due = 0;
  let pause = 300;

  /** Follows every plan and hides what they find. A plan that can't be followed here is dropped. */
  function sweep() {
    due = 0;
    const began = performance.now();
    plans = plans.filter((steps) => {
      try {
        for (const element of follow(steps, null)) element.style.setProperty('display', 'none', 'important');
        return true;
      } catch {
        return false;
      }
    });
    // A page that is slow to search is searched less often.
    pause = Math.min(5000, Math.max(300, (performance.now() - began) * 20));
  }

  function sweepSoon() {
    if (plans.length && !due) due = setTimeout(sweep, pause);
  }

  // --- Watching the document ---------------------------------------------

  function watch(generic) {
    if (generic && document.documentElement) survey(document.documentElement);
    soon();
    if (plans.length) {
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', sweep, { once: true });
      else sweep();
    }
    observer = new MutationObserver((changes) => {
      if (generic) {
        for (const change of changes) {
          if (change.type === 'attributes') look(change.target);
          else for (const node of change.addedNodes) survey(node);
        }
        soon();
      }
      sweepSoon();
    });
    observer.observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'id'], characterData: plans.length > 0 });
  }

  ask({ type: 'cosmetic:start', host }).then((answer) => {
    if (!answer?.active) return;
    plans = Array.isArray(answer.procedural) ? answer.procedural : [];
    if (answer.generic || plans.length) watch(Boolean(answer.generic));
  });
})();
