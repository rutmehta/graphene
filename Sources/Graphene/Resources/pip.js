(() => {
    window.__graphenePiP = () => {
        const video = [...document.querySelectorAll('video')].filter(v => !v.paused && !v.ended).sort((a,b) => b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight)[0];
        if (!video) return false;
        document.getElementById('graphene-pip-request')?.remove();
        const panel = document.createElement('div'); panel.id = 'graphene-pip-request';
        panel.style.cssText = 'position:fixed;right:20px;top:20px;z-index:2147483647;padding:12px;border:1px solid GrayText;border-radius:10px;background:Canvas;color:CanvasText;font:13px system-ui;display:flex;gap:10px;align-items:center';
        const button = document.createElement('button'); button.textContent = 'Open Picture in Picture';
        button.setAttribute('aria-label', 'Open Picture in Picture');
        const close = document.createElement('button'); close.textContent = 'Cancel'; close.onclick = () => panel.remove();
        button.onclick = async event => {
            if (!event.isTrusted) return;
            try {
                if (video.webkitSupportsPresentationMode?.('picture-in-picture')) {
                    video.webkitSetPresentationMode('picture-in-picture');
                    if (video.webkitPresentationMode === 'picture-in-picture') { panel.remove(); return; }
                }
                if (video.requestPictureInPicture) { await video.requestPictureInPicture(); panel.remove(); return; }
                button.textContent = 'Picture in Picture is unavailable in this WebKit'; button.disabled = true;
            } catch (_) { button.textContent = 'WebKit declined Picture in Picture'; button.disabled = true; }
            close.textContent = 'Close';
        };
        panel.append(button, close); document.body.append(panel); return true;
    };
})();
