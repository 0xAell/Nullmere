// YouTube, in the page's own world, before the page's scripts run.
//
// YouTube's player is told which ads to show in the same data that
// describes the video: a list of placements beside the title and the
// streams. This takes those lists out of that data wherever the page reads
// it, so the player is never told of an ad. It is the approach the uBlock
// Origin project found; YouTube changes its player often, and has other
// ways to put an ad in, so this is a best effort that will need mending.
// The switch for it is on the options page.

(() => {
  const AD_KEYS = ['adPlacements', 'adSlots', 'playerAds', 'adBreakHeartbeatParams'];
  let active = true;

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

  /** Takes the ad lists out of a player response, or of one carried inside another object. */
  function prune(value) {
    if (!active || value === null || typeof value !== 'object') return value;
    for (const response of [value, value.playerResponse]) {
      if (response === null || typeof response !== 'object') continue;
      for (const key of AD_KEYS) {
        if (key in response) delete response[key];
      }
    }
    return value;
  }

  // The response written into the page itself.
  let initial;
  try {
    Object.defineProperty(window, 'ytInitialPlayerResponse', {
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
    apply: (target, self, args) => prune(Reflect.apply(target, self, args)),
  });
  Response.prototype.json = new Proxy(Response.prototype.json, {
    apply: (target, self, args) => Reflect.apply(target, self, args).then(prune),
  });
})();
