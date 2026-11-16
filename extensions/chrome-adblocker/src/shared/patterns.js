// Adblock Plus address patterns (`||ads.example^*/pop.php?zone=*&id=`),
// matched as they are written and in time that grows with the length of
// the address, never faster: no regular expression, so no backtracking.
// The address is a page's to choose, and a pattern with several wildcards
// turned into an expression can be made to take seconds on one built for
// it. No Chrome API is used here.
//
// A pattern: `||` a host or any subdomain of it, or `|` the address's
// start; then pieces separated by `*`, anything at all; `^` a separator
// (anything but a letter, a digit or `_ - . %`, or the address's end);
// and a final `|` for the address's end.

/** Whether a character, present, is a separator. */
const separator = (c) => !/[0-9a-z_.%-]/i.test(c);

/** Where a piece matching at `i` ends, or -1 if it does not match there. */
function at(url, i, piece) {
  let j = i;
  for (let k = 0; k < piece.length; k++) {
    const c = piece[k];
    if (c === '^') {
      // The end of the address is a separator too, and takes up nothing.
      if (j === url.length) continue;
      if (!separator(url[j])) return -1;
      j++;
    } else {
      if (url[j] !== c) return -1;
      j++;
    }
  }
  return j;
}

/** Where the leftmost match of a piece at or after `from` ends, or -1. */
function find(url, from, piece) {
  const caret = piece.indexOf('^');
  const head = caret === -1 ? piece : piece.slice(0, caret);
  if (!head) {
    for (let i = from; i <= url.length; i++) {
      const end = at(url, i, piece);
      if (end !== -1) return end;
    }
    return -1;
  }
  for (let i = url.indexOf(head, from); i !== -1; i = url.indexOf(head, i + 1)) {
    const end = at(url, i, piece);
    if (end !== -1) return end;
  }
  return -1;
}

/** Where a host's labels begin in an address: where a `||` pattern may begin. */
function hostStarts(url) {
  const scheme = url.indexOf('://');
  if (scheme === -1) return [];
  const begin = scheme + 3;
  let end = url.length;
  for (const mark of ['/', '?', '#']) {
    const found = url.indexOf(mark, begin);
    if (found !== -1 && found < end) end = found;
  }
  const user = url.lastIndexOf('@', end);
  const host = user >= begin ? user + 1 : begin;
  const starts = [host];
  for (let i = host; i < end; i++) {
    if (url[i] === '.') starts.push(i + 1);
  }
  return starts;
}

/**
 * A test of addresses against a pattern: `(url) => boolean`. Letters are
 * compared without their case unless `cased`.
 *
 * Each piece between wildcards is matched at the leftmost place it can be
 * after the one before: an earlier end never leaves less room for what
 * follows, so this finds a match whenever there is one.
 */
export function patternMatcher(pattern, cased = false) {
  let rest = cased ? pattern : pattern.toLowerCase();
  let host = false;
  let start = false;
  let end = false;
  if (rest.startsWith('||')) {
    host = true;
    rest = rest.slice(2);
  } else if (rest.startsWith('|')) {
    start = true;
    rest = rest.slice(1);
  }
  if (rest.endsWith('|')) {
    end = true;
    rest = rest.slice(0, -1);
  }
  const pieces = rest.split('*');
  const last = pieces.length - 1;

  return (address) => {
    const url = cased ? address : address.toLowerCase();
    const anchors = host ? hostStarts(url) : start ? [0] : null;

    /** The last piece, from `from`: anywhere, or ending at the address's end. */
    const tail = (from) => {
      const piece = pieces[last];
      if (!end) return find(url, from, piece) !== -1;
      for (let i = Math.max(from, url.length - piece.length); i <= url.length; i++) {
        if (at(url, i, piece) === url.length) return true;
      }
      return false;
    };

    if (last === 0) {
      if (!anchors) return tail(0);
      return anchors.some((i) => {
        const reached = at(url, i, pieces[0]);
        return reached !== -1 && (!end || reached === url.length);
      });
    }
    let position = -1;
    if (anchors) {
      for (const i of anchors) {
        position = at(url, i, pieces[0]);
        if (position !== -1) break;
      }
    } else {
      position = find(url, 0, pieces[0]);
    }
    if (position === -1) return false;
    for (let k = 1; k < last; k++) {
      position = find(url, position, pieces[k]);
      if (position === -1) return false;
    }
    return tail(position);
  };
}
