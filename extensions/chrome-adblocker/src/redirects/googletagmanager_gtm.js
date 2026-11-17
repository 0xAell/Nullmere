// Nullmere Stillwater: in place of Google's tag manager, kept back. A page
// that waits on the tag manager to call it back (an event's callback, run
// once its tags have fired) is called back at once, so its links and forms
// go on working; nothing is sent anywhere.
(() => {
  const callBack = (event) => {
    if (!event || typeof event !== 'object') return;
    const callback = event.eventCallback;
    if (typeof callback === 'function') setTimeout(callback, 0);
  };
  const layer = Array.isArray(window.dataLayer) ? window.dataLayer : [];
  const push = layer.push;
  layer.push = function (...events) {
    for (const event of events) callBack(event);
    return push.apply(this, events);
  };
  for (const event of layer) callBack(event);
  window.dataLayer = layer;
  window.google_tag_manager = window.google_tag_manager || {};
  window.ga = window.ga || function () {};
})();
