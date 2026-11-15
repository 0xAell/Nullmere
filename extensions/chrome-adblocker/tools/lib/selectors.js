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
 * at-rule of its own, nothing that ends a statement, and no escape left
 * hanging to swallow what is written after it.
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
  return true;
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
