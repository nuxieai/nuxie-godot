"""Independent malformed-product and dependency-edge import oracles."""

import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

from native_artifacts import verify


REVISION = "1" * 40


class NativeArtifactsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write(self, path, data=b"artifact"):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(data)
        return path

    def manifest(self, sdk, **values):
        receipt = {"schemaVersion": 1, "sdk": sdk, "sourceRevision": REVISION,
                   "sourceDirty": False, **values}
        receipt["artifacts"] = [
            {"kind": "file", "path": path.relative_to(self.root).as_posix(),
             "size": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            for path in sorted(self.root.rglob("*")) if path.is_file() and not path.is_symlink()]
        path = self.root / "sdk-artifacts.json"
        path.write_text(json.dumps(receipt))
        return path

    def android(self):
        prefix = "ai/nuxie/nuxie-android/0.2.0-" + REVISION + "/nuxie-android-0.2.0-" + REVISION
        self.write(prefix + ".aar")
        self.write(prefix + ".module", b"{}")
        self.write(prefix + ".pom", b'''<project xmlns="http://maven.apache.org/POM/4.0.0">
          <dependencies><dependency><groupId>example</groupId><artifactId>api</artifactId>
            <version>1.2.3</version><scope>compile</scope></dependency>
            <dependency><groupId>example</groupId><artifactId>runtime</artifactId>
            <version>4.5.6</version><scope>runtime</scope></dependency></dependencies></project>''')
        return self.manifest("android", runtime={"mode": "published", "checksum": "2" * 64},
                             maven={"groupId": "ai.nuxie", "artifactId": "nuxie-android", "version": "0.2.0-" + REVISION})

    def ios(self):
        runtime = "runtime/NuxieRuntime.xcframework"
        slice_name = "ios-arm64_x86_64-simulator"
        self.write(runtime + "/Info.plist", plistlib.dumps({"AvailableLibraries": [{
            "LibraryIdentifier": slice_name, "LibraryPath": "libnux_capi.a", "HeadersPath": "Headers",
            "SupportedPlatform": "ios", "SupportedPlatformVariant": "simulator", "SupportedArchitectures": ["arm64", "x86_64"]}]}))
        self.write(runtime + "/" + slice_name + "/libnux_capi.a")
        self.write(runtime + "/" + slice_name + "/Headers/module.modulemap")
        self.write(runtime + "/" + slice_name + "/Headers/nux_capi.h")
        framework = "ios-simulator/Release/Nuxie.framework"
        self.write(framework + "/Nuxie")
        self.write(framework + "/Headers/Nuxie.h")
        self.write(framework + "/Modules/module.modulemap")
        bundle = "ios-simulator/Release/Nuxie_Nuxie.bundle"
        self.write(bundle + "/PrivacyInfo.xcprivacy")
        product = {"platform": "ios-simulator", "configuration": "Release", "module": "Nuxie",
                   "framework": framework, "architectures": ["arm64", "x86_64"], "staticLibraries": [],
                   "swiftModules": [], "swiftHeaders": [], "swiftDependencies": ["NuxieRuntime"],
                   "resourceBundles": [bundle], "nativeDependencies": [{"module": "NuxieRuntimeC",
                       "library": runtime + "/" + slice_name + "/libnux_capi.a",
                       "headers": runtime + "/" + slice_name + "/Headers",
                       "moduleMap": runtime + "/" + slice_name + "/Headers/module.modulemap",
                       "sdkFrameworks": ["Metal", "Foundation"]}]}
        for architecture in product["architectures"]:
            for module in ("Nuxie", "NuxieRuntime"):
                prefix = "ios-simulator/Release/static/" + architecture + "/"
                for key, suffix, stem in (("staticLibraries", ".a", "lib" + module),
                                          ("swiftModules", ".swiftmodule", module), ("swiftHeaders", ".h", module)):
                    path = self.write(prefix + stem + suffix)
                    product[key].append({"module": module, "architecture": architecture, "path": path})
        return self.manifest("ios", products=[product], runtime={"path": runtime, "checksum": "3" * 64, "sourceCommit": "4" * 40}, symlinks=[])

    def test_android_carries_api_and_runtime_pom_edges(self):
        path = self.android()
        result = verify(path, "android", REVISION, {"example:api:1.2.3": "@maven//:api", "example:runtime:4.5.6": "@maven//:runtime"})
        self.assertIn("aar_import(", result["build"])
        self.assertIn("deps = ['@maven//:api', '@maven//:runtime']", result["build"])

    def test_android_missing_pom_edge_fails(self):
        with self.assertRaisesRegex(ValueError, "example:api:1.2.3"):
            verify(self.android(), "android", REVISION)

    def test_ios_selects_each_simulator_architecture_and_bundle(self):
        result = verify(self.ios(), "ios", REVISION)
        self.assertIn("apple_static_xcframework_import(", result["build"])
        self.assertIn("apple_dynamic_framework_import(", result["build"])
        self.assertIn("module_name = 'NuxieRuntime'", result["build"])
        self.assertIn("module_name = 'Nuxie'", result["build"])
        self.assertIn("@apple_support//constraints:simulator", result["build"])
        self.assertIn("@platforms//cpu:x86_64", result["build"])
        self.assertIn("apple_bundle_import(", result["build"])

    def test_revision_and_dirty_source_fail(self):
        path = self.ios()
        with self.assertRaisesRegex(ValueError, "NATIVE-PINS"):
            verify(path, "ios", "5" * 40)
        receipt = json.loads(path.read_text())
        receipt["sourceDirty"] = True
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, "committed source"):
            verify(path, "ios", REVISION)

    def test_mutated_byte_with_same_size_fails(self):
        path = self.ios()
        (self.root / "ios-simulator/Release/Nuxie.framework/Nuxie").write_bytes(b"mutated!")
        with self.assertRaisesRegex(ValueError, "SHA-256 changed"):
            verify(path, "ios", REVISION)

    def test_path_escape_fails(self):
        path = self.ios()
        receipt = json.loads(path.read_text())
        receipt["artifacts"][0]["path"] = "../outside.a"
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, "Unsafe artifact path"):
            verify(path, "ios", REVISION)

    def test_uninventoried_swift_module_fails(self):
        path = self.ios()
        receipt = json.loads(path.read_text())
        receipt["products"][0]["swiftModules"][0]["path"] = "unverified.swiftmodule"
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, "uninventoried"):
            verify(path, "ios", REVISION)

    def test_platform_runtime_mismatch_fails(self):
        path = self.ios()
        receipt = json.loads(path.read_text())
        receipt["products"][0]["platform"] = "ios-device"
        receipt["products"][0]["architectures"] = ["arm64"]
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, "matching platform slice"):
            verify(path, "ios", REVISION)

    def test_safe_framework_symlink_is_retained(self):
        path = self.ios()
        link = self.root / "ios-simulator/Release/Nuxie.framework/Modules/current"
        link.symlink_to("module.modulemap")
        receipt = json.loads(path.read_text())
        receipt["symlinks"] = [{"path": link.relative_to(self.root).as_posix(), "target": "module.modulemap"}]
        path.write_text(json.dumps(receipt))
        self.assertEqual(len(verify(path, "ios", REVISION)["symlinks"]), 1)
        link.unlink()
        link.symlink_to("/etc/passwd")
        receipt["symlinks"][0]["target"] = "/etc/passwd"
        path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, "unsafe artifact symlink"):
            verify(path, "ios", REVISION)


if __name__ == "__main__":
    unittest.main()
