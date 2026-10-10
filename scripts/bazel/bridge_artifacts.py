#!/usr/bin/env python3
"""Package compiler-owned bridge products without changing their language code."""

import argparse
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile


ANDROID = "http://schemas.android.com/apk/res/android"


def manifest(source, output, package, placeholders):
    ET.register_namespace("android", ANDROID)
    contents = source.read_text()
    for value in placeholders:
        key, replacement = value.split("=", 1)
        contents = contents.replace("${" + key + "}", replacement)
    if "${" in contents:
        raise ValueError("Unresolved Android bridge manifest placeholder")
    tree = ET.fromstring(contents)
    tree.set("package", package)
    minimum = tree.find("uses-sdk")
    if minimum is None:
        minimum = ET.SubElement(tree, "uses-sdk")
    minimum.set("{" + ANDROID + "}minSdkVersion", "23")
    minimum.set("{" + ANDROID + "}targetSdkVersion", "36")
    output.write_bytes(ET.tostring(tree, encoding="utf-8", xml_declaration=True))


def aar(source, output, consumer_rules=None):
    with zipfile.ZipFile(source) as archive:
        entries = {name: archive.read(name) for name in archive.namelist() if not name.endswith("/")}
    if not entries.get("classes.jar") or not entries.get("AndroidManifest.xml"):
        raise ValueError("The Kotlin compiler/resource target must provide classes.jar and AndroidManifest.xml")
    if consumer_rules:
        entries["proguard.txt"] = consumer_rules.read_bytes()
    entries["META-INF/com/android/build/gradle/aar-metadata.properties"] = (
        b"aarFormatVersion=1.0\naarMetadataVersion=1.0\nminCompileSdk=1\nminCompileSdkExtension=0\n"
        b"minAndroidGradlePluginVersion=1.0.0\ncoreLibraryDesugaringEnabled=false\n")
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("manifest", "aar"):
        sub = commands.add_parser(command)
        sub.add_argument("--input", type=Path, required=True)
        sub.add_argument("--output", type=Path, required=True)
        if command == "manifest":
            sub.add_argument("--package", required=True)
            sub.add_argument("--placeholder", action="append", default=[])
        else:
            sub.add_argument("--consumer-rules", type=Path)
    args = parser.parse_args()
    if args.command == "manifest":
        manifest(args.input, args.output, args.package, args.placeholder)
    else:
        aar(args.input, args.output, args.consumer_rules)


if __name__ == "__main__":
    main()
