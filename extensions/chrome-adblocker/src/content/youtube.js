// YouTube, from the extension's side of the page. If an ad plays all the
// same, this presses its Skip button when it has one, and otherwise runs
// the ad out to its end with the sound off. Nothing here blocks anything:
// it only gets an ad over with.

(() => {
  const SKIP = '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-skip-button-slot button';
  let wasMuted = null;
  let timer = 0;

  // The script in the page's own world (content/youtube-main.js) tells this
  // one the name of the event that stops it, now, before the page's own
  // scripts can run. Whichever of the two starts first, the other finds it.
  let word = '';
  const hear = (event) => {
    if (typeof event.detail !== 'string' || !event.detail.startsWith('stillwater:')) return;
    word = event.detail;
    event.preventDefault();
    document.removeEventListener('stillwater:word', hear);
  };
  document.addEventListener('stillwater:word', hear);
  document.dispatchEvent(new CustomEvent('stillwater:ready'));
  // Where that script is not at work (the switch is off) nobody will tell.
  setTimeout(() => document.removeEventListener('stillwater:word', hear), 0);

  // The host of the page this frame is in (see content/cosmetic.js).
  let top = location.hostname;
  if (window !== window.top) {
    try {
      const origins = location.ancestorOrigins;
      top = new URL(origins[origins.length - 1]).hostname;
    } catch {
      top = '';
    }
  }

  function look() {
    timer = 0;
    const player = document.querySelector('.html5-video-player');
    if (!player) return;
    const video = player.querySelector('video');
    if (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting')) {
      document.querySelector(SKIP)?.click();
      if (!video) return;
      if (wasMuted === null) {
        wasMuted = video.muted;
        video.muted = true;
      }
      if (Number.isFinite(video.duration) && video.duration > 0 && video.currentTime < video.duration - 0.1) video.currentTime = video.duration;
    } else if (wasMuted !== null) {
      if (video) video.muted = wasMuted;
      wasMuted = null;
    }
  }

  function soon() {
    if (!timer) timer = setTimeout(look, 60);
  }

  chrome.runtime.sendMessage({ type: 'youtube:start', top }).then(
    (answer) => {
      if (!answer?.active) {
        // What the page read before this answer came has had its ad lists
        // taken out already; from here on it is left as YouTube sent it.
        if (word) document.dispatchEvent(new CustomEvent(word));
        return;
      }
      new MutationObserver(soon).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });
      document.addEventListener('loadedmetadata', soon, true);
      document.addEventListener('durationchange', soon, true);
      soon();
    },
    () => {},
  );
})();
