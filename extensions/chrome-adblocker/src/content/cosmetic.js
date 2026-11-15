// Runs in every frame as it begins. Asks the service worker what to hide
// here, then tells it which classes and ids the document has, so that of
// the thousands of generic filters only those that could match are ever
// given to the page.

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

  function watch() {
    if (document.documentElement) survey(document.documentElement);
    soon();
    observer = new MutationObserver((changes) => {
      for (const change of changes) {
        if (change.type === 'attributes') look(change.target);
        else for (const node of change.addedNodes) survey(node);
      }
      soon();
    });
    observer.observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'id'] });
  }

  ask({ type: 'cosmetic:start', host }).then((answer) => {
    if (answer?.generic) watch();
  });
})();
