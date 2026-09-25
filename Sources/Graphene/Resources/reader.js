(() => {
  const source = document.querySelector('article, main') || document.body;
  const c = source ? source.cloneNode(true) : null;
  if (!c) return '';
  c.querySelectorAll('script,style,noscript,svg,canvas,nav,footer,header,aside,iframe,form,figure,.infobox,.mw-editsection,.hatnote,[data-graphene]').forEach(n => n.remove());
  c.querySelectorAll('p,li,h1,h2,h3,h4,section,div,br').forEach(n => n.appendChild(document.createTextNode('\n\n')));
  return (c.textContent || '').split('\n').map(line => line.trim()).join('\n').replace(/\n{3,}/g, '\n\n').trim().slice(0, 60000);
})()
