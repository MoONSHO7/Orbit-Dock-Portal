"""Materialize Portal's immutable .pkgmeta Git dependencies without replacing local links."""

import argparse
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]


def linked(path):
    try:
        details = path.lstat()
    except FileNotFoundError:
        return False
    return stat.S_ISLNK(details.st_mode) or bool(
        getattr(details, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
    )


def plain_tree(path):
    if linked(path):
        raise ValueError(f"Expected an ordinary directory: {path}")
    if not path.is_dir():
        raise ValueError(f"Expected an existing directory: {path}")
    for child in path.iterdir():
        if linked(child):
            raise ValueError(f"Refusing to replace a directory containing a link: {child}")
        if child.is_dir():
            plain_tree(child)


def relative_path(value):
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts or ":" in value or "\\" in value:
        raise ValueError(f"Invalid dependency path: {value!r}")
    return path


def dependencies(root):
    externals = {}
    active = False
    current = None
    for line in (root / ".pkgmeta").read_text(encoding="utf-8").splitlines():
        if line == "externals:":
            active = True
            continue
        if not active or not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            break
        destination = re.fullmatch(r"  ([^\s:]+):", line)
        field = re.fullmatch(r"    (url|commit|path): ([^\s]+)", line)
        if destination:
            current = destination.group(1)
            if current in externals or not current.startswith("Libs/"):
                raise ValueError(f"Invalid or duplicate external destination: {current}")
            relative_path(current)
            externals[current] = {}
        elif field and current:
            key, value = field.groups()
            if key in externals[current]:
                raise ValueError(f"Duplicate external field: {current}.{key}")
            externals[current][key] = value
        else:
            raise ValueError(f"Unsupported .pkgmeta external declaration: {line}")
    if not externals:
        raise ValueError("No pinned .pkgmeta externals were found")
    for destination, external in externals.items():
        if set(external) != {"url", "commit", "path"}:
            raise ValueError(f"External needs url, commit and path: {destination}")
        if not re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", external["url"]):
            raise ValueError(f"External must use a GitHub HTTPS URL: {destination}")
        if not re.fullmatch(r"[0-9a-f]{40}", external["commit"]):
            raise ValueError(f"External must pin a full commit SHA: {destination}")
        relative_path(external["path"])
    return externals


def fetch(root, relative, external, force):
    destination = root / relative
    if linked(destination):
        print(f"Preserved development link: {relative}")
        return
    for parent in destination.parents:
        if parent == root:
            break
        if linked(parent):
            raise ValueError(f"Dependency parent is linked: {parent}")
    if destination.exists():
        plain_tree(destination)
        if not force:
            print(f"Already materialized: {relative}; use --force to refresh ordinary files")
            return
    destination.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    with tempfile.TemporaryDirectory(prefix=".fetch-library-", dir=destination.parent) as temporary:
        temporary = Path(temporary).resolve()
        if not temporary.is_relative_to(root) or not destination.absolute().is_relative_to(root):
            raise ValueError("Dependency staging must remain inside the requested checkout")
        repository = temporary / "git"
        archive = temporary / "source.zip"
        stage = temporary / "staged"
        previous = temporary / "previous"
        subprocess.run(["git", "init", "--quiet", str(repository)], check=True, env=env)
        subprocess.run(
            ["git", "-C", str(repository), "fetch", "--quiet", "--depth=1", external["url"], external["commit"]],
            check=True, env=env,
        )
        subprocess.run(
            ["git", "-c", "core.autocrlf=false", "-c", "core.eol=lf", "-C", str(repository),
             "archive", "--format=zip", "--prefix=archive/",
             f"--output={archive}", f"{external['commit']}:{external['path']}"],
            check=True, env=env,
        )
        stage.mkdir()
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.infolist():
                parts = relative_path(entry.filename).parts
                if not parts or parts[0] != "archive":
                    raise ValueError(f"Unexpected archive path: {entry.filename}")
                if entry.is_dir():
                    continue
                mode = entry.external_attr >> 16
                if mode and not stat.S_ISREG(mode):
                    raise ValueError(f"Dependency archive must contain ordinary files: {entry.filename}")
                target = stage.joinpath(*parts[1:])
                if target == stage:
                    raise ValueError("Dependency archive contains an invalid root file")
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open("xb") as stream:
                    stream.write(bundle.read(entry))
        if not (stage / "LICENSE").is_file() or not (stage / f"{destination.name}.xml").is_file():
            raise ValueError(f"Dependency is missing its license or XML manifest: {relative}")
        if linked(destination):
            raise ValueError(f"Dependency became a development link during fetch: {relative}")
        if destination.exists():
            plain_tree(destination)
            destination.rename(previous)
        try:
            stage.rename(destination)
        except OSError:
            if previous.exists() and not destination.exists():
                previous.rename(destination)
            raise
    print(f"Fetched {relative} at {external['commit']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="Portal checkout containing .pkgmeta")
    parser.add_argument("--force", action="store_true", help="Refresh ordinary dependencies; preserve development links")
    args = parser.parse_args()
    try:
        root = args.root.resolve(strict=True)
        for relative, external in dependencies(root).items():
            fetch(root, relative, external, args.force)
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Portal dependency fetch failed: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
