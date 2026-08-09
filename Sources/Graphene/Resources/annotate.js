// Graphene annotation affordance.
// Injected at document-end into the main frame. All UI lives in a Shadow DOM
// overlay so the host page's CSS and CSP can't interfere, and all styling is set
// via CSSOM properties (not injected <style>/inline strings, which strict-CSP
// sites block).
(() => {
  if (window.__grapheneAnnotate) return;
  window.__grapheneAnnotate = true;

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

  // Floating action shown on selection.
  const bar = makeEl("div", {
    position: "absolute", display: "none", alignItems: "center", gap: "6px",
    padding: "5px 6px 5px 10px", borderRadius: "9px",
    background: "rgba(28,28,30,0.96)", color: "#F2F2F7",
    font: `500 12px ${baseFont}`, boxShadow: "0 6px 22px rgba(0,0,0,0.32)",
    border: "1px solid rgba(255,255,255,0.10)", cursor: "default",
    userSelect: "none", whiteSpace: "nowrap",
  });
  const label = makeEl("span", { opacity: "0.9" }, "Save to Graphene");
  const noteBtn = makeEl("button", {
    font: `500 12px ${baseFont}`, color: "#F2F2F7", background: "transparent",
    border: "1px solid rgba(255,255,255,0.16)", borderRadius: "6px",
    padding: "3px 8px", cursor: "pointer",
  }, "Add note");
  const saveBtn = makeEl("button", {
    font: `600 12px ${baseFont}`, color: "#1c1c1e", background: "#F2F2F7",
    border: "none", borderRadius: "6px", padding: "3px 10px", cursor: "pointer",
  }, "Save");
  bar.append(label, noteBtn, saveBtn);
  root.appendChild(bar);

  // Note editor (revealed by "Add note").
  const editor = makeEl("div", {
    position: "absolute", display: "none", flexDirection: "column", gap: "8px",
    padding: "10px", borderRadius: "10px", width: "260px",
    background: "rgba(28,28,30,0.98)", border: "1px solid rgba(255,255,255,0.10)",
    boxShadow: "0 10px 30px rgba(0,0,0,0.4)",
  });
  const ta = makeEl("textarea", {
    font: `400 12px ${baseFont}`, color: "#F2F2F7", background: "rgba(255,255,255,0.06)",
    border: "1px solid rgba(255,255,255,0.14)", borderRadius: "7px", padding: "7px 9px",
    resize: "none", height: "64px", outline: "none",
  });
  ta.setAttribute("placeholder", "Note (optional)…");
  const editorSave = makeEl("button", {
    alignSelf: "flex-end", font: `600 12px ${baseFont}`, color: "#1c1c1e",
    background: "#F2F2F7", border: "none", borderRadius: "6px", padding: "4px 12px", cursor: "pointer",
  }, "Save annotation");
  editor.append(ta, editorSave);
  root.appendChild(editor);

  let savedRange = null;

  function selectionContext(range) {
    const container = range.commonAncestorContainer;
    const block = (container.nodeType === 1 ? container : container.parentElement)?.closest("p,li,article,section,div,main,body");
    return (block?.innerText || "").replace(/\s+/g, " ").trim().slice(0, 500);
  }

  function place(el, rect) {
    el.style.display = el === editor ? "flex" : "inline-flex";
    const top = window.scrollY + rect.bottom + 8;
    const left = Math.max(8, window.scrollX + rect.left);
    el.style.top = `${top}px`;
    el.style.left = `${left}px`;
  }

  function hideAll() { bar.style.display = "none"; editor.style.display = "none"; }

  function highlight(range) {
    try {
      const mark = document.createElement("span");
      mark.style.backgroundColor = "rgba(180,121,79,0.28)";
      mark.style.borderRadius = "2px";
      range.surroundContents(mark);
    } catch (e) { /* selection spans multiple elements — skip visual highlight */ }
  }

  function commit(note) {
    if (!savedRange) return;
    const text = savedRange.toString().trim();
    if (!text) return;
    post({ kind: "annotation", text, note: note || "", context: selectionContext(savedRange) });
    highlight(savedRange);
    hideAll();
    window.getSelection().removeAllRanges();
    savedRange = null;
  }

  document.addEventListener("mouseup", (e) => {
    if (host.contains(e.target)) return;
    setTimeout(() => {
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed || !sel.toString().trim()) { if (editor.style.display === "none") hideAll(); return; }
      savedRange = sel.getRangeAt(0).cloneRange();
      const rect = sel.getRangeAt(0).getBoundingClientRect();
      editor.style.display = "none";
      place(bar, rect);
    }, 10);
  });

  noteBtn.addEventListener("click", () => {
    if (!savedRange) return;
    const rect = savedRange.getBoundingClientRect();
    bar.style.display = "none";
    place(editor, rect);
    ta.value = "";
    ta.focus();
  });
  saveBtn.addEventListener("click", () => commit(""));
  editorSave.addEventListener("click", () => commit(ta.value));

  document.addEventListener("mousedown", (e) => {
    if (!host.contains(e.target) && bar.style.display !== "none" && editor.style.display === "none") hideAll();
  });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") hideAll(); });

  document.addEventListener("copy", () => {
    const t = String(window.getSelection() || "").trim();
    if (t) post({ kind: "copy", text: t });
  });
})();
