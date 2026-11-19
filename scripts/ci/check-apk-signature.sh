#!/usr/bin/env bash
# Kos TV: checks that each APK given is signed with the release key before
# it is published (build.yml). An APK signed with the Android debug key
# (CN=Android Debug) fails, since it won't install over the app the family
# has. With EXPECTED_SHA256 (the KOSTV_SIGNING_SHA256 repository variable:
# the signing certificate's SHA-256, with or without colons), the
# certificate must be exactly that one.
#
#   EXPECTED_SHA256=... scripts/ci/check-apk-signature.sh KosTV_*.apk
#
# apksigner comes from APKSIGNER, or else the newest Android SDK build-tools
# (ANDROID_HOME or ANDROID_SDK_ROOT).
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "::error::No APK to check."
  exit 1
fi

apksigner="${APKSIGNER:-}"
if [ -z "$apksigner" ]; then
  sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  apksigner=$(find "$sdk/build-tools" -mindepth 2 -maxdepth 2 -name apksigner 2>/dev/null | sort -V | tail -n 1 || true)
fi
if [ -z "$apksigner" ]; then
  echo "::error::apksigner not found (set APKSIGNER, or ANDROID_HOME with build-tools)."
  exit 1
fi

expected=$(printf '%s' "${EXPECTED_SHA256:-}" | tr -d ': \t\r\n' | tr '[:upper:]' '[:lower:]')

for apk in "$@"; do
  if [ ! -f "$apk" ]; then
    echo "::error::$apk not found."
    exit 1
  fi
  if ! certs=$("$apksigner" verify --print-certs "$apk"); then
    echo "::error::$apk: apksigner could not verify its signature."
    exit 1
  fi
  if grep -q 'CN=Android Debug' <<<"$certs"; then
    echo "::error::$apk is signed with the Android debug key, not the release key."
    exit 1
  fi
  # apksigner names the signer "Signer #1", or by SDK range
  # ("Signer (minSdkVersion=..., maxSdkVersion=...)") with key rotation or
  # newer build-tools; any of them counts.
  digests=$(sed -n 's/^.*[Ss]igner.*certificate SHA-256 digest: *//p' <<<"$certs" \
    | tr -d ': ' | tr '[:upper:]' '[:lower:]' | sort -u)
  if [ -z "$digests" ]; then
    echo "$certs"
    echo "::error::$apk: no signing certificate found."
    exit 1
  fi
  if [ -n "$expected" ] && ! grep -qx "$expected" <<<"$digests"; then
    echo "::error::$apk is not signed with the expected key (KOSTV_SIGNING_SHA256). Its certificate: $digests"
    exit 1
  fi
  echo "$apk: $digests"
done

if [ -z "$expected" ]; then
  echo "::notice::KOSTV_SIGNING_SHA256 is not set: only checked that the APKs are not debug-signed."
fi
