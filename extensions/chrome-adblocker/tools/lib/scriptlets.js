// Scriptlets: what a filter written `site##+js(name, arguments)` asks to be
// run in a site's pages, in the page's own world and before its scripts:
// to give a property a value the page can't change, to stop a script that
// reaches for something, to take a script out before it runs, to answer a
// request without sending it. Each is written for Stillwater, under the
// names uBlock Origin's lists use for them, and run by Chrome only on the
// sites the filter names (see the service worker).
//
// Every scriptlet is a function of `kit` (the helpers below) and the
// filter's arguments, kept to itself: the build writes each filter out as
// a file that calls its scriptlet inside a function of its own, so nothing
// is added to the page's globals.

/** The helpers a scriptlet is given. Each is written out into every file. */
export const KIT = {
  /** A needle as a test: `/re/flags` as written, anything else as itself; none matches all. */
  toRegExp(needle) {
    if (needle === undefined || needle === '') return /^/;
    const literal = /^\/(.+)\/([dgimsuy]*)$/.exec(needle);
    if (literal) {
      try {
        return new RegExp(literal[1], literal[2]);
      } catch {
        return /(?!)/;
      }
    }
    return new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  },

  /**
   * Reaches the property a chain names (`a.b.c`), now or as soon as its
   * owner is made, and hands `owner` and `name` to `then`.
   */
  onProperty(chain, then) {
    const reach = (owner, path) => {
      const [name, ...rest] = path;
      if (!rest.length) {
        then(owner, name);
        return;
      }
      let inner;
      try {
        inner = owner[name];
      } catch {
        return;
      }
      if (inner instanceof Object) {
        reach(inner, rest);
        return;
      }
      // Not made yet: when it is, reach on into it.
      try {
        Object.defineProperty(owner, name, {
          configurable: true,
          get: () => inner,
          set(next) {
            inner = next;
            if (next instanceof Object) reach(next, rest);
          },
        });
      } catch {
        // A property the page has fixed already: nothing to be done.
      }
    };
    reach(window, chain.split('.'));
  },

  /** Keeps the console clean of the errors a scriptlet throws on purpose. */
  quietly(mark) {
    window.addEventListener('error', (event) => {
      if (String(event.message).includes(mark)) event.preventDefault();
    });
  },
};

/** The values `set` may give, by the words a filter writes them in. */
const SETTABLE = ['undefined', 'false', 'true', 'null', 'noopFunc', 'trueFunc', 'falseFunc', "''", '""', '', '{}', '[]', 'emptyObj', 'emptyArr', 'noopPromiseResolve'];

