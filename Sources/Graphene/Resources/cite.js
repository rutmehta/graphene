// Graphene in-page citations (graphene-identity.md §3.3, §3.4).
// Finds a passage by normalised text (whitespace collapsed, case-insensitive, first
// match, may span text nodes) and wraps it in <mark data-graphene-cite="ID">.
// Never highlights an approximate match. The Swift mirror is CitedPassage.normalized.
(() => {
  if (window.__grapheneCite) return;

  const STYLE_ID = "graphene-cite-style";
  const SKIP = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "TEXTAREA", "INPUT", "SELECT", "OPTION", "IFRAME", "SVG", "CANVAS", "HEAD", "TITLE"]);
  const BLOCK = new Set(["ADDRESS", "ARTICLE", "ASIDE", "BLOCKQUOTE", "BODY", "BR", "DD", "DETAILS", "DIV", "DL", "DT", "FIELDSET",
    "FIGCAPTION", "FIGURE", "FOOTER", "FORM", "H1", "H2", "H3", "H4", "H5", "H6", "HEADER", "HR", "LI", "MAIN", "NAV", "OL",
    "P", "PRE", "SECTION", "SUMMARY", "TABLE", "TBODY", "TD", "TFOOT", "TH", "THEAD", "TR", "UL"]);
  const WS = /\s/;
  let hovered = null;

  const post = (message) => {
    try { window.webkit.messageHandlers.graphene.postMessage(message); } catch (e) {}
  };
  const editable = () => !document.body || document.body.isContentEditable;
  const reducedMotion = () => window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Same rule as the Swift mirror: collapse whitespace runs to one space, trim, lowercase.
  const normalize = (text) => {
    let out = "";
    let space = false;
    for (const ch of String(text)) {
      if (WS.test(ch)) { space = out.length > 0; continue; }
      if (space) { out += " "; space = false; }
      out += ch.toLowerCase();
    }
    return out;
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
    }
    return false;
  };

  // The document as one normalised string, with a source position for every character.
  // Block boundaries count as whitespace, so "a</p><p>b" matches "a b".
  const index = () => {
    const text = [];
    const map = [];
    let pendingSpace = false;
    let lastBlock = null;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (skipped(node)) continue;
      const block = blockOf(node);
      if (block !== lastBlock) { pendingSpace = true; lastBlock = block; }
      const value = node.nodeValue;
      let offset = 0;
      for (const ch of value) {
        const length = ch.length;
        if (WS.test(ch)) { pendingSpace = true; offset += length; continue; }
        if (pendingSpace && text.length > 0) { text.push(" "); map.push({ node, offset, end: offset }); }
        pendingSpace = false;
        for (const lower of ch.toLowerCase()) { text.push(lower); map.push({ node, offset, end: offset + length }); }
        offset += length;
      }
    }
    return { text: text.join(""), map };
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
    // passages: [{id, text, index?}]; style: {highlight, highlightActive, accent, inset}.
    // Replaces marks with the same ids; returns the ids found.
    highlight(passages, style) {
      if (editable()) return [];
      installStyle(style);
      for (const passage of passages) marksFor(String(passage.id)).forEach(unwrap);
      const found = [];
      for (const passage of passages) {
        const needle = normalize(passage.text || "");
        if (!needle) continue;
        const { text, map } = index();
        const at = text.indexOf(needle);
        if (at < 0) continue;
        const first = map[at], last = map[at + needle.length - 1];
        const range = document.createRange();
        range.setStart(first.node, first.offset);
        range.setEnd(last.node, last.end);
        if (wrap(range, String(passage.id), passage.index)) found.push(String(passage.id));
      }
      return found;
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
