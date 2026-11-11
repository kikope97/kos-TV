#!/usr/bin/env bash
# Kos TV: writes the version into pubspec.yaml before a release or test build.
#
#   scripts/kostv_set_version.sh 1.0.1        a release
#   scripts/kostv_set_version.sh 1.0.0 12     test build 12 on top of 1.0.0
#
# The release version (what build.yml's "release_version" input or a tag
# names) is the only source of truth: it becomes the version name of both
# Android builds, and the version code Android compares on an update is worked
# out from it as (MAJOR*1000000 + MINOR*1000 + PATCH) * 100, so a higher
# version always installs over a lower one (1.0.1 -> 100000100).
#
# A test build (build.yml's "test_apk") takes the latest release's version
# plus its number N (1-99): the name "1.0.0-prueba.12" and the code of 1.0.0
# plus N. It installs over that release, and the next release installs over
# it. The app's update check reads only the X.Y.Z part, so it still offers the
# next release to a test build.
#
# Releases up to 1.0.0 used MAJOR*1000000 + MINOR*1000 + PATCH (1.0.0 ->
# 1000000). Every code from this scheme is higher, so they update fine.
#
# The pubspec in the repository keeps 0.1.0, so any other build counts as older
# than every release and still gets updated.
set -euo pipefail

VERSION="${1:-}"
TEST_NUMBER="${2:-}"
if ! [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "::error::The version must look like X.Y.Z (for example 1.0.1), not '$VERSION'."
  exit 1
fi
MAJOR=$((10#${BASH_REMATCH[1]}))
MINOR=$((10#${BASH_REMATCH[2]}))
PATCH=$((10#${BASH_REMATCH[3]}))
if (( MAJOR > 20 || MINOR > 999 || PATCH > 999 )); then
  echo "::error::The first part of the version must stay under 21 and the others under 1000."
  exit 1
fi
CODE=$(( (MAJOR * 1000000 + MINOR * 1000 + PATCH) * 100 ))
if (( CODE < 1 )); then
  echo "::error::0.0.0 is not a release version."
  exit 1
fi

NAME="$VERSION"
if [ -n "$TEST_NUMBER" ]; then
  if ! [[ "$TEST_NUMBER" =~ ^[0-9]+$ ]] || (( 10#$TEST_NUMBER < 1 || 10#$TEST_NUMBER > 99 )); then
    echo "::error::The test build number must be between 1 and 99, not '$TEST_NUMBER'."
    exit 1
  fi
  NAME="${VERSION}-prueba.$((10#$TEST_NUMBER))"
  CODE=$(( CODE + 10#$TEST_NUMBER ))
fi

PUBSPEC="$(cd "$(dirname "$0")/.." && pwd)/pubspec.yaml"
sed -i -E \
  -e "s/^version:.*/version: ${NAME}+${CODE}/" \
  -e "s/^([[:space:]]+)android_tv_version:.*/\1android_tv_version: ${NAME}/" \
  -e "s/^([[:space:]]+)android_tv_build_number:.*/\1android_tv_build_number: ${CODE}/" \
  "$PUBSPEC"

echo "Kos TV ${NAME} (version code ${CODE})"
grep -E '^version:|android_tv_(version|build_number):' "$PUBSPEC"
