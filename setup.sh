#!/usr/bin/env bash
# Builds the V2-TUN Flutter project around the io.surprise.vpn tunnel library.
# Needs: flutter, git, and (to build the library) go, gomobile, Android SDK + NDK.
set -euo pipefail

REPO="${V2TUN_REPO:-https://github.com/CipherTun/V2-TUN.git}"
BRANCH="${V2TUN_BRANCH:-fix/review-20261104}"
SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$SRC/../v2tun_flutter}"

# 1. Fresh Flutter project: current templates, applicationId and namespace io.surprise.vpn.
flutter create --org io.surprise --project-name vpn --platforms android "$OUT"
cd "$OUT"
rm -rf lib test
cp -r "$SRC/lib" lib
cp -r "$SRC/assets" assets
cp "$SRC/pubspec.yaml" pubspec.yaml

# 2. Native side.
APP=android/app/src/main
rm -rf "$APP/kotlin" "$APP/java"
mkdir -p "$APP/kotlin"
cp -r "$SRC/android_src/kotlin/." "$APP/kotlin/"
cp "$SRC/android_src/AndroidManifest.xml" "$APP/AndroidManifest.xml"
# Launcher icon: replaces the default Flutter mipmaps (mdpi to xxxhdpi).
if [ -d "$SRC/android_src/res" ]; then
  mkdir -p "$APP/res"
  cp -r "$SRC/android_src/res/." "$APP/res/"
fi

# 3. The tunnel library as an AAR (gomobile gives it the Java package io.surprise.mobile).
mkdir -p android/app/libs
if [ -f "$SRC/v2tun.aar" ]; then
  cp "$SRC/v2tun.aar" android/app/libs/v2tun.aar
else
  TMP="$(mktemp -d)"
  git clone --depth 1 --branch "$BRANCH" "$REPO" "$TMP/V2-TUN"
  ( cd "$TMP/V2-TUN" && go mod tidy \
    && go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init \
    && gomobile bind -target=android -javapkg=io.surprise -o "$OLDPWD/android/app/libs/v2tun.aar" io.surprise.vpn/mobile )
fi

# 4. Link the AAR (works for build.gradle.kts and build.gradle).
if [ -f android/app/build.gradle.kts ]; then
  printf '\ndependencies {\n    implementation(files("libs/v2tun.aar"))\n}\n' >> android/app/build.gradle.kts
else
  printf '\ndependencies {\n    implementation files("libs/v2tun.aar")\n}\n' >> android/app/build.gradle
fi

flutter pub get
flutter pub upgrade --major-versions
echo "Done. cd $OUT && flutter run"
