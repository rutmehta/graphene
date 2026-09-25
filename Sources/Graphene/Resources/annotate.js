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

  window.__grapheneReadable = () => {
    const clone = document.body?.cloneNode(true);
    if (!clone) return { title: document.title, text: '', selection: '', byline: '', published: '', headings: [] };
    clone.querySelectorAll('nav,footer,header,aside,script,style,noscript,form,input,textarea,[contenteditable],[hidden],[aria-hidden="true"],[data-graphene]').forEach(e => e.remove());
    // textContent runs blocks together ("…material.Graphene…"); space them as the page shows them.
    clone.querySelectorAll('address,article,aside,blockquote,br,dd,div,dl,dt,figcaption,figure,h1,h2,h3,h4,h5,h6,hr,li,ol,p,pre,section,table,td,th,tr,ul').forEach(e => { e.before(' '); e.after(' '); });
    const candidates = [...clone.querySelectorAll('article,main,[role="main"],section')];
    const score = e => (e.textContent || '').length - [...e.querySelectorAll('a')].reduce((n, a) => n + a.textContent.length, 0) * 2;
    const main = candidates.sort((a, b) => score(b) - score(a))[0] || clone;
    return { title: document.title, text: (main.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 40000),
      selection: String(getSelection() || '').slice(0, 8000),
      byline: document.querySelector('meta[name="author"]')?.content || '',
      published: document.querySelector('meta[property="article:published_time"]')?.content || document.querySelector('time[datetime]')?.dateTime || '',
      headings: [...main.querySelectorAll('h1,h2,h3')].map(e => e.textContent.trim()).slice(0, 40) };
  };

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
