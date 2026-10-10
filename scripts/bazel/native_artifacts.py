#!/usr/bin/env python3
"""Verify native producers' sdk-artifacts.json and describe Bazel imports.

This consumes the native SDK preparation contract. It does not create a second
receipt: the original manifest remains the provenance and packaging boundary.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import sys
import xml.etree.ElementTree as ET


def relative(value):
    if not isinstance(value, str) or any(character in value for character in "\0\r\n\\"):
        raise ValueError("Artifact paths must be relative POSIX paths on one line")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.as_posix() != value or value in {"", "."}:
        raise ValueError("Unsafe artifact path: " + value)
    return value


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inventory(manifest_path, sdk, expected_revision):
    root = manifest_path.parent.resolve()
    receipt = json.loads(manifest_path.read_text())
    if receipt.get("schemaVersion") != 1 or receipt.get("sdk") != sdk:
        raise ValueError("Expected schemaVersion 1 " + sdk + " sdk-artifacts.json")
    if not re.fullmatch(r"[0-9a-f]{40}", expected_revision) or receipt.get("sourceRevision") != expected_revision:
        raise ValueError("Prepared SDK sourceRevision must equal NATIVE-PINS.json: " + expected_revision)
    if receipt.get("sourceDirty") is not False:
        raise ValueError("Downstream imports require native artifacts from committed source")
    files = {}
    for item in receipt.get("artifacts", []):
        name = relative(item["path"])
        if name in files or name == "sdk-artifacts.json":
            raise ValueError("Duplicate or reserved artifact path: " + name)
        path = root / name
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
            raise ValueError("Missing or unsafe artifact: " + name)
        if not isinstance(item.get("size"), int) or item["size"] != path.stat().st_size:
            raise ValueError("Artifact size changed: " + name)
        if not re.fullmatch(r"[0-9a-f]{64}", item.get("sha256", "")) or sha256(path) != item["sha256"]:
            raise ValueError("Artifact SHA-256 changed: " + name)
        files[name] = item
    if not files:
        raise ValueError("The SDK manifest must inventory its prepared products")
    links = {}
    for item in receipt.get("symlinks", []):
        name = relative(item["path"])
        target = item["target"]
        if name in files or name in links or not isinstance(target, str) or os.path.isabs(target):
            raise ValueError("Duplicate or unsafe artifact symlink: " + name)
        path = root / name
        try:
            destination = path.resolve(strict=True)
        except (OSError, RuntimeError) as error:
            raise ValueError("Broken artifact symlink: " + name) from error
        if not path.is_symlink() or os.readlink(path) != target or not destination.is_relative_to(root):
            raise ValueError("Artifact symlink changed or escapes its products: " + name)
        resolved = destination.relative_to(root).as_posix()
        if resolved not in files and not any(file.startswith(resolved + "/") for file in files):
            raise ValueError("Artifact symlink refers to unverified content: " + name)
        links[name] = target
    return receipt, root, files, links


def rule(kind, **attrs):
    return kind + "(\n" + "".join("    " + key + " = " + repr(value) + ",\n" for key, value in attrs.items()) + ")\n"


def file_reference(value, files):
    name = relative(value)
    if name not in files:
        raise ValueError("Product refers to an uninventoried artifact: " + name)
    return "artifacts/" + name


def directory_references(value, files):
    name = relative(value)
    matches = ["artifacts/" + file for file in files if file.startswith(name + "/")]
    if not matches:
        raise ValueError("Product refers to an empty or uninventoried directory: " + name)
    return sorted(matches)


def ios_build(receipt, root, files):
    runtime = receipt["runtime"]
    runtime_path = relative(runtime["path"])
    if not re.fullmatch(r"[0-9a-f]{64}", runtime.get("checksum", "")) or not re.fullmatch(r"[0-9a-f]{40}", runtime.get("sourceCommit", "")):
        raise ValueError("Prepared iOS SDK must identify its checksum-pinned runtime")
    info = plistlib.loads((root / runtime_path / "Info.plist").read_bytes())
    file_reference(runtime_path + "/Info.plist", files)
    native_frameworks = set()
    lines = [
        'load("@rules_apple//apple:apple.bzl", "apple_dynamic_framework_import", "apple_static_xcframework_import")\n',
        'load("@rules_apple//apple:resources.bzl", "apple_bundle_import")\n',
        'load("@rules_cc//cc:cc_library.bzl", "cc_library")\n',
        'load("@rules_swift//swift:swift.bzl", "swift_import")\n',
        'package(default_visibility = ["//visibility:public"])\n',
    ]
    selections = {"sdk": {}, "framework": {}, "resources": {}}
    identities = set()
    for product in receipt["products"]:
        platform, configuration = product["platform"], product["configuration"]
        if platform not in {"ios-device", "ios-simulator", "macos"} or configuration not in {"Debug", "Release"}:
            raise ValueError("Unsupported prepared iOS platform or configuration")
        if product["module"] != "Nuxie" or product["swiftDependencies"] != ["NuxieRuntime"]:
            raise ValueError("Unexpected prepared SDK Swift module dependencies")
        architectures = product["architectures"]
        if not architectures or len(architectures) != len(set(architectures)) or set(architectures) - {"arm64", "x86_64"}:
            raise ValueError("Unsupported or duplicate prepared iOS architectures")
        if platform == "ios-device" and architectures != ["arm64"]:
            raise ValueError("iOS device products must contain arm64")
        prefix = platform.replace("-", "_") + "_" + configuration.lower()
        framework_files = directory_references(product["framework"], files)
        bundles = product["resourceBundles"]
        if len(bundles) != 1 or PurePosixPath(bundles[0]).name != "Nuxie_Nuxie.bundle":
            raise ValueError("An iOS product must carry its Nuxie_Nuxie.bundle")
        lines.append(rule("apple_bundle_import", name=prefix + "_resources", bundle_imports=directory_references(bundles[0], files)))
        if len(product["nativeDependencies"]) != 1:
            raise ValueError("Expected exactly the pinned NuxieRuntimeC native dependency")
        native = product["nativeDependencies"][0]
        if native["module"] != "NuxieRuntimeC":
            raise ValueError("Unexpected iOS native dependency module")
        native_frameworks.update(native["sdkFrameworks"])
        file_reference(native["library"], files)
        file_reference(native["moduleMap"], files)
        headers = directory_references(native["headers"], files)
        candidates = [item for item in info["AvailableLibraries"]
                      if item["SupportedPlatform"] == ("macos" if platform == "macos" else "ios")
                      and item.get("SupportedPlatformVariant", "") == ("simulator" if platform == "ios-simulator" else "")
                      and set(architectures).issubset(item["SupportedArchitectures"])]
        if len(candidates) != 1:
            raise ValueError("The pinned runtime does not contain one matching platform slice")
        selected = candidates[0]
        slice_root = runtime_path + "/" + selected["LibraryIdentifier"]
        if native["library"] != slice_root + "/" + selected["LibraryPath"] or native["headers"] != slice_root + "/" + selected["HeadersPath"]:
            raise ValueError("Product native dependencies do not match the runtime XCFramework slice")
        lines.append(rule("cc_library", name=prefix + "_native_headers", hdrs=headers, includes=["artifacts/" + native["headers"]]))
        for architecture in architectures:
            identity = (platform, configuration, architecture)
            if identity in identities:
                raise ValueError("Duplicate prepared iOS platform/configuration/architecture")
            identities.add(identity)
            name = prefix + "_" + architecture
            constraints = ["@platforms//os:" + ("macos" if platform == "macos" else "ios"), "@platforms//cpu:" + architecture]
            if platform != "macos":
                constraints.append("@apple_support//constraints:" + ("simulator" if platform == "ios-simulator" else "device"))
            for module in ("NuxieRuntime", "Nuxie"):
                archives = [item for item in product["staticLibraries"] if item["module"] == module and item["architecture"] == architecture]
                modules = [item for item in product["swiftModules"] if item["module"] == module and item["architecture"] == architecture]
                if len(archives) != 1 or len(modules) != 1:
                    raise ValueError("Each architecture must have exactly one " + module + " archive and Swift module")
                module_file = file_reference(modules[0]["path"], files)
                archive_file = file_reference(archives[0]["path"], files)
                dependencies = [":runtime"] if module == "NuxieRuntime" else [":" + name + "_NuxieRuntime"]
                if module == "Nuxie":
                    swift_headers = [item for item in product["swiftHeaders"] if item["module"] == module and item["architecture"] == architecture]
                    if len(swift_headers) != 1:
                        raise ValueError("The owning SDK Swift header is missing")
                    header = file_reference(swift_headers[0]["path"], files)
                    lines.append(rule("cc_library", name=name + "_headers", hdrs=[header], includes=[str(PurePosixPath(header).parent)], target_compatible_with=constraints))
                    dependencies.append(":" + name + "_headers")
                lines.append(rule("swift_import", name=name + "_" + module, module_name=module, swiftmodule=module_file, archives=[archive_file], deps=dependencies, data=[":" + prefix + "_resources"], target_compatible_with=constraints))
                if module == "NuxieRuntime":
                    # The dynamic SDK already links its runtime. Preserve its
                    # compile imports without linking the static archives again.
                    lines.append(rule("swift_import", name=name + "_runtime_compile", module_name=module, swiftmodule=module_file, deps=[":" + prefix + "_native_headers"], target_compatible_with=constraints))
            lines.append(rule("apple_dynamic_framework_import", name=name + "_framework", framework_imports=framework_files, deps=[":" + name + "_runtime_compile"], target_compatible_with=constraints))
            for mode in (["opt"] if configuration == "Release" else ["dbg", "fastbuild"]):
                setting = name + "_" + mode
                lines.append(rule("config_setting", name=setting, constraint_values=constraints, values={"compilation_mode": mode}))
                selections["sdk"][":" + setting] = ":" + name + "_Nuxie"
                selections["framework"][":" + setting] = ":" + name + "_framework"
                selections["resources"][":" + setting] = ":" + prefix + "_resources"
    if not identities:
        raise ValueError("The prepared iOS SDK contains no products")
    lines.insert(5, rule("apple_static_xcframework_import", name="runtime", xcframework_imports=directory_references(runtime_path, files), sdk_frameworks=sorted(native_frameworks)))
    for name, selections_by_setting in selections.items():
        lines.append("alias(name = " + repr(name) + ", actual = select(" + repr(selections_by_setting) + ', no_match_error = "Prepare the selected iOS platform, architecture, and Debug/Release configuration first"))\n')
    return "".join(lines)


def android_build(receipt, root, files, dependencies):
    if receipt["runtime"].get("mode") != "published":
        raise ValueError("Downstream Android imports require the checksum-pinned published runtime")
    if not re.fullmatch(r"[0-9a-f]{64}", receipt["runtime"].get("checksum", "")):
        raise ValueError("The Android runtime checksum is missing")
    maven = receipt["maven"]
    if (maven["groupId"], maven["artifactId"], maven["version"]) != ("ai.nuxie", "nuxie-android", "0.2.0-" + receipt["sourceRevision"]):
        raise ValueError("Downstream Maven artifacts must use the source-addressed SDK coordinate")
    prefix = "ai/nuxie/nuxie-android/" + maven["version"] + "/nuxie-android-" + maven["version"]
    aar = file_reference(prefix + ".aar", files)
    file_reference(prefix + ".pom", files)
    file_reference(prefix + ".module", files)
    pom = ET.fromstring((root / (prefix + ".pom")).read_bytes())
    namespace = {"m": "http://maven.apache.org/POM/4.0.0"}
    required = []
    for item in pom.findall("m:dependencies/m:dependency", namespace):
        fields = [item.findtext("m:" + key, namespaces=namespace) for key in ("groupId", "artifactId", "version", "scope")]
        if any(value is None for value in fields) or fields[3] not in {"compile", "runtime"}:
            raise ValueError("Unsupported native SDK POM dependency")
        coordinate = ":".join(fields[:3])
        if coordinate not in dependencies:
            raise ValueError("Declare the producer POM dependency in android_dependencies: " + coordinate)
        required.append(dependencies[coordinate])
    if len(required) != len(set(required)):
        raise ValueError("POM coordinates must have distinct Bazel dependency labels")
    return ('load("@rules_android//android:rules.bzl", "aar_import")\n'
            'package(default_visibility = ["//visibility:public"])\n'
            + rule("aar_import", name="sdk", aar=aar, deps=required)
            + rule("filegroup", name="maven", srcs=["artifacts/" + path for path in sorted(files)]))


def verify(manifest_path, sdk, expected_revision, dependencies=None):
    receipt, root, files, links = inventory(manifest_path, sdk, expected_revision)
    build = ios_build(receipt, root, files) if sdk == "ios" else android_build(receipt, root, files, dependencies or {})
    build += 'exports_files(["sdk-artifacts.json"])\n'
    build += rule("filegroup", name="artifacts", srcs=["artifacts/" + name for name in sorted(files)])
    return {"files": sorted(files), "symlinks": links, "build": build}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--sdk", choices=("ios", "android"), required=True)
    parser.add_argument("--expected-revision", required=True)
    parser.add_argument("--android-dependency", action="append", default=[])
    args = parser.parse_args()
    dependencies = {}
    for dependency in args.android_dependency:
        coordinate, label = dependency.split("=", 1)
        if coordinate in dependencies:
            raise ValueError("Duplicate Android dependency coordinate: " + coordinate)
        dependencies[coordinate] = label
    print(json.dumps(verify(args.manifest.resolve(), args.sdk, args.expected_revision, dependencies)))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
