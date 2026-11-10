#!/usr/bin/env bash
# Kos TV: writes a release version into pubspec.yaml before a release build.
#
#   scripts/kostv_set_version.sh 1.0.1
#
# The release version (what build.yml's "release_version" input or a tag
# names) is the only source of truth: it becomes the version name of both
# Android builds, and the version code Android compares on an update is worked
# out from it as MAJOR*1000000 + MINOR*1000 + PATCH, so a higher version always
# installs over a lower one (1.0.1 -> 1000001, 1.2.0 -> 1002000).
#
# The pubspec in the repository keeps 0.1.0 (code 1000), so any build that isn't
# a release counts as older than every release and still gets updated.
set -euo pipefail

VERSION="${1:-}"
if ! [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "::error::The version must look like X.Y.Z (for example 1.0.1), not '$VERSION'."
  exit 1
fi
MAJOR=$((10#${BASH_REMATCH[1]}))
MINOR=$((10#${BASH_REMATCH[2]}))
PATCH=$((10#${BASH_REMATCH[3]}))
if (( MAJOR > 2000 || MINOR > 999 || PATCH > 999 )); then
  echo "::error::Each part of the version must stay under 1000 (and the first under 2001)."
  exit 1
fi
CODE=$(( MAJOR * 1000000 + MINOR * 1000 + PATCH ))
if (( CODE < 1 )); then
  echo "::error::0.0.0 is not a release version."
  exit 1
fi

PUBSPEC="$(cd "$(dirname "$0")/.." && pwd)/pubspec.yaml"
sed -i -E \
  -e "s/^version:.*/version: ${VERSION}+${CODE}/" \
  -e "s/^([[:space:]]+)android_tv_version:.*/\1android_tv_version: ${VERSION}/" \
  -e "s/^([[:space:]]+)android_tv_build_number:.*/\1android_tv_build_number: ${CODE}/" \
  "$PUBSPEC"

echo "Kos TV ${VERSION} (version code ${CODE})"
grep -E '^version:|android_tv_(version|build_number):' "$PUBSPEC"
