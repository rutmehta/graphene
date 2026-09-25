(() => {
    const query = QUERY_VALUE;
    const backwards = BACKWARDS_VALUE;
    const selection = window.getSelection();
    if (!query || !document.body || !selection) { window.__grapheneFind = null; return {current: 0, total: 0}; }
    const saved = [];
    for (let i = 0; i < selection.rangeCount; i++) saved.push(selection.getRangeAt(i).cloneRange());
    const start = document.createRange(); start.selectNodeContents(document.body); start.collapse(true);
    selection.removeAllRanges(); selection.addRange(start);
    const ranges = [];
    // WebKit's own text finder handles inline nodes, hidden text and word boundaries.
    // Never wrap or search frames: the counter and selected range share the same scope.
    while (window.find(query, false, false, false, false, false, false)) {
        if (!selection.rangeCount) break;
        const range = selection.getRangeAt(0).cloneRange();
        const last = ranges[ranges.length - 1];
        if (last && last.compareBoundaryPoints(Range.START_TO_START, range) === 0 && last.compareBoundaryPoints(Range.END_TO_END, range) === 0) break;
        ranges.push(range);
    }
    const old = window.__grapheneFind;
    const total = ranges.length;
    const index = old && old.query === query && old.total === total
        ? (old.index + (backwards ? -1 : 1) + total) % total
        : (backwards ? total - 1 : 0);
    selection.removeAllRanges();
    if (total) {
        const range = ranges[index]; selection.addRange(range);
        const node = range.startContainer;
        (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement)?.scrollIntoView({block: 'center', inline: 'nearest'});
    } else saved.forEach(range => selection.addRange(range));
    window.__grapheneFind = {query, total, index};
    return {current: total ? index + 1 : 0, total};
})();
