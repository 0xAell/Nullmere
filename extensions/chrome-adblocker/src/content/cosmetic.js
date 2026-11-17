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

  // The host of the page this frame is in, which decides whether the site
  // is let through. The frame says it itself: the worker knows only which
  // tab a frame is in, and a page Chrome is loading ahead of a visit is in
  // the tab of the page still showing.
  let top = host;
  if (window !== window.top) {
    try {
      const origins = location.ancestorOrigins;
      top = new URL(origins[origins.length - 1]).hostname;
    } catch {
      top = '';
    }
  }

  // A page can give a form fields named `style`, `id` or `querySelectorAll`,
  // and the form then answers to those names with its fields. So the DOM
  // is asked through the prototypes' own methods, which no page can reach
  // from here, never through an element's properties.
  const bound = (method) => Function.prototype.call.bind(method);
  const getter = (prototype, name) => bound(Object.getOwnPropertyDescriptor(prototype, name).get);
  const attributeOf = bound(Element.prototype.getAttribute);
  const allIn = bound(Element.prototype.querySelectorAll);
  // The document answers to the names of images and forms in it the
  // same way, so it is asked the same way.
  const allInDocument = bound(Document.prototype.querySelectorAll);
  const rootOf = getter(Document.prototype, 'documentElement');
  const stateOf = getter(Document.prototype, 'readyState');
  const listen = bound(EventTarget.prototype.addEventListener);
  const matches = bound(Element.prototype.matches);
  const nextOf = getter(Element.prototype, 'nextElementSibling');
  const textOf = getter(Node.prototype, 'textContent');
  const styleOf = { html: getter(HTMLElement.prototype, 'style'), svg: getter(SVGElement.prototype, 'style') };
  const setProperty = bound(CSSStyleDeclaration.prototype.setProperty);
  const evaluate = bound(Document.prototype.evaluate);
  const sheetsOf = getter(Document.prototype, 'styleSheets');

  /** Hides an element by its own style, which outranks the page's style sheets. */
  function conceal(element) {
    const style = element instanceof HTMLElement ? styleOf.html(element) : element instanceof SVGElement ? styleOf.svg(element) : null;
    if (style) setProperty(style, 'display', 'none', 'important');
  }

  const LONGEST = 128;
  // More names than any page made by hand has: past this the page is
  // minting them, and looking up each new one would go on for ever.
  const MOST = 50_000;
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
    if (token.length > LONGEST || seen.size >= MOST || seen.has(token)) return;
    seen.add(token);
    waiting.push(token);
  }

  function look(element) {
    const id = attributeOf(element, 'id');
    if (id) note(`#${id}`);
    const classes = attributeOf(element, 'class');
    if (!classes) return;
    for (const name of classes.split(/\s+/)) {
      if (name) note(`.${name}`);
    }
  }

  function survey(root) {
    if (!(root instanceof Element)) return;
    look(root);
    for (const element of allIn(root, '[id],[class]')) look(element);
  }

  let wait = 40;
  let sent = 0;

  function send() {
    timer = 0;
    // A page that keeps bringing new names is answered less often, down to
    // once a second; one that then stays quiet for a second is answered
    // quickly again from its next lot on. (This was called `wait` after the first new name, so
    // the quiet before that name is what is left of the time since the
    // last lot went.)
    const now = performance.now();
    const quiet = now - sent - wait;
    wait = quiet < 1000 ? Math.min(1000, wait * 2) : 40;
    sent = now;
    // In lots the worker will take, however many a large page has.
    while (waiting.length) ask({ type: 'cosmetic:tokens', host, top, tokens: waiting.splice(0, 4000) });
  }

  function soon() {
    if (waiting.length && !timer) timer = setTimeout(send, wait);
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
    if (lead !== '+' && lead !== '~') return [...allIn(element, `:scope ${rest}`)];
    const [compound, more] = split(rest.slice(1).trimStart());
    const found = [];
    for (let sibling = nextOf(element); sibling; sibling = nextOf(sibling)) {
      if (!compound || matches(sibling, compound)) found.push(...(more ? onward(sibling, more) : [sibling]));
      if (lead === '+') break;
    }
    return found;
  }

  /** The elements an XPath expression finds from `context`; what is not an element is passed over. */
  function byPath(expression, context) {
    const result = evaluate(document, expression, context, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
    const found = [];
    for (let i = 0; i < result.snapshotLength; i++) {
      const node = result.snapshotItem(i);
      if (node instanceof Element) found.push(node);
    }
    return found;
  }

  /** A rule's declarations as `:-abp-properties()` reads them: `name: value;` each, in order of name. */
  function declarationsOf(style) {
    const all = [];
    for (let i = 0; i < style.length; i++) {
      const name = style.item(i);
      const priority = style.getPropertyPriority(name);
      all.push(`${name}: ${style.getPropertyValue(name)}${priority ? ` !${priority}` : ''};`);
    }
    return all.sort().join(' ');
  }

  /**
   * The selectors of the page's own style rules whose declarations match,
   * a pseudo-element taken off so that the element it belongs to is found.
   * A style sheet from another site can't be read, and is passed over.
   */
  function styledBy(expression) {
    const selectors = [];
    const read = (rules) => {
      for (const rule of rules) {
        if (rule instanceof CSSStyleRule) {
          if (expression.test(declarationsOf(rule.style))) {
            const selector = rule.selectorText.replace(/::?(?:before|after|first-line|first-letter|marker|placeholder)\b/gi, '').trim();
            if (selector) selectors.push(selector);
          }
        } else if (rule.cssRules) {
          read(rule.cssRules);
        }
      }
    };
    for (const sheet of sheetsOf(document)) {
      let rules;
      try {
        rules = sheet.cssRules;
      } catch {
        continue;
      }
      read(rules);
    }
    return selectors;
  }

  /** The elements a plan's steps find, in the document or going on from `root`. */
  function follow(steps, root) {
    let found = null;
    for (const step of steps) {
      if (step.css !== undefined) {
        if (found === null) {
          found = root ? onward(root, step.css) : [...allInDocument(document, step.css)];
        } else {
          const [compound, more] = split(step.css);
          const next = new Set();
          for (const element of found) {
            if (compound && !matches(element, compound)) continue;
            for (const reached of more ? onward(element, more) : [element]) next.add(reached);
          }
          found = [...next];
        }
      } else if (step.text !== undefined) {
        found = found.filter((element) => textOf(element).includes(step.text));
      } else if (step.re !== undefined) {
        // Asked of one element after another, so never with a flag that
        // makes it remember where it last stopped.
        const expression = new RegExp(step.re, String(step.flags ?? '').replace(/[gy]/g, ''));
        found = found.filter((element) => expression.test(textOf(element)));
      } else if (step.has) {
        found = found.filter((element) => follow(step.has, element).length > 0);
      } else if (step.xpath !== undefined) {
        const next = new Set();
        for (const context of found ?? [root ?? document]) for (const reached of byPath(step.xpath, context)) next.add(reached);
        found = [...next];
      } else if (step.props !== undefined) {
        const selectors = styledBy(new RegExp(step.props.re, String(step.props.flags ?? '').replace(/[gy]/g, '')));
        const fits = (element, selector) => {
          try {
            return matches(element, selector);
          } catch {
            return false;
          }
        };
        if (found === null) {
          const next = new Set();
          for (const selector of selectors) {
            try {
              for (const element of root ? allIn(root, selector) : allInDocument(document, selector)) next.add(element);
            } catch {
              // A selector this Chromium can't read finds nothing.
            }
          }
          found = [...next];
        } else {
          found = found.filter((element) => selectors.some((selector) => fits(element, selector)));
        }
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
        for (const element of follow(steps, null)) conceal(element);
        return true;
      } catch {
        return false;
      }
    });
    // A page that is slow to search is searched less often: the searching
    // is kept to a twentieth of the time, for as long as that can be done.
    pause = Math.min(30_000, Math.max(300, (performance.now() - began) * 20));
  }

  function sweepSoon() {
    if (plans.length && !due) due = setTimeout(sweep, pause);
  }

  // --- Watching the document ---------------------------------------------

  function watch(generic) {
    const root = rootOf(document);
    if (generic && root) survey(root);
    soon();
    if (plans.length) {
      if (stateOf(document) === 'loading') listen(document, 'DOMContentLoaded', sweep, { once: true });
      else sweep();
      // Style sheets a page links to are read only once they have come.
      listen(window, 'load', sweepSoon, { once: true });
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

  ask({ type: 'cosmetic:start', host, top }).then((answer) => {
    if (!answer?.active) return;
    plans = Array.isArray(answer.procedural) ? answer.procedural : [];
    if (answer.generic || plans.length) watch(Boolean(answer.generic));
  });
})();
