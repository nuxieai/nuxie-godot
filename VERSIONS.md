# Version contract

The breaking wrapper version is **0.4.0**. It replaces the prior public API without aliases. Source and binary inputs are pinned in [NATIVE-PINS.json](NATIVE-PINS.json): Godot 4.7.2, iOS e2cc75fb2e996d9e8a844942e53aa53b3056248b and Android 1cfd174cc6a713794e93c1654e37bec853f7e38f.

Gradle and Swift Package Manager read the canonical manifest. The packer includes that same manifest with SHA-256 checksums for the staged addon. Android's revision-qualified Maven coordinate is a package-local build of the pinned source, not a claim that this version exists on Maven Central.

See [qualification](docs/testing-and-validation.md) for measured engine, platform and runtime coverage. Git history preserves the retired API; this repository documents only the replacement.