export const SCRIPTLETS = {
  /** set-constant: a property is given a value, and keeps it whatever the page sets. */
  setConstant(kit, chain, raw = '') {
    const values = {
      undefined: () => undefined,
      false: () => false,
      true: () => true,
      null: () => null,
      noopFunc: () => function () {},
      trueFunc: () => () => true,
      falseFunc: () => () => false,
      "''": () => '',
      '""': () => '',
      '': () => '',
      '{}': () => ({}),
      '[]': () => [],
      emptyObj: () => ({}),
      emptyArr: () => [],
      noopPromiseResolve: () => () => Promise.resolve(),
    };
    let make = values[raw];
    if (!make && /^-?\d{1,5}$/.test(raw)) make = () => Number(raw);
    if (!make || !chain) return;
    const value = make();
    kit.onProperty(chain, (owner, name) => {
      try {
        Object.defineProperty(owner, name, { configurable: false, get: () => value, set: () => {} });
      } catch {
        // Fixed by the page before this ran.
      }
    });
  },

  /**
   * abort-current-script: a script that reaches for the property, and
   * whose own text or address holds the needle, is stopped where it stands.
   */
  abortCurrentScript(kit, chain, needle = '') {
    if (!chain) return;
    const pattern = kit.toRegExp(needle);
    const mark = `Stillwater stopped a script ${Math.random().toString(36).slice(2)}`;
    kit.quietly(mark);
    const check = () => {
      const script = document.currentScript;
      if (!(script instanceof HTMLScriptElement)) return;
      const said = script.src || script.textContent || '';
      if (pattern.test(said)) throw new ReferenceError(mark);
    };
    kit.onProperty(chain, (owner, name) => {
      let value;
      try {
        value = owner[name];
      } catch {
        return;
      }
      try {
        Object.defineProperty(owner, name, {
          configurable: true,
          get() {
            check();
            return value;
          },
          set(next) {
            check();
            value = next;
          },
        });
      } catch {
        // Fixed by the page before this ran.
      }
    });
  },

  /**
   * abort-on-stack-trace: whatever reaches for the property is stopped if
   * the way it came (its stack, without this file's own part) holds the needle.
   */
  abortOnStackTrace(kit, chain, needle = '') {
    if (!chain) return;
    const pattern = kit.toRegExp(needle);
    const mark = `Stillwater stopped a caller ${Math.random().toString(36).slice(2)}`;
    kit.quietly(mark);
    const own = /chrome-extension:\/\//;
    const check = () => {
      const stack = String(new Error().stack ?? '')
        .split('\n')
        .slice(1)
        .filter((line) => !own.test(line))
        .join('\n');
      if (pattern.test(stack)) throw new ReferenceError(mark);
    };
    kit.onProperty(chain, (owner, name) => {
      let value;
      try {
        value = owner[name];
      } catch {
        return;
      }
      try {
        Object.defineProperty(owner, name, {
          configurable: true,
          get() {
            check();
            return value;
          },
          set(next) {
            check();
            value = next;
          },
        });
      } catch {
        // Fixed by the page before this ran.
      }
    });
  },

  /**
   * remove-node-text: a script (or other element) of the page whose text
   * holds the needle is emptied and taken out as it arrives, before it
   * runs: the page's parser lets this see it first.
   */
  removeNodeText(kit, nodeName, needle = '') {
    if (!nodeName) return;
    const names = kit.toRegExp(/^\/.*\/[a-z]*$/.test(nodeName) ? nodeName : `/^${nodeName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$/i`);
    const pattern = kit.toRegExp(needle);
    const look = (node) => {
      if (!names.test(node.nodeName)) return;
      if (!pattern.test(node.textContent ?? '')) return;
      node.textContent = '';
      node.remove?.();
    };
    const each = (node) => {
      look(node);
      if (node.querySelectorAll) for (const inner of node.querySelectorAll('*')) look(inner);
    };
    new MutationObserver((records) => {
      for (const record of records) for (const node of record.addedNodes) each(node);
    }).observe(document, { childList: true, subtree: true });
    each(document);
  },

  /** set-local-storage-item: a key of the site's storage set to a plain value, or taken out. */
  setLocalStorageItem(kit, key, raw = '') {
    if (!key) return;
    const plain = ['undefined', 'false', 'true', 'null', 'yes', 'no', 'on', 'off', 'accept', 'reject', 'accepted', 'rejected', ''];
    try {
      if (raw === '$remove$') localStorage.removeItem(key);
      else if (plain.includes(raw) || /^\d{1,5}$/.test(raw)) localStorage.setItem(key, raw);
      else if (raw === 'emptyArr' || raw === 'emptyObj') localStorage.setItem(key, raw === 'emptyArr' ? '[]' : '{}');
    } catch {
      // Storage the page may not use.
    }
  },

  /**
   * set-cookie: a cookie of the site's set to a plain value; with
   * `reload, 1`, the page is loaded again once, if that changed it.
   */
  setCookie(kit, name, raw = '', path = '', ...options) {
    if (!name || !/^[\w.-]+$/.test(name)) return;
    const plain = ['true', 'false', 'yes', 'no', 'y', 'n', 'ok', 'on', 'off', 'accept', 'reject', 'accepted', 'rejected', 'allow', 'deny', ''];
    if (!plain.includes(raw) && !/^\d{1,5}$/.test(raw)) return;
    const named = {};
    for (let i = 0; i + 1 < options.length; i += 2) named[options[i]] = options[i + 1];
    const has = () => document.cookie.split(';').some((part) => part.trim() === `${name}=${raw}`);
    if (has()) return;
    const where = path === '/' || path === '' ? '/' : path === 'none' ? '' : '/';
    document.cookie = `${name}=${raw}; max-age=31536000${where ? `; path=${where}` : ''}`;
    if (named.reload === '1' && has()) window.location.reload();
  },

  /** cookie-remover: the site's cookies whose names hold the needle are taken away, now and as the page is left. */
  cookieRemover(kit, needle = '') {
    const pattern = kit.toRegExp(needle);
    const remove = () => {
      const parts = window.location.hostname.split('.');
      const domains = [''];
      for (let i = 0; i < parts.length - 1; i++) domains.push(`; domain=.${parts.slice(i).join('.')}`);
      for (const part of document.cookie.split(';')) {
        const name = part.split('=')[0].trim();
        if (!name || !pattern.test(name)) continue;
        for (const domain of domains) {
          for (const path of ['', '; path=/']) document.cookie = `${name}=; max-age=0${path}${domain}`;
        }
      }
    };
    remove();
    window.addEventListener('beforeunload', remove);
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') remove();
    });
  },

  /** no-fetch-if: a fetch for an address that holds the needle is answered, empty, and never sent. */
  noFetchIf(kit, needle = '') {
    const pattern = kit.toRegExp(needle);
    const fetch = window.fetch;
    if (typeof fetch !== 'function') return;
    const answering = function (input, init) {
      let url = '';
      try {
        url = input instanceof Request ? input.url : String(input);
      } catch {
        // Not an address: fetch will say so.
      }
      if (pattern.test(url)) return Promise.resolve(new Response('', { status: 200, statusText: 'OK' }));
      return fetch.apply(this, [input, init]);
    };
    Object.defineProperty(answering, 'name', { value: 'fetch' });
    answering.toString = () => fetch.toString();
    window.fetch = answering;
  },

  /** no-xhr-if: an XMLHttpRequest to an address that holds the needle is answered, empty, and never sent. */
  noXhrIf(kit, needle = '') {
    const pattern = kit.toRegExp(needle);
    const { open, send } = XMLHttpRequest.prototype;
    const kept = new WeakSet();
    XMLHttpRequest.prototype.open = function (method, url, ...rest) {
      if (pattern.test(String(url))) kept.add(this);
      else kept.delete(this);
      return open.call(this, method, url, ...rest);
    };
    XMLHttpRequest.prototype.send = function (...args) {
      if (!kept.has(this)) return send.apply(this, args);
      const request = this;
      const answer = { readyState: 4, status: 200, statusText: 'OK', response: request.responseType === 'json' ? null : '', responseText: '' };
      for (const [key, value] of Object.entries(answer)) {
        try {
          Object.defineProperty(request, key, { value, configurable: true });
        } catch {
          // responseText is not there to read for every type: leave it.
        }
      }
      setTimeout(() => {
        for (const type of ['readystatechange', 'load', 'loadend']) request.dispatchEvent(new Event(type));
      }, 1);
    };
  },

  /** addEventListener-defuser: a listener for an event of a type, whose code holds the needle, is never added. */
  addEventListenerDefuser(kit, type = '', needle = '') {
    const types = kit.toRegExp(type);
    const pattern = kit.toRegExp(needle);
    const add = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function (kind, listener, ...rest) {
      let code = '';
      try {
        code = String(typeof listener === 'function' ? listener : listener?.handleEvent ?? '');
      } catch {
        // A listener that won't be read is not one to judge.
      }
      if (types.test(String(kind)) && pattern.test(code)) return undefined;
      return add.call(this, kind, listener, ...rest);
    };
  },

  /** json-edit: what the page reads with JSON.parse has the parts the query finds taken out. */
  jsonEdit(kit, query = '') {
    const steps = kit.readJsonq(query);
    if (!steps) return;
    const parse = JSON.parse;
    const edited = function (...args) {
      const value = parse.apply(this, args);
      try {
        kit.editJson(steps, value);
      } catch {
        // What can't be edited is given as it came.
      }
      return value;
    };
    Object.defineProperty(edited, 'name', { value: 'parse' });
    edited.toString = () => parse.toString();
    JSON.parse = edited;
  },
};

