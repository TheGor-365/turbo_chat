#!/usr/bin/env bash
# Opt-in OFFLINE encryption of a previously verified local backup.
# Never deletes plaintext, uploads files, modifies PostgreSQL, or exports keys.
set -euo pipefail
umask 077

if [[ $# -ne 4 || "${4:-}" != "--encrypt-only" || "${1:-}" != /* || "${2:-}" != /* ]]; then
  printf 'Usage: bash bin/encrypt_local_backup.sh /absolute/source-backup-dir /absolute/private-output-parent age1RECIPIENT --encrypt-only\n' >&2
  exit 2
fi

source_dir="$(cd "$1" && pwd -P)"
output_parent="$2"
recipient="$3"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if [[ ! "$recipient" =~ ^age1[023456789acdefghjklmnpqrstuvwxyz]{50,}$ ]]; then
  printf 'Expected one native age X25519 public recipient (age1...). Never supply a secret key.\n' >&2
  exit 2
fi
if ! command -v age >/dev/null 2>&1; then
  printf 'age encryption CLI is not installed; no files were changed.\n' >&2
  exit 1
fi

# Fail closed on corrupted or incomplete inputs before creating any output.
bash "$repo_root/bin/verify_local_backup.sh" "$source_dir"

mkdir -p -- "$output_parent"
output_parent="$(cd "$output_parent" && pwd -P)"
case "$output_parent/" in
  "$repo_root/"*) printf 'Refusing encrypted output inside Git repository.\n' >&2; exit 2 ;;
  "$source_dir/"*) printf 'Refusing encrypted output inside plaintext backup.\n' >&2; exit 2 ;;
esac
if [[ "$output_parent" == "/" || "$output_parent" == "$source_dir" ]]; then
  printf 'Unsafe destination directory.\n' >&2
  exit 2
fi
case "$source_dir/" in
  "$output_parent/"*) printf 'Refusing encrypted output parent enclosing original backup.\n' >&2; exit 2 ;;
esac

for file in database.dump active_storage.tar.gz SHA256SUMS; do
  if [[ ! -f "$source_dir/$file" || -L "$source_dir/$file" ]]; then
    printf 'Missing or linked source file: %s\n' "$file" >&2
    exit 1
  fi
done

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
destination="$output_parent/$(basename "$source_dir")-encrypted-$stamp"
if [[ -e "$destination" ]]; then
  printf 'Refusing to overwrite encrypted backup destination.\n' >&2
  exit 1
fi
temporary="$(mktemp -d "$output_parent/.tc-encrypt-partial.XXXXXXXX")"
cleanup() {
  if [[ -n "${temporary:-}" && -d "$temporary" ]]; then rm -rf -- "$temporary"; fi
}
trap cleanup EXIT

for file in database.dump active_storage.tar.gz SHA256SUMS; do
  age -e -r "$recipient" -o "$temporary/$file.age" "$source_dir/$file"
done
(
  cd "$temporary"
  sha256sum database.dump.age active_storage.tar.gz.age SHA256SUMS.age > CIPHERTEXT_SHA256SUMS
  sha256sum --check --status CIPHERTEXT_SHA256SUMS
)
printf 'Encrypted files only; preserve recovery identity separately. No upload performed.\n' > "$temporary/README.txt"
mv -- "$temporary" "$destination"
temporary=""
printf 'PASS: encrypted backup created outside repository: %s\n' "$destination"
printf 'Plaintext backup retained. Ciphertext SHA256 checked. Decryption and offsite restore NOT verified.\n'
