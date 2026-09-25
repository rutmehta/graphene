#!/usr/bin/env python3
"""Generate a bounded network-only EasyList subset. No runtime downloads.
Source: EasyList, GPL-3.0-or-later (https://easylist.to/pages/licence.html).
Only unconditional domain anchors are supported; never discard exceptions.
"""
import json
import hashlib
import re
import urllib.request
from pathlib import Path

SOURCE = 'https://raw.githubusercontent.com/easylist/easylist/master/easylist/easylist_adservers.txt'
text = urllib.request.urlopen(SOURCE, timeout=60).read().decode('utf-8')
domains = []
for line in text.splitlines():
    match = re.fullmatch(r'\|\|([a-z0-9.-]+)\^(?:\$third-party)?', line)
    if match and '.' in match[1]:
        domains.append(match[1])
# Keep common ad networks, then sample the full source deterministically instead
# of shipping only the alphabetically early domains. Every entry is source-backed.
priority = ('doubleclick.net', 'amazon-adsystem.com', 'adnxs.com', 'adsrvr.org',
            'criteo.com', 'taboola.com', 'outbrain.com', 'pubmatic.com',
            'rubiconproject.com', 'openx.net', 'casalemedia.com', 'advertising.com',
            'adform.net', 'smartadserver.com', 'googlesyndication.com')
domains = sorted(set(domains), key=lambda d: (not any(d == p or d.endswith('.' + p) for p in priority), hashlib.sha256(d.encode()).hexdigest()))[:2000]
if len(domains) < 1900:
    raise RuntimeError(f'Unexpected source format: only {len(domains)} domain rules')
rules = [{'trigger': {'url-filter': r'^https?://([^/]+\.)?' + re.escape(d) + r'[:/]',
                      'load-type': ['third-party']}, 'action': {'type': 'block'}} for d in domains]
output = Path(__file__).resolve().parents[1] / 'Sources/Graphene/Resources/blocklist.json'
encoded = json.dumps(rules, separators=(',', ':')).encode()
assert len(encoded) < 1_500_000
output.write_bytes(encoded)
print(f'{len(rules)} rules, {len(encoded)} bytes, source {SOURCE}')
