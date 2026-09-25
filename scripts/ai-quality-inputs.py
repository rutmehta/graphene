#!/usr/bin/env python3
"""Fetch public source excerpts for the opt-in AnswerQualityTests harness."""
import json
from pathlib import Path
from urllib.request import Request, urlopen
from bs4 import BeautifulSoup

pages = [
    ("https://en.wikipedia.org/wiki/Graphene", "Graphene (Wikipedia)", ["What is graphene, and how does it differ from graphite?", "Who isolated graphene in 2004?"]),
    ("https://raw.githubusercontent.com/swiftlang/swift/main/README.md", "Swift README", ["What is this repository for?", "Summarize the README in three bullets."]),
    ("https://www.nasa.gov/news-release/nasa-reveals-webb-telescopes-first-images-of-unseen-universe/", "NASA Webb first images news", ["What did Webb observe in the atmosphere of WASP-96b?"]),
    ("https://example.org", "Example Domain", ["What is this domain for?"]),
]
rows = []
for url, title, questions in pages:
    with urlopen(Request(url, headers={"User-Agent": "GrapheneQualityCheck/1.0"}), timeout=30) as response:
        raw = response.read().decode("utf-8")
    if url.endswith(".md"):
        text = raw
    else:
        soup = BeautifulSoup(raw, "html.parser")
        for node in soup.select("script,style,nav,footer,header"):
            node.decompose()
        article = soup.select_one(".mw-parser-output") or soup.select_one("article") or soup.body
        text = "\n".join(node.get_text(" ", strip=True) for node in article.select("h1,h2,p,li") if not node.find_parent("table"))
    for question in questions:
        rows.append(dict(url=url, title=title, text=text[:6000], question=question))
output = Path(__file__).resolve().parents[1] / "docs/parity/shots/wp8/inputs.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(rows, indent=2))
print(f"Saved {len(rows)} questions across {len(pages)} pages to {output}")
for row in rows:
    print(row["title"], len(row["text"]), row["question"])
