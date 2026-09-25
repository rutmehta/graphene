(() => {
  if (window.__grapheneZapCancel) { window.__grapheneZapCancel(); return; }
  let target, outline;
  const clear = () => { if (target) target.style.outline = outline; target = null; };
  const cancel = () => {
    clear(); document.removeEventListener('mouseover', hover, true);
    document.removeEventListener('click', pick, true); document.removeEventListener('keydown', key, true);
    delete window.__grapheneZapCancel;
  };
  const hover = e => { clear(); target = e.target; outline = target.style.outline; target.style.outline = '2px solid currentColor'; };
  const key = e => { if (e.key === 'Escape') { e.preventDefault(); cancel(); } };
  const pick = e => {
    e.preventDefault(); e.stopImmediatePropagation();
    let node = e.target, parts = [];
    while (node && node.nodeType === 1 && node !== document.documentElement) {
      if (node.id) { parts.unshift('#' + CSS.escape(node.id)); break; }
      const tag = node.localName;
      const siblings = Array.from(node.parentElement.children).filter(n => n.localName === tag);
      parts.unshift(tag + ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')'); node = node.parentElement;
    }
    const selector = parts.join(' > '); cancel();
    if (selector) window.webkit.messageHandlers.graphene.postMessage({kind:'zap', selector});
  };
  document.addEventListener('mouseover', hover, true); document.addEventListener('click', pick, true);
  document.addEventListener('keydown', key, true); window.__grapheneZapCancel = cancel;
})();
