// Graphene annotation affordance (graphene-language.md §5.3).
// Injected at document-end into the main frame. All UI lives in a Shadow DOM
// overlay so the host page's CSS and CSP can't interfere, and all styling is set
// via CSSOM properties (not injected <style>/inline strings, which strict-CSP
// sites block). Colours, sizes and radii arrive from Swift as page-scheme tokens
// (`window.__grapheneAnnotateTheme`, WKWebEngine.annotationStyle); saved notes arrive
// through `window.__grapheneAnnotateNotes` and cite.js draws them as note-kind marks.
(() => {
  if (window.__grapheneAnnotate) return;
  window.__grapheneAnnotate = true;

  // Placement rules, in viewport coordinates. `sel` is the selection's bounding rect
  // ({left, top, right, bottom}), `size` the card's {width, height}, `view` the viewport's
  // {width, height} and `gap` the distance kept from the selection and the viewport edges.
  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  const layout = {
    // The selection bar sits `gap` above the selection, centred on it; below it when the
    // viewport has no room above.
    bar(sel, size, view, gap) {
      const left = clamp((sel.left + sel.right) / 2 - size.width / 2, gap, Math.max(gap, view.width - size.width - gap));
      const above = sel.top - gap - size.height;
      if (above >= gap) return { left, top: above, placement: "above" };
      return { left, top: sel.bottom + gap, placement: "below" };
    },
    // The note editor never covers the selection: beside it (right, then left), else
    // below it, else above it; when nothing fits it goes below and the page scrolls.
    editor(sel, size, view, gap) {
      const top = clamp(sel.top, gap, Math.max(gap, view.height - size.height - gap));
      if (sel.right + gap + size.width <= view.width - gap) return { left: sel.right + gap, top, placement: "right" };
      if (sel.left - gap - size.width >= gap) return { left: sel.left - gap - size.width, top, placement: "left" };
      const left = clamp(sel.left, gap, Math.max(gap, view.width - size.width - gap));
      if (sel.bottom + gap + size.height <= view.height - gap) return { left, top: sel.bottom + gap, placement: "below" };
      if (sel.top - gap - size.height >= gap) return { left, top: sel.top - gap - size.height, placement: "above" };
      return { left, top: sel.bottom + gap, placement: "below" };
    },
  };
  window.__grapheneAnnotateLayout = layout;
  if (typeof document === "undefined" || !document.documentElement) return;

  const post = (msg) => {
    try { window.webkit.messageHandlers.graphene.postMessage(msg); } catch (e) {}
  };
  // Shadow host, positioned absolutely in the document.
  const host = document.createElement("div");
  host.setAttribute("data-graphene", "");
  const s = host.style;
  s.position = "absolute"; s.zIndex = "2147483646"; s.top = "0"; s.left = "0";
  s.width = "0"; s.height = "0";
  const root = host.attachShadow({ mode: "open" });
  document.documentElement.appendChild(host);

  function makeEl(tag, styles, text) {
    const el = document.createElement(tag);
    Object.assign(el.style, styles);
    if (text != null) el.textContent = text;
    return el;
  }

  const baseFont = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

  // The page's readable text, for the graph snippet and Ask. Read from the live document with
  // a walker that stops at `READABLE_LIMIT` characters: cloning the whole body and spacing
  // every block element cost as much as the page was large, after every load.
  const READABLE_LIMIT = 40000;
  const READABLE_SKIP = 'nav,footer,header,aside,script,style,noscript,form,input,textarea,[contenteditable],[hidden],[aria-hidden="true"],[data-graphene]';
  // textContent runs blocks together ("…material.Graphene…"); space them as the page shows them.
  const READABLE_BLOCKS = new Set('ADDRESS ARTICLE ASIDE BLOCKQUOTE BR DD DIV DL DT FIGCAPTION FIGURE H1 H2 H3 H4 H5 H6 HR LI OL P PRE SECTION TABLE TD TH TR UL'.split(' '));
  const readableText = (main) => {
    const walker = document.createTreeWalker(main, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
      acceptNode: node => node.nodeType === 1 && node !== main && node.matches(READABLE_SKIP) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
    });
    const blockOf = node => { let e = node.parentElement; while (e && e !== main && !READABLE_BLOCKS.has(e.tagName)) e = e.parentElement; return e; };
    const parts = [];
    let length = 0, lastBlock = null, crossed = false;
    for (let node = walker.nextNode(); node && length <= READABLE_LIMIT; node = walker.nextNode()) {
      if (node.nodeType === 1) { if (READABLE_BLOCKS.has(node.tagName)) crossed = true; continue; }
      const text = node.nodeValue;
      if (!text) continue;
      const block = blockOf(node);
      if (crossed || block !== lastBlock) { parts.push(' '); length += 1; }
      crossed = false; lastBlock = block;
      const piece = text.replace(/\s+/g, ' ');
      parts.push(piece); length += piece.length;
    }
    return parts.join('').replace(/\s+/g, ' ').trim().slice(0, READABLE_LIMIT);
  };
  window.__grapheneReadable = () => {
    const body = document.body;
    if (!body) return { title: document.title, text: '', selection: '', byline: '', published: '', headings: [] };
    const readable = e => !e.closest(READABLE_SKIP);
    // At most 60 candidates are scored: nested sections made scoring grow with depth × size.
    const candidates = [...body.querySelectorAll('article,main,[role="main"],section')].filter(readable).slice(0, 60);
    const score = e => (e.textContent || '').length - [...e.querySelectorAll('a')].reduce((n, a) => n + a.textContent.length, 0) * 2;
    const main = candidates.map(e => [e, score(e)]).sort((a, b) => b[1] - a[1])[0]?.[0] || body;
    return { title: document.title, text: readableText(main),
      selection: String(getSelection() || '').slice(0, 8000),
      byline: document.querySelector('meta[name="author"]')?.content || '',
      published: document.querySelector('meta[property="article:published_time"]')?.content || document.querySelector('time[datetime]')?.dateTime || '',
      headings: [...main.querySelectorAll('h1,h2,h3')].filter(readable).map(e => e.textContent.trim()).slice(0, 40) };
  };
  window.__grapheneReadableLimit = READABLE_LIMIT;

  // Drafts are never sent merely because an editor gained focus.
  const writingButton = makeEl('button', { position: 'fixed', display: 'none', borderRadius: '8px', padding: '4px 8px', font: `500 13px ${baseFont}`, color: 'ButtonText', background: 'ButtonFace', border: '1px solid GrayText', cursor: 'pointer' }, '✦');
  writingButton.setAttribute('aria-label', 'Writing help');
  root.appendChild(writingButton);
  const safeEditor = e => {
    if (!(e instanceof HTMLElement) || !e.isConnected || e.closest('[data-graphene]') || e.closest('[aria-disabled="true"]')) return false;
    if (!(e.matches('textarea,input[type="text"],input:not([type])') || e.isContentEditable)) return false;
    if (e.disabled || e.readOnly || e.querySelector('input[type="password"],[autocomplete^="cc-"]')) return false;
    const labels = [e.id, e.getAttribute('name'), e.getAttribute('autocomplete'), e.getAttribute('aria-label'), e.getAttribute('placeholder')].join(' ');
    return !/password|passcode|credit|card|payment|cvv|cvc|cc-|account.?number|ssn|one-time-code/i.test(labels);
  };
  const editorText = e => e.isContentEditable ? e.innerText : e.value;
  let writingTarget = null, writingID = '', original = '';
  const updateWriting = () => {
    const e = document.activeElement;
    if (!safeEditor(e) || !/[.!?](\s|$)/.test(editorText(e) || '')) { writingButton.style.display = 'none'; return; }
    writingTarget = e;
    const r = e.getBoundingClientRect();
    writingButton.style.left = `${Math.max(4, Math.min(innerWidth - 40, r.right - 36))}px`;
    writingButton.style.top = `${Math.max(4, Math.min(innerHeight - 32, r.bottom - 30))}px`;
    writingButton.style.display = 'block';
  };
  document.addEventListener('focusin', updateWriting, true);
  document.addEventListener('input', updateWriting, true);
  document.addEventListener('scroll', updateWriting, true);
  writingButton.addEventListener('mousedown', e => e.preventDefault());
  writingButton.addEventListener('click', () => {
    if (!safeEditor(writingTarget)) return;
    writingID = crypto.randomUUID(); original = editorText(writingTarget);
    const r = writingButton.getBoundingClientRect();
    try { window.webkit.messageHandlers['graphene.writing'].postMessage({kind:'writing', id:writingID, text:original.slice(0, 12000), x:r.x, y:r.y}); } catch (_) {}
  });
  window.__grapheneWrite = (id, text, mode) => {
    if (id !== writingID || !safeEditor(writingTarget) || original !== editorText(writingTarget)) return false;
    const e = writingTarget;
    const value = mode === 'insert' ? original + '\n' + text : text;
    e.focus();
    // insertText preserves a native undo step for simple contenteditables.
    if (e.isContentEditable) {
      const selection = getSelection(), range = document.createRange(); range.selectNodeContents(e);
      selection.removeAllRanges(); selection.addRange(range);
      if (!document.execCommand('insertText', false, value)) return false;
    } else {
      e.setSelectionRange(0, e.value.length);
      if (!document.execCommand('insertText', false, value)) {
        const prototype = e.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(prototype, 'value').set.call(e, value);
      }
    }
    e.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertReplacementText', data:text}));
    e.dispatchEvent(new Event('change', {bubbles:true}));
    writingID = ''; writingButton.style.display = 'none'; return true;
  };

  let hoverTimer, hovered;
  document.addEventListener('mousemove', e => {
    const a = e.target.closest?.('a[href]');
    if (hovered === a && e.shiftKey) return;
    clearTimeout(hoverTimer); hovered = e.shiftKey ? a : null;
    if (!hovered || !/^https?:/.test(a.href)) return;
    hoverTimer = setTimeout(() => { const r = a.getBoundingClientRect(); post({kind:'preview', url:a.href, x:r.x, y:r.y}); }, 700);
  }, true);
  document.addEventListener('keyup', e => { if (e.key === 'Shift') { clearTimeout(hoverTimer); hovered = null; } });


  // MARK: tokens

  const reducedMotion = () => window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const darkPage = () => window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  // Used only until Swift sends the page-scheme tokens (at load).
  const fallback = () => darkPage()
    ? { elev: "rgb(38,38,44)", hairline: "rgba(255,255,255,0.1)", ink: "rgb(255,255,255)", ink2: "rgba(255,255,255,0.72)",
        ink3: "rgba(255,255,255,0.48)", accent: "rgb(145,150,217)", elevFill: "rgba(255,255,255,0.09)", quoteRule: "rgba(255,255,255,0.18)",
        shadow: "rgba(0,0,0,0.35)", shadowRadius: 12, shadowY: 2, highlightActive: "rgba(145,150,217,0.38)" }
    : { elev: "rgb(255,255,255)", hairline: "rgba(0,0,0,0.08)", ink: "rgb(27,27,34)", ink2: "rgba(27,27,34,0.75)",
        ink3: "rgba(27,27,34,0.5)", accent: "rgb(71,78,158)", elevFill: "rgba(0,0,0,0.04)", quoteRule: "rgba(27,27,34,0.14)",
        shadow: "rgba(0,0,0,0.1)", shadowRadius: 10, shadowY: 1, highlightActive: "rgba(71,78,158,0.38)" };
  const sizes = { radius: 12, rowRadius: 8, barHeight: 36, cardWidth: 320, gap: 8, dot: 6, labelSize: 11, rowSize: 13, bodySize: 13,
    quoteSize: 13, quoteLineHeight: 1.45 };
  let theme = Object.assign({}, sizes, fallback());
  const serifFont = 'ui-serif, "New York", Georgia, serif';
  // §6 motion as CSS: the margin dot's spring(0.25, 0.8), the Arc popover spring(0.32, 0.8),
  // and the 120ms fade Reduce Motion substitutes for both.
  const DOT_SPRING = "transform 250ms cubic-bezier(0.34, 1.35, 0.64, 1), opacity 120ms ease-out";
  const CARD_SPRING = "transform 320ms cubic-bezier(0.3, 1.25, 0.6, 1), opacity 160ms ease-out";
  const FADE = "opacity 120ms ease-out";

  // MARK: cards

  const card = () => makeEl("div", { position: "absolute", display: "none", boxSizing: "border-box", cursor: "default",
    userSelect: "none", webkitUserSelect: "none" });
  const paintCard = (el) => {
    Object.assign(el.style, { background: theme.elev, border: `1px solid ${theme.hairline}`, borderRadius: `${theme.radius}px`,
      boxShadow: `0 ${theme.shadowY}px ${theme.shadowRadius * 2}px ${theme.shadow}`, color: theme.ink, font: `400 ${theme.rowSize}px ${baseFont}` });
  };
  const SVG = "http://www.w3.org/2000/svg";
  const GLYPHS = {
    save: "M4.5 2.5h5a1 1 0 0 1 1 1v8.5L7 9.6 3.5 12V3.5a1 1 0 0 1 1-1z",
    note: "M9.6 2.4l2 2L5.2 10.8 2.7 11.3l.5-2.5z",
    ask: "M2.5 3.2a1 1 0 0 1 1-1h7a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H6.2L3.8 11.5V9.2h-.3a1 1 0 0 1-1-1z",
  };
  const glyph = (name) => {
    const svg = document.createElementNS(SVG, "svg");
    svg.setAttribute("width", "14"); svg.setAttribute("height", "14"); svg.setAttribute("viewBox", "0 0 14 14");
    svg.setAttribute("aria-hidden", "true");
    const path = document.createElementNS(SVG, "path");
    path.setAttribute("d", GLYPHS[name]); path.setAttribute("fill", "none"); path.setAttribute("stroke", "currentColor");
    path.setAttribute("stroke-width", "1.2"); path.setAttribute("stroke-linejoin", "round");
    svg.appendChild(path);
    return svg;
  };
  const labelButton = (text) => makeEl("button", { display: "inline-flex", alignItems: "center", gap: "5px", height: "100%",
    padding: "0 8px", border: "none", background: "transparent", cursor: "pointer", borderRadius: "6px", whiteSpace: "nowrap" }, text);
  const paintLabel = (el, color) => Object.assign(el.style, { color, font: `600 ${theme.labelSize}px ${baseFont}` });

  // Selection bar: Save (⌘D), Note, Ask. No brand name.
  const bar = card();
  Object.assign(bar.style, { alignItems: "center", padding: "0 4px", whiteSpace: "nowrap" });
  bar.setAttribute("role", "toolbar"); bar.setAttribute("aria-label", "Selection");
  const action = (name, text, hint) => {
    const button = labelButton(null);
    button.append(glyph(name), document.createTextNode(text));
    if (hint) { const key = makeEl("span", {}, hint); key.setAttribute("data-hint", ""); button.appendChild(key); }
    button.setAttribute("aria-label", text);
    button.addEventListener("mousedown", (e) => e.preventDefault());
    return button;
  };
  const saveBtn = action("save", "Save", "⌘D"), noteBtn = action("note", "Note"), askBtn = action("ask", "Ask");
  bar.append(saveBtn, noteBtn, askBtn);
  root.appendChild(bar);

  // Note editor: the same card with a `body` field and "Save note"; Escape cancels.
  const editor = card();
  Object.assign(editor.style, { flexDirection: "column", gap: "8px", padding: "10px" });
  const ta = makeEl("textarea", { resize: "none", height: "72px", outline: "none", boxSizing: "border-box", width: "100%",
    border: "none", padding: "7px 9px", userSelect: "text", webkitUserSelect: "text" });
  ta.setAttribute("placeholder", "Add a note");
  ta.setAttribute("aria-label", "Note");
  const editorSave = labelButton("Save note");
  Object.assign(editorSave.style, { alignSelf: "flex-end", height: "24px" });
  editor.append(ta, editorSave);
  root.appendChild(editor);

  // The margin dot beside a hovered saved mark, and the note card it opens. The dot's
  // padding is a larger, invisible hit area around the 6pt disc.
  const DOT_PAD = 5;
  const dot = makeEl("div", { position: "absolute", display: "none", borderRadius: "50%", cursor: "pointer", padding: `${DOT_PAD}px`,
    backgroundClip: "content-box", boxSizing: "content-box" });
  dot.setAttribute("role", "button"); dot.setAttribute("aria-label", "Show note");
  root.appendChild(dot);
  const noteCard = card();
  Object.assign(noteCard.style, { flexDirection: "column", gap: "8px", padding: "12px", transformOrigin: "top left" });
  const noteText = makeEl("div", { whiteSpace: "pre-wrap", userSelect: "text", webkitUserSelect: "text" });
  const noteQuote = makeEl("div", { borderLeft: "1px solid", paddingLeft: "8px", margin: "2px 0", userSelect: "text", webkitUserSelect: "text",
    maxHeight: "160px", overflow: "auto" });
  const noteActions = makeEl("div", { display: "flex", gap: "4px", marginLeft: "-8px", height: "22px" });
  const editBtn = labelButton("Edit"), openBtn = labelButton("Open in Vault");
  noteActions.append(editBtn, openBtn);
  noteCard.append(noteText, noteQuote, noteActions);
  root.appendChild(noteCard);

  function applyTheme() {
    [bar, editor, noteCard].forEach(paintCard);
    bar.style.height = `${theme.barHeight}px`;
    for (const button of [saveBtn, noteBtn, askBtn]) {
      paintLabel(button, theme.ink2);
      const hint = button.querySelector("[data-hint]");
      if (hint) hint.style.color = theme.ink3;
    }
    editor.style.width = `${theme.cardWidth}px`;
    noteCard.style.width = `${theme.cardWidth}px`;
    Object.assign(ta.style, { font: `400 ${theme.bodySize}px ${baseFont}`, color: theme.ink, background: theme.elevFill, borderRadius: `${theme.rowRadius}px` });
    paintLabel(editorSave, theme.accent);
    paintLabel(editBtn, theme.ink2); paintLabel(openBtn, theme.ink2);
    Object.assign(noteText.style, { font: `400 ${theme.rowSize}px ${baseFont}`, color: theme.ink });
    Object.assign(noteQuote.style, { font: `400 ${theme.quoteSize}px/${theme.quoteLineHeight} ${serifFont}`, color: theme.ink, borderLeftColor: theme.quoteRule });
    Object.assign(dot.style, { width: `${theme.dot}px`, height: `${theme.dot}px`, backgroundColor: theme.accent });
  }
  applyTheme();
  // style: WKWebEngine.annotationStyle(palette.page(dark:)).
  window.__grapheneAnnotateTheme = (style) => { theme = Object.assign({}, sizes, fallback(), style || {}); applyTheme(); };

  const view = () => ({ width: document.documentElement.clientWidth || innerWidth, height: innerHeight });
  const rectOf = (r) => ({ left: r.left, top: r.top, right: r.right, bottom: r.bottom });
  // Cards live in the document: the shadow host sits at its origin.
  const put = (el, pos) => { el.style.left = `${pos.left + scrollX}px`; el.style.top = `${pos.top + scrollY}px`; };
  const measure = (el, display) => {
    el.style.visibility = "hidden"; el.style.display = display;
    const size = { width: el.offsetWidth, height: el.offsetHeight };
    el.style.visibility = "";
    return size;
  };
  // The Arc popover spring on appearance; a fade under Reduce Motion.
  const reveal = (el, display) => {
    const reduced = reducedMotion();
    el.style.transition = "none"; el.style.opacity = "0";
    el.style.transform = reduced ? "none" : "scale(0.96)";
    el.style.display = display;
    void el.offsetWidth;
    el.style.transition = reduced ? FADE : CARD_SPRING;
    el.style.opacity = "1"; el.style.transform = "none";
  };

  // MARK: selection

  let savedRange = null;
  // The saved note the editor is changing ({id}), or null while it writes a new one.
  let editing = null;

  function selectionContext(range) {
    const container = range.commonAncestorContainer;
    const block = (container.nodeType === 1 ? container : container.parentElement)?.closest("p,li,article,section,div,main,body");
    return (block?.innerText || "").replace(/\s+/g, " ").trim().slice(0, 500);
  }

  function hideSelectionUI() { bar.style.display = "none"; editor.style.display = "none"; editing = null; }
  function hideNoteUI() { noteCard.style.display = "none"; hideDot(); }
  function hideAll() { hideSelectionUI(); hideNoteUI(); }

  function showBar(range) {
    const size = measure(bar, "inline-flex");
    put(bar, layout.bar(rectOf(range.getBoundingClientRect()), size, view(), theme.gap));
    reveal(bar, "inline-flex");
  }

  function showEditor(rect, text) {
    bar.style.display = "none";
    ta.value = text || "";
    const size = measure(editor, "flex");
    put(editor, layout.editor(rect, size, view(), theme.gap));
    reveal(editor, "flex");
    ta.focus();
  }

  const selectedText = (range) => range ? range.toString().trim() : "";

  function commit(note) {
    const text = selectedText(savedRange);
    if (!text) return false;
    post({ kind: "annotation", text, note: note || "", context: selectionContext(savedRange) });
    hideSelectionUI();
    window.getSelection().removeAllRanges();
    savedRange = null;
    return true;
  }

  // ⌘D from the app menu: saves the live selection, if there is one. Returns whether it did.
  window.__grapheneAnnotateSave = () => {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.rangeCount || !sel.toString().trim()) return false;
    savedRange = sel.getRangeAt(0).cloneRange();
    return commit("");
  };

  document.addEventListener("mouseup", (e) => {
    if (e.composedPath().includes(host)) return;
    setTimeout(() => {
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed || !sel.toString().trim()) { if (editor.style.display === "none") hideSelectionUI(); return; }
      savedRange = sel.getRangeAt(0).cloneRange();
      editor.style.display = "none"; editing = null;
      hideNoteUI();
      showBar(savedRange);
    }, 10);
  });

  saveBtn.addEventListener("click", () => commit(""));
  noteBtn.addEventListener("click", () => { if (savedRange) showEditor(rectOf(savedRange.getBoundingClientRect()), ""); });
  askBtn.addEventListener("click", () => {
    const text = selectedText(savedRange);
    if (!text) return;
    post({ kind: "ask", text: text.slice(0, 8000) });
    hideSelectionUI();
  });
  const saveEditor = () => {
    if (editing) {
      const known = notes.get(editing.id);
      if (known) known.note = ta.value;
      post({ kind: "noteEdit", id: editing.id, note: ta.value });
      hideSelectionUI();
    } else commit(ta.value);
  };
  editorSave.addEventListener("click", saveEditor);
  ta.addEventListener("keydown", (e) => {
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); hideSelectionUI(); }
    else if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); saveEditor(); }
  });

  document.addEventListener("mousedown", (e) => {
    if (e.composedPath().includes(host)) return;
    if (bar.style.display !== "none" && editor.style.display === "none") hideSelectionUI();
    if (noteCard.style.display !== "none") hideNoteUI();
  });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") hideAll(); });

  document.addEventListener("copy", () => {
    const t = String(window.getSelection() || "").trim();
    if (t) post({ kind: "copy", text: t });
  });

  // MARK: saved marks (drawn by cite.js with data-graphene-kind="note")

  // Mark id ("note:<uuid>") → {id, quote, note}, for this page.
  const notes = new Map();
  const noteMarks = (id) => Array.from(document.querySelectorAll('mark[data-graphene-kind="note"]'))
    .filter((mark) => mark.getAttribute("data-graphene-cite") === id);
  const unwrap = (mark) => {
    const parent = mark.parentNode;
    if (!parent) return;
    while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
    parent.removeChild(mark);
    parent.normalize();
  };
  let hoveredID = null, dotID = null, dotTimer = null;

  // list: [{id, quote, note}], the page's saved notes. Marks of notes no longer listed go.
  window.__grapheneAnnotateNotes = (list) => {
    notes.clear();
    for (const item of list || []) notes.set(String(item.id), { id: String(item.id), quote: item.quote || "", note: item.note || "" });
    document.querySelectorAll('mark[data-graphene-kind="note"]').forEach((mark) => {
      if (!notes.has(mark.getAttribute("data-graphene-cite"))) unwrap(mark);
    });
    if (dotID && !notes.has(dotID)) hideNoteUI();
  };

  // Hover raises every segment of the note's mark to highlightActive (cite.js fades it over 120ms).
  const setHover = (id, on) => noteMarks(id).forEach((mark) => { mark.style.backgroundColor = on ? theme.highlightActive : ""; });
  function hideDot() {
    clearTimeout(dotTimer);
    dot.style.display = "none";
    dotID = null;
  }
  // The dot sits in the page margin, `gap` left of the line's left edge, centred on the line.
  function showDot(id, mark) {
    clearTimeout(dotTimer);
    const line = mark.getClientRects()[0] || mark.getBoundingClientRect();
    const block = mark.parentElement?.closest("p,li,dd,dt,blockquote,figcaption,td,th,h1,h2,h3,h4,h5,h6,pre,div,article,section,main,body") || document.body;
    const edge = Math.min(block.getBoundingClientRect().left, line.left);
    const left = Math.max(2, edge - theme.gap - theme.dot) - DOT_PAD;
    const top = line.top + line.height / 2 - theme.dot / 2 - DOT_PAD;
    dotID = id;
    dot.style.left = `${left + scrollX}px`; dot.style.top = `${top + scrollY}px`;
    dot.dataset.lineBottom = String(line.bottom + scrollY);
    const reduced = reducedMotion();
    dot.style.transition = "none";
    dot.style.opacity = "0"; dot.style.transform = reduced ? "none" : "scale(0.6)";
    dot.style.display = "block";
    void dot.offsetWidth;
    dot.style.transition = reduced ? FADE : DOT_SPRING;
    dot.style.opacity = "1"; dot.style.transform = "scale(1)";
  }
  const scheduleDotHide = () => {
    clearTimeout(dotTimer);
    dotTimer = setTimeout(() => { if (noteCard.style.display === "none") hideDot(); }, 700);
  };
  dot.addEventListener("mouseenter", () => clearTimeout(dotTimer));
  dot.addEventListener("mouseleave", scheduleDotHide);

  // cite.js's hover hook: the pointer entered a mark ({id, kind, mark}) or left the last one.
  document.addEventListener("graphene-mark-hover", (event) => {
    const detail = event.detail || {};
    if (hoveredID) setHover(hoveredID, false);
    hoveredID = null;
    if (detail.kind === "note" && detail.id && notes.has(detail.id) && detail.mark) {
      hoveredID = detail.id;
      setHover(hoveredID, true);
      if (dotID !== detail.id || noteCard.style.display === "none") { noteCard.style.display = "none"; showDot(detail.id, detail.mark); }
    } else if (dotID) scheduleDotHide();
  });

  dot.addEventListener("mousedown", (e) => e.preventDefault());
  // The note card: anchored to the margin under the line, 320 wide.
  dot.addEventListener("click", () => {
    const note = dotID && notes.get(dotID);
    if (!note) return;
    clearTimeout(dotTimer);
    noteText.textContent = note.note;
    noteText.style.display = note.note ? "block" : "none";
    noteQuote.textContent = note.quote;
    const size = measure(noteCard, "flex");
    const v = view();
    const left = parseFloat(dot.style.left) + DOT_PAD - scrollX;
    const top = Number(dot.dataset.lineBottom) - scrollY + theme.gap;
    put(noteCard, { left: clamp(left, theme.gap, Math.max(theme.gap, v.width - size.width - theme.gap)), top });
    reveal(noteCard, "flex");
  });
  // Edit opens the editor where the card was: below the marked line, never over it.
  editBtn.addEventListener("click", () => {
    const note = dotID && notes.get(dotID);
    if (!note) return;
    const r = noteCard.getBoundingClientRect();
    hideNoteUI();
    editing = { id: note.id };
    ta.value = note.note;
    measure(editor, "flex");
    put(editor, { left: r.left, top: r.top });
    reveal(editor, "flex");
    ta.focus();
  });
  openBtn.addEventListener("click", () => {
    const id = dotID;
    hideNoteUI();
    if (id) post({ kind: "noteOpen", id });
  });
})();