/**
 * Reads a json-edit query, the subset of uBlock Origin's the lists use:
 * `.name` a property, `..name` one at any depth, `.*` and `..*` every
 * child or descendant, `[n]` an item, and `[?.path op value]` those of
 * what was found so far whose path holds a value (op `==`, `!=`, `^=`,
 * `$=`, `*=`; a string, number, true, false or null), or `[?.path]` those
 * that have it. Returns the steps, or null for anything else.
 */
export function readJsonq(query) {
  const steps = [];
  const name = /^[A-Za-z_$][\w$-]*/;
  let rest = String(query).trim();
  if (!rest) return null;
  while (rest) {
    let found;
    if ((found = /^(\.\.?)(\*|[A-Za-z_$][\w$-]*)/.exec(rest))) {
      steps.push({ deep: found[1] === '..', key: found[2] });
    } else if ((found = /^\[(\d+)\]/.exec(rest))) {
      steps.push({ deep: false, key: found[1] });
    } else if ((found = /^\[\?((?:\.[A-Za-z_$][\w$-]*)+)(?:\s*(==|!=|\^=|\$=|\*=)\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|-?\d+(?:\.\d+)?|true|false|null))?\]/.exec(rest))) {
      const path = found[1].slice(1).split('.');
      if (!path.every((part) => name.test(part))) return null;
      let value;
      if (found[3] !== undefined) {
        const literal = found[3].startsWith("'") ? `"${found[3].slice(1, -1).replaceAll('"', '\\"')}"` : found[3];
        try {
          value = JSON.parse(literal);
        } catch {
          return null;
        }
      }
      steps.push({ where: path, op: found[2] ?? 'has', value });
    } else {
      return null;
    }
    rest = rest.slice(found[0].length);
  }
  // A query that finds the whole of what was read takes nothing out.
  return steps.some((step) => step.key !== undefined) ? steps : null;
}

