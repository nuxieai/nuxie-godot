#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

godot_version=$(python3 -c 'import json; print(json.load(open("NATIVE-PINS.json"))["godot"])')
export GODOT_BIN="$PWD/.native/tools/Godot.app/Contents/MacOS/Godot"
installed_version=""
if [[ -x "$GODOT_BIN" ]]; then
  installed_version=$("$GODOT_BIN" --version)
fi
if [[ "$installed_version" != "$godot_version.stable."* ]]; then
  mkdir -p .native/tools
  touch .native/.gdignore
  archive="Godot_v${godot_version}-stable_macos.universal.zip"
  release_url="https://github.com/godotengine/godot-builds/releases/download/${godot_version}-stable"
  download_dir=$(mktemp -d "$PWD/.native/tools/download.XXXXXX")
  trap 'rm -rf "$download_dir"' EXIT
  curl --fail --location --retry 3 "$release_url/$archive" -o "$download_dir/$archive"
  curl --fail --location --retry 3 "$release_url/SHA512-SUMS.txt" -o "$download_dir/SHA512-SUMS.txt"
  (
    cd "$download_dir"
    awk -v name="$archive" '$2 == name { print }' SHA512-SUMS.txt > selected-checksum.txt
    test -s selected-checksum.txt
    shasum -a 512 --check selected-checksum.txt
    ditto -x -k "$archive" extracted
    test -x extracted/Godot.app/Contents/MacOS/Godot
  )
  rm -rf .native/tools/Godot.app
  mv "$download_dir/extracted/Godot.app" .native/tools/Godot.app
fi

python3 scripts/prepare-native.py
python3 scripts/pack.py
python3 scripts/check.py
