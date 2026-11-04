#!/usr/bin/env python3
"""Build a revision-pinned, native gitcommit parser bundle for Neovim."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import resource
import shutil
import signal
import subprocess
import tarfile
import tempfile
import urllib.request

PARSER_REVISION = "55a265cf763ec15d6e2d96bb206e3f5e30d82bae"
PLUGIN_REVISION = "ca581c3436fc2b236847f5b739ebc263739e5ca6"
SOURCES = (
    ("gbprod/tree-sitter-gitcommit", PARSER_REVISION,
     "ccf8c3aaf5d6d9885433e4f3bc34c80d39cc40894c24b44b5a712ee50cf92e0b"),
    ("nvim-treesitter/nvim-treesitter", PLUGIN_REVISION,
     "aa871691f9f943d1926cef70ecb725dc0c83dc6ac5f036da95f9a03e975f58c4"),
)
MEMORY_LIMIT = 1536 * 1024 * 1024


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def download_source(parent, repository, revision, expected_hash):
    url = f"https://codeload.github.com/{repository}/tar.gz/{revision}"
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read(16 * 1024 * 1024 + 1)
    if hashlib.sha256(data).hexdigest() != expected_hash:
        raise ValueError(f"Archive checksum mismatch: {repository}@{revision}")
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        archive.extractall(parent, filter="data")
    source = parent / f"{repository.split('/')[-1]}-{revision}"
    if not source.is_dir():
        raise ValueError(f"Missing archive root: {source.name}")
    return source


def limit_compiler():
    resource.setrlimit(resource.RLIMIT_AS, (MEMORY_LIMIT, MEMORY_LIMIT))


def compile_parser(source, output):
    # Optimizing this generated parser can use more than 4 GiB. Commit messages
    # are small; -O0 avoids that build cost. The limit also protects future changes.
    src = source / "src"
    command = ["cc", "-std=c11", "-O0", "-fPIC", "-I", str(src), "-shared",
               str(src / "parser.c"), str(src / "scanner.c"), "-o", str(output)]
    process = subprocess.Popen(command, start_new_session=True, preexec_fn=limit_compiler)
    try:
        code = process.wait(timeout=180)
    except subprocess.TimeoutExpired:
        # Stop the compiler's children too, so a timeout cannot leave cc1 running.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        raise
    if code:
        raise subprocess.CalledProcessError(code, command)


def build(output_dir):
    machine = platform.machine()
    if machine not in {"x86_64", "aarch64"}:
        raise ValueError(f"Unsupported machine: {machine}")
    output_dir = output_dir.resolve()
    target = output_dir / machine
    if target.exists() or target.is_symlink():
        raise FileExistsError(f"Use an empty output directory; refusing to replace {target}")
    output_dir.mkdir(parents=True, exist_ok=True)
    # Keep staging on the destination filesystem for atomic publication, including NFS.
    with tempfile.TemporaryDirectory(prefix=".gitcommit-build-", dir=output_dir) as temporary:
        work = Path(temporary)
        parser_source, plugin_source = [download_source(work, *spec) for spec in SOURCES]
        bundle = work / "bundle"
        (bundle / "parser").mkdir(parents=True)
        (bundle / "queries/gitcommit").mkdir(parents=True)
        (bundle / "licenses").mkdir()
        library = bundle / "parser/gitcommit.so"
        compile_parser(parser_source, library)
        queries = {}
        for name in ("highlights.scm", "injections.scm"):
            destination = bundle / "queries/gitcommit" / name
            shutil.copyfile(plugin_source / "runtime/queries/gitcommit" / name, destination)
            queries[name] = sha256(destination)
        for source, name in ((parser_source, "tree-sitter-gitcommit"),
                             (plugin_source, "nvim-treesitter")):
            shutil.copyfile(source / "LICENSE", bundle / "licenses" / f"{name}.txt")
        manifest = {
            "schema_version": 1, "language": "gitcommit", "machine": machine,
            "parser_revision": PARSER_REVISION, "nvim_treesitter_revision": PLUGIN_REVISION,
            "parser_sha256": sha256(library), "query_sha256": queries,
        }
        (bundle / "manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        bundle.rename(target)
    print(json.dumps({"status": "built", "bundle": str(target), **manifest}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    build(parser.parse_args().output_dir)