/** Takes out of `root` what the steps find, from the object or array that holds each. */
export function editJson(steps, root) {
  const holds = (node) => node !== null && typeof node === 'object';
  // Each found thing as [what holds it, its key, itself].
  let found = [[null, null, root]];
  const children = (node) => (holds(node) ? Object.keys(node).map((key) => [node, key, node[key]]) : []);
  const descendants = (node) => {
    const all = [];
    const walk = (parent) => {
      for (const entry of children(parent)) {
        all.push(entry);
        if (all.length > 100000) return;
        walk(entry[2]);
      }
    };
    walk(node);
    return all;
  };
  for (const step of steps) {
    if (step.where) {
      found = found.filter(([, , node]) => {
        let at = node;
        for (const part of step.where) {
          if (!holds(at) || !(part in at)) return false;
          at = at[part];
        }
        if (step.op === 'has') return true;
        if (step.op === '==') return at === step.value;
        if (step.op === '!=') return at !== step.value;
        const text = String(at);
        const wanted = String(step.value);
        return step.op === '^=' ? text.startsWith(wanted) : step.op === '$=' ? text.endsWith(wanted) : text.includes(wanted);
      });
      continue;
    }
    const next = [];
    for (const [, , node] of found) {
      const among = step.deep ? [[null, null, node], ...descendants(node)].flatMap(([, , inner]) => children(inner)) : children(node);
      for (const entry of among) if (step.key === '*' || entry[1] === step.key) next.push(entry);
    }
    found = [...new Map(next.map((entry) => [entry[2] !== null && typeof entry[2] === 'object' ? entry[2] : entry, entry])).values()];
  }
  // Out of each array from its last item back, so the others keep their places.
  const out = found.filter(([parent]) => parent !== null);
  const items = new Map();
  for (const [parent, key] of out) {
    if (Array.isArray(parent)) items.set(parent, [...(items.get(parent) ?? []), Number(key)]);
    else delete parent[key];
  }
  for (const [array, indices] of items) for (const index of indices.sort((a, b) => b - a)) array.splice(index, 1);
  return out.length;
}

/** Helpers only some scriptlets need, written out only into their files. */
const OWN = { jsonEdit: { readJsonq, editJson } };

