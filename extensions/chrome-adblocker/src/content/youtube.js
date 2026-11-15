// YouTube, from the extension's side of the page. If an ad plays all the
// same, this presses its Skip button when it has one, and otherwise runs
// the ad out to its end with the sound off. Nothing here blocks anything:
// it only gets an ad over with.

(() => {
  const SKIP = '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-skip-button-slot button';
  let wasMuted = null;
  let timer = 0;

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

  chrome.runtime.sendMessage({ type: 'youtube:start' }).then(
    (answer) => {
      if (!answer?.active) {
        document.dispatchEvent(new CustomEvent('stillwater:rest'));
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
