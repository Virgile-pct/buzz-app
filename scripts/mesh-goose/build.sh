#!/bin/sh
# Builds lean upstream goose's ACP-only binary (`goose-acp`, goose #11961) for
# the Mesh agent type and stages it for `--config src-tauri/tauri.mesh.conf.json`,
# which bundles it into the app as `buzz-mesh-goose` (Contents/MacOS, found
# before PATH by host processes).
#
# Usage: scripts/mesh-goose/build.sh [/path/to/goose/checkout]
# Pin: aaif-goose/goose at $REVISION, `lean` profile, the feature set Buzz used
# for its earlier bundled goose-acp.
set -eu

REPOSITORY=https://github.com/aaif-goose/goose.git
REVISION=69de89c50cc01d4e0187d6645bf3618729873f74
FEATURES=native-tls,system-keyring,online-model-meta,openssl/vendored

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/buzz-mesh-goose.XXXXXX")
cleanup() {
  if [ -n "${source:-}" ]; then
    git -C "$source" worktree remove --force "$work/src" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT
if [ "$#" -ge 1 ]; then
  source=$(git -C "$1" rev-parse --show-toplevel)
  git -C "$source" cat-file -e "$REVISION^{commit}" 2>/dev/null ||
    git -C "$source" fetch "$REPOSITORY" "$REVISION"
  git -C "$source" worktree add --detach "$work/src" "$REVISION" >/dev/null
else
  git init -q "$work/src"
  git -C "$work/src" fetch -q --depth 1 --filter=blob:none "$REPOSITORY" "$REVISION"
  git -C "$work/src" checkout -q --detach FETCH_HEAD
fi
host=$(rustc -vV | sed -n 's/^host: //p')
exe=
case "$host" in
  *-windows-msvc)
    exe=.exe
    # Under Git Bash, `perl` is MSYS's, which cannot configure the vendored
    # OpenSSL: openssl-src takes a native Perl from OPENSSL_SRC_PERL or PERL instead.
    if [ -z "${OPENSSL_SRC_PERL:-}${PERL:-}" ] && perl -e 'exit($^O eq "msys" ? 0 : 1)' 2>/dev/null; then
      echo "The vendored OpenSSL needs a native Windows Perl (for example Strawberry Perl): set OPENSSL_SRC_PERL or PERL to its perl.exe." >&2
      exit 1
    fi
    # In a Visual Studio developer environment rustc trusts PATH, where Git
    # Bash puts coreutils' link.exe first: name MSVC's linker explicitly.
    if [ "$host" = x86_64-pc-windows-msvc ] && [ -n "${VCToolsInstallDir:-}" ] &&
      [ -z "${CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER:-}" ]; then
      export CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER="${VCToolsInstallDir}bin/Hostx64/x64/link.exe"
    fi
    ;;
esac
CARGO_TARGET_DIR="$work/target" cargo build --locked \
  --manifest-path "$work/src/Cargo.toml" -p goose --bin goose-acp \
  --profile lean --no-default-features --features "$FEATURES"
mkdir -p "$root/src-tauri/binaries"
out="$root/src-tauri/binaries/buzz-mesh-goose-$host$exe"
cp "$work/target/lean/goose-acp$exe" "$out"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$out"
else
  sha256sum "$out"
fi