/** Each scriptlet by every name a filter may give it. */
export const NAMES = {
  set: 'setConstant',
  'set-constant': 'setConstant',
  acs: 'abortCurrentScript',
  acis: 'abortCurrentScript',
  'abort-current-script': 'abortCurrentScript',
  'abort-current-inline-script': 'abortCurrentScript',
  aost: 'abortOnStackTrace',
  'abort-on-stack-trace': 'abortOnStackTrace',
  rmnt: 'removeNodeText',
  'remove-node-text': 'removeNodeText',
  'set-local-storage-item': 'setLocalStorageItem',
  'set-cookie': 'setCookie',
  'cookie-remover': 'cookieRemover',
  'no-fetch-if': 'noFetchIf',
  'prevent-fetch': 'noFetchIf',
  'no-xhr-if': 'noXhrIf',
  'prevent-xhr': 'noXhrIf',
  aeld: 'addEventListenerDefuser',
  'addEventListener-defuser': 'addEventListenerDefuser',
  'json-edit': 'jsonEdit',
};

/**
 * A scriptlet's arguments as a filter writes them: split at commas not
 * escaped (`\,`), each trimmed; one in quotes (`'...'` or `"..."`) is
 * taken as what is inside them, commas and all.
 */
export function readArguments(text) {
  const out = [];
  let i = 0;
  while (i <= text.length) {
    while (text[i] === ' ') i++;
    const quote = text[i] === "'" || text[i] === '"' ? text[i] : null;
    if (quote) {
      const close = text.indexOf(quote, i + 1);
      const after = close === -1 ? -1 : text.slice(close + 1).search(/\S/);
      // Quoted only if the quote closes the argument.
      if (close !== -1 && (after === -1 || text[close + 1 + after] === ',')) {
        out.push(text.slice(i + 1, close));
        i = after === -1 ? text.length + 1 : close + 1 + after + 1;
        continue;
      }
    }
    let piece = '';
    for (; i < text.length; i++) {
      if (text[i] === '\\' && text[i + 1] === ',') {
        piece += ',';
        i++;
      } else if (text[i] === ',') break;
      else piece += text[i];
    }
    out.push(piece.trim());
    i++;
  }
  return out;
}

/**
 * Reads what follows `##` in a scriptlet filter: `+js(name, arguments)`.
 * Returns { name, method, args } for a scriptlet Stillwater has, or
 * { unknown: name }.
 */
export function readScriptlet(body) {
  const found = /^\+js\(([\s\S]*)\)$/.exec(body.trim());
  if (!found) return { unknown: body };
  const [first, ...args] = readArguments(found[1]);
  const name = (first ?? '').replace(/\.js$/, '');
  const method = NAMES[name];
  if (!method) return { unknown: name };
  if (name === 'json-edit' && (args.length !== 1 || !readJsonq(args[0]))) return { unknown: `${name} ${args[0] ?? ''}` };
  if (name === 'set' || name === 'set-constant') {
    if (args.length < 2 || !(SETTABLE.includes(args[1]) || /^-?\d{1,5}$/.test(args[1]))) return { unknown: `${name} ${args[1] ?? ''}` };
  }
  return { name, method, args };
}

/** The file a scriptlet filter becomes: its scriptlet run with its arguments, in a function of its own. */
export function scriptletSource({ method, args, raw }) {
  const kit = Object.entries({ ...KIT, ...(OWN[method] ?? {}) })
    .map(([key, fn]) => `  ${key}: ${fn.toString().replace(/^(?:function\s+)?(\w+)\(/, 'function (')},`)
    .join('\n');
  return `// Nullmere Stillwater: ${raw.replaceAll('\n', ' ')}\n(() => {\nconst kit = {\n${kit}\n};\n(${SCRIPTLETS[method].toString().replace(/^(\w+)\(/, 'function (')})(kit, ...${JSON.stringify(args)});\n})();\n`;
}

/** The match patterns of the hosts a filter names, as Chrome registers a script for them: each with its subdomains. */
export function patternsFor(hosts) {
  return [...new Set(hosts)].sort().map((host) => `*://*.${host}/*`);
}
