// Reading CSS selectors as text: enough to split a list of them, and to
// tell whether one stays inside the rule it is put in. The extension
// writes selectors from the lists into a style sheet of the user's own
// for every page, so one that could close its rule and begin another is
// refused here, whatever a browser would later make of it.

/** Whether brackets, parentheses and quotes are balanced. */
export function isBalanced(selector) {
  const closers = { ')': '(', ']': '[' };
  const open = [];
  let quote = '';
  for (let i = 0; i < selector.length; i++) {
    const c = selector[i];
    if (c === '\\') {
      i++;
      continue;
    }
    if (quote) {
      if (c === quote) quote = '';
      continue;
    }
    if (c === '"' || c === "'") quote = c;
    else if (c === '(' || c === '[') open.push(c);
    else if (c === ')' || c === ']') {
      if (open.pop() !== closers[c]) return false;
    }
  }
  return !quote && open.length === 0;
}

/**
 * Whether a selector, written into `selector, selector {declarations}`,
 * stays a selector of that rule: balanced, with no block, comment or
 * at-rule of its own, nothing that ends a statement, no address written
 * outside quotes, and no escape left hanging to swallow what is written
 * after it.
 */
export function isContained(selector) {
  if (!selector || selector.startsWith('@') || /[{}]|\/\*|\*\/|[\n\r\f]/.test(selector) || !isBalanced(selector)) return false;
  let quote = '';
  for (let i = 0; i < selector.length; i++) {
    const c = selector[i];
    if (c === '\\') {
      if (i === selector.length - 1) return false;
      i++;
    } else if (quote) {
      if (c === quote) quote = '';
    } else if (c === '"' || c === "'") {
      quote = c;
    } else if (c === ';') {
      return false;
    }
  }
  // An unquoted url( reads on to the next ) whatever is between, and a
  // quote left over after it would then run on into the rule's block. It
  // is a url( however its letters are written: escaped (`\75rl(`) as well.
  return !/url\(/i.test(bare(selector));
}

/**
 * What a selector says outside its quotes, its escapes read as the
 * letters they stand for: an escaped `(` is kept apart as a letter of a
 * name, which is what it is.
 */
function bare(selector) {
  let out = '';
  let quote = '';
  for (let i = 0; i < selector.length; i++) {
    const c = selector[i];
    if (quote) {
      if (c === '\\') i++;
      else if (c === quote) quote = '';
      continue;
    }
    if (c === '"' || c === "'") {
      quote = c;
      continue;
    }
    if (c !== '\\') {
      out += c;
      continue;
    }
    // An escape: up to six hexadecimal digits and one space after them, or any one character.
    const hex = /^[0-9a-f]{1,6}/i.exec(selector.slice(i + 1, i + 7));
    let letter;
    if (hex) {
      letter = String.fromCodePoint(Math.min(parseInt(hex[0], 16), 0x10ffff) || 0xfffd);
      i += hex[0].length;
      if (/[ \t\n\r\f]/.test(selector[i + 1] ?? '')) i++;
    } else {
      letter = selector[i + 1] ?? '';
      i++;
    }
    out += letter === '(' ? '\u0000' : letter;
  }
  return out;
}

/** Splits a selector list at its top-level commas. */
export function splitSelectors(text) {
  const parts = [];
  let depth = 0;
  let quote = '';
  let start = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '\\') {
      i++;
      continue;
    }
    if (quote) {
      if (c === quote) quote = '';
      continue;
    }
    if (c === '"' || c === "'") quote = c;
    else if (c === '(' || c === '[') depth++;
    else if (c === ')' || c === ']') depth--;
    else if (c === ',' && depth === 0) {
      parts.push(text.slice(start, i).trim());
      start = i + 1;
    }
  }
  parts.push(text.slice(start).trim());
  return parts.filter(Boolean);
}
