#!/usr/bin/env python3
"""Retain upstream dist, but produce a deployable bundle using our same-origin API."""
import argparse
import hashlib
from pathlib import Path
import shutil

ORIGINAL_API = "https://67da0a9e35c87309f52ac061.mockapi.io/api/v1/tasks"


def prepare(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if destination == source or source.is_relative_to(destination) or destination.is_relative_to(source):
        raise ValueError("Source and output directories must be separate")
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    index = (destination / "index.html").read_text()
    substitutions = 0
    for path in sorted((destination / "assets").glob("*.js")):
        original = path.read_text()
        count = original.count(ORIGINAL_API)
        if not count:
            continue
        updated = original.replace(ORIGINAL_API, "/api/v1/tasks")
        # The upstream list fetches only when mounted. Refresh after mutations
        # so its initial fetch runs again with the persisted data.
        for before, after in [
            ('await s(v),c(-1),i({title:', 'await s(v),window.location.assign("/"),i({title:'),
            ('await c(o,m),s("/"),i({title:', 'await c(o,m),window.location.assign("/"),i({title:'),
            ('onClick:_=>{_.stopPropagation(),i(S.id)},', 'onClick:async _=>{_.stopPropagation(),await i(S.id),window.location.assign("/")},'),
        ]:
            if updated.count(before) != 1:
                raise ValueError("Upstream mutation code changed; review the list-refresh patch")
            updated = updated.replace(before, after)
        new_name = "index-" + hashlib.sha256(updated.encode()).hexdigest()[:12] + ".js"
        (path.parent / new_name).write_text(updated)
        index = index.replace(path.name, new_name)
        path.unlink()
        substitutions += count
    if substitutions != 5:
        raise ValueError(f"Expected five known API references; found {substitutions}. Review upstream changes.")
    (destination / "index.html").write_text(index)
    print(f"Prepared {destination}; replaced five API references and updated the JS content hash")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="dist")
    parser.add_argument("--output", default="out/static")
    args = parser.parse_args()
    prepare(args.source, args.output)
