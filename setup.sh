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
mkdir -p assets/fonts
# Bundled fonts (open source, SIL OFL). Fetched from the google/fonts repository when not already present.
fetch_font() { # <repo path> <file name>
  if [ -f "$SRC/assets/fonts/$2" ]; then cp "$SRC/assets/fonts/$2" "assets/fonts/$2"
  else curl -fsSL -o "assets/fonts/$2" "https://raw.githubusercontent.com/google/fonts/main/$1"; fi
}
fetch_font 'ofl/dmsans/DMSans%5Bopsz,wght%5D.ttf' DMSans.ttf
fetch_font 'ofl/newsreader/Newsreader%5Bopsz,wght%5D.ttf' Newsreader.ttf
fetch_font 'ofl/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf' JetBrainsMono.ttf
cp "$SRC/pubspec.yaml" pubspec.yaml

# 2. Native side.
APP=android/app/src/main
rm -rf "$APP/kotlin" "$APP/java"
mkdir -p "$APP/kotlin"
cp -r "$SRC/android_src/kotlin/." "$APP/kotlin/"
cp "$SRC/android_src/AndroidManifest.xml" "$APP/AndroidManifest.xml"

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
