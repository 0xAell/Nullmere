// Nullmere Stillwater: in place of the fingerprintjs2 library, kept back. A
// page that asks for the browser's fingerprint is given the same answer
// every browser gets from Stillwater, made of nothing about this one.
(() => {
  const SAME = '2f51b4f0b4d6c1a87e03f5c5a7e3c4b1';
  const later = (done, ...answer) => {
    if (typeof done === 'function') setTimeout(() => done(...answer), 1);
  };
  function Fingerprint2() {}
  Fingerprint2.prototype.get = function (done) {
    later(done, SAME, []);
  };
  Fingerprint2.get = (options, done) => later(typeof options === 'function' ? options : done, []);
  Fingerprint2.getV18 = (options, done) => later(typeof options === 'function' ? options : done, SAME, []);
  Fingerprint2.getPromise = () => Promise.resolve([]);
  Fingerprint2.x64hash128 = () => SAME;
  Fingerprint2.VERSION = '2.1.0';
  window.Fingerprint2 = Fingerprint2;
})();
