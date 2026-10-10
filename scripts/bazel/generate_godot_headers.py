#!/usr/bin/env python3
"""Generate official Godot headers without compiling the engine or plugin."""

import argparse
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tarfile
import tempfile


GENERATED = (
    "core/disabled_classes.gen.h", "core/version_generated.gen.h",
    "core/object/gdvirtual.gen.h", "core/extension/ext_wrappers.gen.h",
    "core/extension/gdextension_interface_dump.gen.h", "core/extension/gdextension_interface.gen.h",
)


def export_headers(source, output, version):
    values = runpy.run_path(str(source / "version.py"))
    actual = ".".join(str(values[key]) for key in ("major", "minor", "patch"))
    if actual != version:
        raise ValueError("Godot headers must match " + version + ", found " + actual)
    for name in GENERATED:
        if not (source / name).is_file():
            raise ValueError("SCons did not produce the declared engine header: " + name)
    output.mkdir(parents=True, exist_ok=True)
    for name in ("LICENSE.txt", "COPYRIGHT.txt"):
        shutil.copyfile(source / name, output / name)
    for path in sorted(source.rglob("*")):
        if path.is_file() and path.suffix in {".h", ".hpp", ".inc", ".inl"}:
            destination = output / path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)


def generate(archive, output, version, scons):
    archive, output, scons = archive.resolve(), output.resolve(), scons.absolute()
    with tempfile.TemporaryDirectory(prefix="godot-header-source-") as temporary:
        stage = Path(temporary)
        with tarfile.open(archive) as compressed:
            compressed.extractall(stage, filter="data")
        candidates = [path.parent for path in stage.glob("*/version.py")]
        if len(candidates) != 1:
            raise ValueError("Expected one official Godot source root")
        source = candidates[0]
        values = runpy.run_path(str(source / "version.py"))
        if ".".join(str(values[key]) for key in ("major", "minor", "patch")) != version:
            raise ValueError("The source archive differs from the pinned Godot version")
        # Each declared Python tool owns its runfiles; do not inherit the
        # generator launcher's runfiles directory when starting SCons.
        environment = {key: value for key, value in os.environ.items()
                       if key not in {'RUNFILES_DIR', 'RUNFILES_MANIFEST_FILE', 'JAVA_RUNFILES'}}
        subprocess.run([str(scons), "-Q", "-j2", "platform=ios", "target=template_release", "arch=arm64", *GENERATED], cwd=source, env=environment, check=True)
        export_headers(source, output, version)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--scons", type=Path, required=True)
    args = parser.parse_args()
    generate(args.archive, args.output, args.version, args.scons)


if __name__ == "__main__":
    main()
