#!/usr/bin/env bash
# Fixed, upstream SHA-256 verified Dart Sass compiler.
# No npm sass package, @parcel/watcher or picomatch required.
set -euo pipefail

version="1.107.1"
if [[ -n "${DART_SASS_BIN:-}" ]]; then
  binary="$DART_SASS_BIN"
else
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)
      platform="linux-x64"
      expected_sha="6cefe78692d03ca53843394bb98de4dccf9a3d8ee5ece40be7316be852624003"
      ;;
    Linux-aarch64|Linux-arm64)
      platform="linux-arm64"
      expected_sha="c919b91f6162d01ea442e1df0aaed3557c4322a60d48fdf10972ce4d3483a49f"
      ;;
    *)
      echo "Unsupported automatic Sass platform. Set DART_SASS_BIN to a verified Sass $version executable." >&2
      exit 1
      ;;
  esac

  cache_root="${DART_SASS_CACHE_ROOT:-$PWD/tmp/toolchain}"
  install_dir="$cache_root/dart-sass-$version-$platform"
  binary="$install_dir/sass"

  if [[ ! -x "$binary" ]]; then
    for utility in curl tar sha256sum flock mktemp; do
      command -v "$utility" >/dev/null || { echo "Required command missing: $utility" >&2; exit 1; }
    done
    mkdir -p "$cache_root"
    (
      flock -x 9
      if [[ ! -x "$binary" ]]; then
        work="$(mktemp -d "$cache_root/.dart-sass-XXXXXXXX")"
        trap 'rm -rf "$work"' EXIT
        url="https://github.com/sass/dart-sass/releases/download/$version/dart-sass-$version-$platform.tar.gz"
        curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error --retry 3 "$url" -o "$work/dart-sass.tar.gz"
        printf '%s  %s\n' "$expected_sha" "$work/dart-sass.tar.gz" | sha256sum --check --status || {
          echo "Dart Sass official artifact SHA-256 mismatch; refusing to execute." >&2
          exit 1
        }
        tar -xzf "$work/dart-sass.tar.gz" -C "$work"
        test -x "$work/dart-sass/sass"
        mv "$work/dart-sass" "$install_dir"
      fi
    ) 9>"$cache_root/.dart-sass-install.lock"
  fi
fi

actual_version="$("$binary" --version)"
if [[ "$actual_version" != "$version" ]]; then
  echo "Wrong Sass executable version: expected $version, got $actual_version" >&2
  exit 1
fi
exec "$binary" "$@"
