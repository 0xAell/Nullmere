// Nullmere Stillwater: in place of Chartbeat's analytics script, kept back.
// A page that tells Chartbeat what it shows finds something to tell, which
// sends nothing anywhere.
(() => {
  const nothing = () => {};
  window.pSUPERFLY = { activity: nothing, virtualPage: nothing };
})();
