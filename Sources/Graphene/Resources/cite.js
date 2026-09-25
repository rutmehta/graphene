// Graphene in-page citations (graphene-identity.md §3.3, §3.4).
// Finds a passage by normalised text (first match, may span text nodes) and wraps it
// in <mark data-graphene-cite="ID">. Normalising drops bracketed markers ("[4]",
// "[citation needed]"), collapses whitespace, ignores case and the spacing next to
// punctuation, and counts block boundaries as spaces. When the whole passage is not
// in the page, its longest run of at least MIN_RUN words that is gets marked instead.
// Never highlights an approximate match. The Swift mirror is CitedPassage.
(() => {
  if (window.__grapheneCite) return;

  const STYLE_ID = "graphene-cite-style";
  const SKIP = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "TEXTAREA", "INPUT", "SELECT", "OPTION", "IFRAME", "SVG", "CANVAS", "HEAD", "TITLE"]);
  const BLOCK = new Set(["ADDRESS", "ARTICLE", "ASIDE", "BLOCKQUOTE", "BODY", "BR", "DD", "DETAILS", "DIV", "DL", "DT", "FIELDSET",
    "FIGCAPTION", "FIGURE", "FOOTER", "FORM", "H1", "H2", "H3", "H4", "H5", "H6", "HEADER", "HR", "LI", "MAIN", "NAV", "OL",
    "P", "PRE", "SECTION", "SUMMARY", "TABLE", "TBODY", "TD", "TFOOT", "TH", "THEAD", "TR", "UL"]);
  // JavaScript's \s plus U+0085, the same set as Swift's White_Space plus U+FEFF.
  const WS = /[\s\u0085]/;
  const FORMAT = /\p{Cf}/u;
  const WORD = /[\p{L}\p{N}]/u;
  // Longest bracketed marker dropped, in code points between the brackets.
  const BRACKET_MAX = 30;
  // Fewest words a partial match must span.
  const MIN_RUN = 8;
  let hovered = null;

  const post = (message) => {
    try { window.webkit.messageHandlers.graphene.postMessage(message); } catch (e) {}
  };
  const editable = () => !document.body || document.body.isContentEditable;
  const reducedMotion = () => window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Indices of `chars` (code points) left after dropping bracketed markers: "[" then 1 to
  // BRACKET_MAX code points without brackets, at least one not whitespace, then "]".
  const unbracket = (chars) => {
    const keep = [];
    for (let i = 0; i < chars.length; i++) {
      if (chars[i] === "[") {
        let j = i + 1, visible = false;
        while (j < chars.length && j - i - 1 <= BRACKET_MAX && chars[j] !== "[" && chars[j] !== "]") {
          if (!WS.test(chars[j])) visible = true;
          j++;
        }
        if (j < chars.length && chars[j] === "]" && visible && j - i - 1 <= BRACKET_MAX) { i = j; continue; }
      }
      keep.push(i);
    }
    return keep;
  };
  // Folds the kept code points: whitespace runs become one space, kept only between two
  // letters or digits; format characters vanish; the rest is lowercased. `emit(ch, i)` gets
  // each output code point with its source index (-1 for a space).
  const fold = (chars, keep, emit) => {
    let pending = false, last = null;
    for (const i of keep) {
      const ch = chars[i];
      if (WS.test(ch)) { pending = true; continue; }
      if (FORMAT.test(ch)) continue;
      if (pending && last !== null && WORD.test(last) && WORD.test(ch)) emit(" ", -1);
      pending = false;
      for (const lower of ch.toLowerCase()) { emit(lower, i); last = lower; }
    }
  };
  const normalize = (text) => {
    const chars = Array.from(String(text));
    let out = "";
    fold(chars, unbracket(chars), (ch) => { out += ch; });
    return out;
  };
  const words = (text) => String(text).split(/[\s\u0085]+/u).filter((word) => word.length > 0);
  // Where `passage` is in the normalised `text`: the whole passage, else its longest run of at
  // least MIN_RUN whole words (first such run on ties). Returns {at, length, run} or null.
  const locate = (text, passage) => {
    const needle = normalize(passage);
    if (!needle) return null;
    const whole = text.indexOf(needle);
    if (whole >= 0) return { at: whole, length: needle.length, run: String(passage) };
    const list = words(passage);
    let best = null;
    for (let start = 0; start + MIN_RUN <= list.length; start++) {
      if (best && list.length - start <= best.count) break;
      for (let end = start + Math.max(MIN_RUN, best ? best.count + 1 : MIN_RUN); end <= list.length; end++) {
        const run = list.slice(start, end).join(" ");
        const at = text.indexOf(normalize(run));
        if (at < 0) break;
        best = { at, length: normalize(run).length, run, count: end - start };
      }
    }
    return best ? { at: best.at, length: best.length, run: best.run } : null;
  };

  const blockOf = (node) => {
    let el = node.parentElement;
    while (el && !BLOCK.has(el.tagName.toUpperCase())) el = el.parentElement;
    return el;
  };
  const skipped = (node) => {
    for (let el = node.parentElement; el; el = el.parentElement) {
      if (SKIP.has(el.tagName.toUpperCase())) return true;
      if (el.isContentEditable) return true;
      // Left out of the page text the model reads (annotate.js __grapheneReadable).
      if (el.hidden || el.getAttribute("aria-hidden") === "true") return true;
    }
    return false;
  };

  // The document as one normalised string, with a source position for every character.
  // Block boundaries count as whitespace, so "a</p><p>b" matches "a b".
  const index = () => {
    const chars = [];
    const at = [];
    let lastBlock = null;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (skipped(node)) continue;
      const block = blockOf(node);
      if (block !== lastBlock) { chars.push(" "); at.push(null); lastBlock = block; }
      let offset = 0;
      for (const ch of node.nodeValue) {
        chars.push(ch);
        at.push({ node, offset, end: offset + ch.length });
        offset += ch.length;
      }
    }
    let text = "";
    const map = [];
    // One map entry per UTF-16 unit, the unit indexOf counts in.
    fold(chars, unbracket(chars), (ch, i) => { text += ch; for (let k = 0; k < ch.length; k++) map.push(i < 0 ? null : at[i]); });
    return { text, map };
  };

  const wrap = (range, id, number) => {
    const nodes = [];
    const walker = document.createTreeWalker(range.commonAncestorContainer.nodeType === Node.TEXT_NODE
      ? range.commonAncestorContainer.parentNode : range.commonAncestorContainer, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (range.intersectsNode(node) && !skipped(node)) nodes.push(node);
    }
    const marks = [];
    for (const node of nodes) {
      let start = node === range.startContainer ? range.startOffset : 0;
      let end = node === range.endContainer ? range.endOffset : node.nodeValue.length;
      if (end <= start || !node.nodeValue.slice(start, end).trim()) continue;
      let target = node;
      if (start > 0) { target = target.splitText(start); end -= start; }
      if (end < target.nodeValue.length) target.splitText(end);
      const mark = document.createElement("mark");
      mark.setAttribute("data-graphene-cite", id);
      target.parentNode.insertBefore(mark, target);
      mark.appendChild(target);
      marks.push(mark);
    }
    if (marks.length && number != null) marks[0].setAttribute("data-graphene-index", String(number));
    return marks.length > 0;
  };

  const marksFor = (id) => Array.from(document.querySelectorAll("mark[data-graphene-cite]"))
    .filter((mark) => mark.getAttribute("data-graphene-cite") === id);

  const unwrap = (mark) => {
    const parent = mark.parentNode;
    if (!parent) return;
    while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
    parent.removeChild(mark);
    parent.normalize();
  };

  const installStyle = (style) => {
    let el = document.getElementById(STYLE_ID);
    if (!el) {
      el = document.createElement("style");
      el.id = STYLE_ID;
      (document.head || document.documentElement).appendChild(el);
    }
    const fade = reducedMotion() ? 120 : 200;
    el.textContent = `
mark[data-graphene-cite]{background-color:${style.highlight};color:inherit;padding:0 ${style.inset}px;border-radius:2px;
  box-decoration-break:clone;-webkit-box-decoration-break:clone;transition:background-color 120ms ease-out;
  animation:graphene-cite-in ${fade}ms ease-out}
mark[data-graphene-cite].active{background-color:${style.highlightActive}}
mark[data-graphene-cite][data-graphene-index]::before{content:attr(data-graphene-index);color:${style.accent};
  font:600 11px -apple-system,system-ui,sans-serif;font-variant-numeric:tabular-nums;vertical-align:super;margin-right:1px}
@keyframes graphene-cite-in{from{background-color:transparent}}`;
  };

  document.addEventListener("mouseover", (event) => {
    const mark = event.target instanceof Element ? event.target.closest("mark[data-graphene-cite]") : null;
    const id = mark ? mark.getAttribute("data-graphene-cite") : null;
    if (id === hovered) return;
    hovered = id;
    post({ kind: "citeHover", id });
  }, true);

  window.__grapheneCite = {
    normalize,
    // The text that would be marked for `passage` in a page whose text is `pageText` (the
    // passage, or its longest matching run), else null. The Swift mirror is matchingRun(in:).
    match(pageText, passage) {
      const found = locate(normalize(pageText), passage);
      return found ? found.run : null;
    },
    // passages: [{id, text, index?}]; style: {highlight, highlightActive, accent, inset}.
    // Replaces marks with the same ids; returns the ids found.
    highlight(passages, style) {
      if (editable()) return [];
      installStyle(style);
      for (const passage of passages) marksFor(String(passage.id)).forEach(unwrap);
      const ids = [];
      for (const passage of passages) {
        const { text, map } = index();
        const found = locate(text, passage.text || "");
        if (!found) continue;
        const first = map[found.at], last = map[found.at + found.length - 1];
        if (!first || !last) continue;
        const range = document.createRange();
        range.setStart(first.node, first.offset);
        range.setEnd(last.node, last.end);
        if (wrap(range, String(passage.id), passage.index)) ids.push(String(passage.id));
      }
      return ids;
    },
    setActive(id) {
      document.querySelectorAll("mark[data-graphene-cite].active").forEach((mark) => mark.classList.remove("active"));
      if (id != null) marksFor(String(id)).forEach((mark) => mark.classList.add("active"));
    },
    scrollTo(id) {
      const mark = marksFor(String(id))[0];
      if (!mark) return false;
      mark.scrollIntoView({ behavior: reducedMotion() ? "auto" : "smooth", block: "center", inline: "nearest" });
      return true;
    },
    clear() {
      document.querySelectorAll("mark[data-graphene-cite]").forEach(unwrap);
      hovered = null;
    },
  };
})();
