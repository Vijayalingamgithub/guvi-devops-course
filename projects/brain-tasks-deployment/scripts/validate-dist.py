#!/usr/bin/env python3
"""Validate a supplied precompiled React bundle without inventing a source build."""
from html.parser import HTMLParser
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]


class Assets(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "script" and values.get("src"):
            self.refs.append(values["src"])
        if tag == "link" and values.get("rel") == "stylesheet":
            self.refs.append(values.get("href", ""))


def main():
    dist = ROOT / "dist"
    entry = dist / "index.html"
    assert entry.is_file(), "dist/index.html is missing"
    parser = Assets()
    parser.feed(entry.read_text())
    assert parser.refs, "No application JS/CSS assets referenced"
    for ref in parser.refs:
        assert ref and ":" not in ref, f"Unexpected nonlocal application asset: {ref}"
        target = (dist / ref.lstrip("/")).resolve()
        assert target.is_relative_to(dist.resolve()), f"Asset escapes dist: {ref}"
        assert target.is_file() and target.stat().st_size, f"Missing/empty asset: {ref}"
    files = list(dist.rglob("*"))
    assert not any(p.is_symlink() for p in files), "dist must not contain symlinks"
    assert not any(p.suffix in {".map", ".pem", ".key"} for p in files), "Unexpected debug/key file in dist"
    hashes = {str(p.relative_to(dist)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(files) if p.is_file()}
    print(json.dumps({"result": "PASS", "referenced_assets": parser.refs, "sha256": hashes}, indent=2))


if __name__ == "__main__":
    main()
