#!/usr/bin/env bash
# Stamp CFBundleShortVersionString / CFBundleVersion on the built app bundle.
#
# Resolution order:
#   1. $BELLITH_MARKETING_VERSION / $BELLITH_BUILD_NUMBER (explicit, used by CI)
#   2. git tag (stripped of a leading "v") / git rev-list --count
#   3. "0.0.0-dev" / "1" fallback
set -euo pipefail

repo_root="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

version="${BELLITH_MARKETING_VERSION:-}"
build="${BELLITH_BUILD_NUMBER:-}"

if [ -z "$version" ]; then
  if tag=$(git -C "$repo_root" describe --tags --abbrev=0 2>/dev/null); then
    version="${tag#v}"
  fi
fi
: "${version:=0.0.0-dev}"

if [ -z "$build" ]; then
  if count=$(git -C "$repo_root" rev-list --count HEAD 2>/dev/null); then
    build="$count"
  fi
fi
: "${build:=1}"

target_build_dir="${TARGET_BUILD_DIR:-}"
infoplist_path="${INFOPLIST_PATH:-}"
if [ -z "$target_build_dir" ] || [ -z "$infoplist_path" ]; then
  echo "stamp-version: TARGET_BUILD_DIR or INFOPLIST_PATH unset; skipping" >&2
  exit 0
fi

plist="$target_build_dir/$infoplist_path"
if [ ! -f "$plist" ]; then
  echo "stamp-version: $plist not found; skipping" >&2
  exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"
echo "stamp-version: $version ($build) -> $plist"
