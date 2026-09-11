"""Validate Portal's declared runtime closure before tagging or packaging."""

import argparse
import hashlib
import json
import posixpath
from pathlib import Path
import xml.etree.ElementTree as ET

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
TOC = "Orbit_Portal.toc"
MANIFEST = "Libs/LibOrbitUI-manifest.json"
ASSETS = ("Orbit.png", "Audio/switch-sound.ogg", "LICENSE")
LIBRARY_ASSETS = {"Libs/LibOrbitUI-1.0/LICENSE"}


def validate(root, release=False):
    root = root.absolute()
    compile_lua = LuaRuntime().eval("function(code, name) assert(loadstring(code, name)) end")
    loaded = set()

    def read(relative):
        relative = posixpath.normpath(str(relative).replace("\\", "/"))
        if relative.startswith(("/", "../")) or relative in (".", "..") or ":" in relative:
            raise ValueError(f"Runtime reference escapes Portal: {relative}")
        path = root / relative
        if release:
            for parent in (path, *path.parents):
                if parent == root:
                    break
                if parent.is_symlink() or (hasattr(parent, "is_junction") and parent.is_junction()):
                    raise ValueError(f"Release dependency must contain ordinary files, not a local link: {relative}")
        return relative, path.read_bytes()

    def visit(relative):
        relative, content = read(relative)
        if relative in loaded:
            raise ValueError(f"Duplicate or cyclic runtime inclusion: {relative}")
        loaded.add(relative)
        if relative.endswith(".xml"):
            for node in ET.fromstring(content).iter():
                if node.tag.rsplit("}", 1)[-1] in ("Script", "Include") and "file" in node.attrib:
                    visit(posixpath.join(posixpath.dirname(relative), node.attrib["file"].replace("\\", "/")))
        elif relative.endswith(".lua"):
            compile_lua(content.decode("utf-8-sig"), "@" + relative)
        else:
            raise ValueError(f"Unsupported runtime entry: {relative}")

    _, toc_bytes = read(TOC)
    toc = toc_bytes.decode("utf-8-sig")
    headers = {}
    for line in toc.splitlines():
        line = line.strip()
        if line.startswith("##") and ":" in line:
            key, value = line[2:].split(":", 1)
            headers[key.strip()] = value.strip()
        elif line and not line.startswith("#"):
            visit(line)
    if headers.get("Interface") != "120100":
        raise ValueError("Portal must target Interface 120100")
    if headers.get("SavedVariables") != "OrbitPortalDB":
        raise ValueError("Portal's standalone store must be declared in SavedVariables")
    for asset in ASSETS:
        read(asset)
    _, content = read(MANIFEST)
    manifest = json.loads(content)
    files = manifest["files"]
    library_files = {name for name in loaded if name.startswith("Libs/LibOrbitUI-1.0/")}
    manifest_library = {name for name in files if name.startswith("Libs/LibOrbitUI-1.0/")}
    if not library_files or library_files | LIBRARY_ASSETS != manifest_library:
        raise ValueError("LibOrbitUI manifest and declared runtime closure differ")
    if "Localization/Generated.lua" not in files or "Localization/Generated.lua" not in loaded:
        raise ValueError("Generated localization must be declared and included in the content manifest")
    for name, digest in files.items():
        _, content = read(name)
        if name not in loaded | LIBRARY_ASSETS or hashlib.sha256(content).hexdigest() != digest:
            raise ValueError(f"Stale or undeclared library/localization manifest entry: {name}")
    revision = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    if revision != manifest["contentRevision"]:
        raise ValueError("LibOrbitUI content revision does not match its file manifest")
    print(f"PASS: {len(loaded)} TOC/XML runtime files, Lua 5.1 syntax, assets and library manifest")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="Portal source or materialized package directory")
    parser.add_argument("--release", action="store_true", help="Reject development symlinks/junctions")
    args = parser.parse_args()
    try:
        validate(args.root, args.release)
    except Exception as error:
        parser.exit(1, f"Portal package validation failed: {error}\n")
