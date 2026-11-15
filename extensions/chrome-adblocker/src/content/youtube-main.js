// YouTube, in the page's own world, before the page's scripts run.
//
// YouTube's player is told which ads to show in the same data that
// describes the video: a list of placements beside the title and the
// streams. This takes those lists out of that data wherever the page reads
// it, so the player is never told of an ad. It is the approach the uBlock
// Origin project found; YouTube changes its player often, and has other
// ways to put an ad in, so this is a best effort that will need mending.
// It does not hide: a page that looks can tell its functions are wrapped.
// The switch for it is on the options page.

(() => {
  const AD_KEYS = ['adPlacements', 'adSlots', 'playerAds', 'adBreakHeartbeatParams'];
  let active = true;

  // Everything this script will use is taken now, while it is still what
  // the browser made: the page's scripts run after this one, and may put
  // their own in place of any of it.
  const { apply, defineProperty, deleteProperty, has, ownKeys } = Reflect;
  const then = Function.prototype.call.bind(Promise.prototype.then);

  // The extension's own script in this frame (content/youtube.js) says so
  // if this site is let through after all: a player embedded in a site
  // that is. It says it by an event whose name is made up here and told to
  // it now, before any script of the page's has run, so that the page can
  // neither hear the two speak nor tell this script to stop.
  const word = `stillwater:${Array.from(crypto.getRandomValues(new Uint32Array(4)), (part) => part.toString(36)).join('')}`;
  /** Tells the other script the word; true if it was there to hear. */
  const tell = () => !document.dispatchEvent(new CustomEvent('stillwater:word', { detail: word, cancelable: true }));
  if (!tell()) {
    // It has not started yet. It asks when it does, which is still before
    // the page's scripts; after that nobody is answered.
    document.addEventListener('stillwater:ready', tell, { once: true });
    setTimeout(() => document.removeEventListener('stillwater:ready', tell), 0);
  }
  document.addEventListener(
    word,
    () => {
      active = false;
    },
    { once: true },
  );

  /** A response without its ad lists: itself, or a copy where the page has made it one that can't be changed. */
  function without(response) {
    let stuck = false;
    for (let i = 0; i < AD_KEYS.length; i++) {
      if (has(response, AD_KEYS[i]) && !deleteProperty(response, AD_KEYS[i])) stuck = true;
    }
    if (!stuck) return response;
    const copy = {};
    const keys = ownKeys(response);
    for (let i = 0; i < keys.length; i++) {
      let ad = false;
      for (let j = 0; j < AD_KEYS.length; j++) ad ||= keys[i] === AD_KEYS[j];
      if (!ad) copy[keys[i]] = response[keys[i]];
    }
    return copy;
  }

  /** Takes the ad lists out of a player response, or of one carried inside another object. */
  function prune(value) {
    if (!active || value === null || typeof value !== 'object') return value;
    try {
      const inner = value.playerResponse;
      if (inner !== null && typeof inner === 'object') {
        const pruned = without(inner);
        if (pruned !== inner) value.playerResponse = pruned;
      }
      return without(value);
    } catch {
      // Something that is not what a player response is: left as it came.
      return value;
    }
  }

  // The response written into the page itself.
  let initial;
  try {
    defineProperty(window, 'ytInitialPlayerResponse', {
      configurable: true,
      enumerable: true,
      get: () => initial,
      set: (value) => {
        initial = prune(value);
      },
    });
  } catch {
    // Already defined some other way: the two below still apply.
  }

  // Responses that arrive later, however they are read.
  JSON.parse = new Proxy(JSON.parse, {
    apply: (target, self, args) => prune(apply(target, self, args)),
  });
  Response.prototype.json = new Proxy(Response.prototype.json, {
    apply: (target, self, args) => then(apply(target, self, args), prune),
  });
})();
