// Cosmetic filters plain CSS can't say: those that pick an element by the
// words in it (`:has-text(Sponsored)`), on their own or inside `:has()`;
// by an XPath expression (`:xpath()`); or by the declarations the page's
// own style sheets give it (`:-abp-properties()`). A filter is turned here
// into a short plan the content script follows (src/content/cosmetic.js):
// a list of steps, each narrowing the elements found so far.
//
//   { css }          elements the selector finds, from the document or
//                    from each element so far
//   { text }         keep those whose text holds these words
//   { re, flags }    keep those whose text matches the expression
//   { has: [steps] } keep those in which the steps find something
//   { xpath }        the elements the expression finds, from the
//                    document or from each element so far
//   { props: { re, flags } }
//                    the elements the page's own style rules apply to,
//                    of those rules whose declarations match; or of the
//                    elements so far, those such a rule applies to

import { isContained, splitSelectors } from './selectors.js';

const TEXT = [':has-text(', ':-abp-contains(', ':contains('];
const FINDING = [':xpath(', ':-abp-properties('];

/** The end of the parenthesis that opens at `open`, or -1. */
function closing(text, open) {
  let depth = 0;
  let quote = '';
  for (let i = open; i < text.length; i++) {
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
    else if (c === ')' || c === ']') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/**
 * Whether a selector holds a :has() inside a :has(), which CSS refuses
 * (`article:has(header:has(.ad))`) and a plan follows: the outer one a
 * step, what it holds plain CSS.
 */
export function nestedHas(selector) {
  for (let at = selector.indexOf(':has('); at !== -1; at = selector.indexOf(':has(', at + 1)) {
    const close = closing(selector, at + 4);
    if (close !== -1 && selector.slice(at + 5, close).includes(':has(')) return true;
  }
  return false;
}

/** Whether a selector needs a plan: it uses a text operator somewhere, or a :has() within a :has(). */
export function isProcedural(selector) {
  return [...TEXT, ...FINDING].some((operator) => selector.includes(operator)) || nestedHas(selector);
}

/**
 * The declarations `:-abp-properties()` looks for, as a step: an
 * expression, or words in which `*` is anything; null if they can't be read.
 */
function propertiesStep(argument) {
  const regex = /^\/(.+)\/([a-z]*)$/s.exec(argument);
  if (regex) {
    try {
      new RegExp(regex[1], regex[2]);
    } catch {
      return null;
    }
    return { props: { re: regex[1], flags: [...new Set(regex[2])].filter((flag) => 'imsu'.includes(flag)).join('') } };
  }
  if (!argument.replaceAll('*', '').trim()) return null;
  return { props: { re: argument.replace(/[.+?^${}()|[\]\\/]/g, '\\$&').replaceAll('*', '.*'), flags: '' } };
}

/** The words or expression a text operator was given, as a step; null if they can't be read. */
function textStep(argument) {
  const regex = /^\/(.+)\/([a-z]*)$/s.exec(argument);
  if (regex) {
    try {
      new RegExp(regex[1], regex[2]);
    } catch {
      return null;
    }
    // Only the flags that change what matches: with `g` or `y` an
    // expression remembers where it stopped, and would miss every other element.
    return { re: regex[1], flags: [...new Set(regex[2])].filter((flag) => 'imsu'.includes(flag)).join('') };
  }
  const quoted = /^(["'])(.*)\1$/s.exec(argument);
  const text = quoted ? quoted[2] : argument;
  return text ? { text } : null;
}

/**
 * The plan for a procedural selector, or null if it uses something the
 * plan has no step for.
 */
export function planFor(selector) {
  const steps = [];
  let css = '';
  // `narrowing`: what comes next keeps some of the elements found. Where
  // the selector before it ends at a combinator (`.feed :has-text(x)`,
  // `.feed > :has-text(x)`) the element the words are looked for in was
  // left unsaid: it is any element there, not `.feed` itself.
  const flush = (narrowing = false) => {
    let part = css.trimEnd();
    // An escaped space is the end of a name, not space after it.
    if (/(?:^|[^\\])(?:\\\\)*\\$/.test(part)) part = css.slice(0, part.length + 1);
    const open = part.length < css.length || /(?:^|[^\\])[>+~]$/.test(part);
    if (narrowing && open) part += ' *';
    if (part.trim()) steps.push({ css: part });
    css = '';
  };
  let i = 0;
  let depth = 0;
  let quote = '';
  while (i < selector.length) {
    const c = selector[i];
    if (c === '\\') {
      css += selector.slice(i, i + 2);
      i += 2;
      continue;
    }
    if (quote) {
      if (c === quote) quote = '';
      css += c;
      i++;
      continue;
    }
    if (c === '"' || c === "'") quote = c;
    else if (c === '[') depth++;
    else if (c === ']') depth--;
    if (depth === 0 && c === ':') {
      const finding = FINDING.find((name) => selector.startsWith(name, i));
      if (finding) {
        const close = closing(selector, i + finding.length - 1);
        if (close === -1) return null;
        const argument = selector.slice(i + finding.length, close).trim();
        const step = finding === ':xpath(' ? (argument ? { xpath: argument } : null) : propertiesStep(argument);
        if (!step) return null;
        flush(true);
        steps.push(step);
        i = close + 1;
        continue;
      }
      const operator = TEXT.find((name) => selector.startsWith(name, i));
      const has = selector.startsWith(':has(', i);
      if (operator || has) {
        const open = i + (operator ?? ':has(').length - 1;
        const close = closing(selector, open);
        if (close === -1) return null;
        const argument = selector.slice(open + 1, close).trim();
        if (operator) {
          const step = textStep(argument);
          if (!step) return null;
          flush(true);
          steps.push(step);
          i = close + 1;
          continue;
        }
        if (isProcedural(argument) || argument.includes(':has(')) {
          // `:has(:has-text(x))`: the element the words are in is any one inside.
          // `:has(header:has(.ad))`: CSS takes no :has() in a :has(), so the outer is a step.
          const inner = planFor(argument.startsWith(':') ? `*${argument}` : argument);
          if (!inner) return null;
          flush(true);
          steps.push({ has: inner });
          i = close + 1;
          continue;
        }
        // An ordinary :has(): CSS as it stands.
        css += selector.slice(i, close + 1);
        i = close + 1;
        continue;
      }
      // A plain parenthesised pseudo-class is copied whole, so nothing in it is taken for a step.
      const pseudo = /^:[a-z-]+\(/.exec(selector.slice(i));
      if (pseudo) {
        const close = closing(selector, i + pseudo[0].length - 1);
        if (close === -1) return null;
        css += selector.slice(i, close + 1);
        i = close + 1;
        continue;
      }
    }
    css += c;
    i++;
  }
  flush();
  if (!steps.length || isProcedural(steps.map((step) => step.css ?? '').join(' '))) return null;
  // Something must be found before it can be narrowed.
  if (steps[0].css === undefined && steps[0].xpath === undefined && steps[0].props === undefined) return null;
  return steps;
}

/**
 * uBlock Origin's way to restyle, `selector:style(declarations)`, written
 * as Adblock Plus writes it, `selector {declarations}`; null if the
 * selector does not end so.
 */
export function styleOperator(text) {
  const selector = text.trimEnd();
  const at = selector.lastIndexOf(':style(');
  if (at <= 0 || closing(selector, at + ':style'.length) !== selector.length - 1) return null;
  return `${selector.slice(0, at)} {${selector.slice(at + ':style('.length, -1)}}`;
}

/**
 * A restyling filter's rule, `selector {declarations}`, as CSS safe to
 * give a page; null if it is anything but plain declarations.
 */
export function styleRule(text) {
  const parts = /^(.+?)\s*\{([^{}]*)\}\s*$/s.exec(text);
  if (!parts) return null;
  const selector = parts[1].trim();
  if (!selector || isProcedural(selector) || !splitSelectors(selector).every(isContained)) return null;
  const declarations = [];
  for (const piece of parts[2].split(';')) {
    const declaration = piece.trim();
    if (!declaration) continue;
    const pair = /^(-?[a-z][a-z-]*)\s*:\s*(.+)$/is.exec(declaration);
    // Nothing that could fetch an address, and nothing that isn't a value.
    if (!pair || /url\(|image\(|image-set\(|src\(|expression\(|[\\@<>]/i.test(pair[2])) return null;
    declarations.push(`${pair[1].toLowerCase()}:${pair[2].trim()}`);
  }
  return declarations.length ? `${selector}{${declarations.join(';')}}` : null;
}
