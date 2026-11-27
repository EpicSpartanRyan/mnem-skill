#!/usr/bin/env bash
# setup-mnem.sh — install the mnem binary if missing, then smoke-test it.
#
# Vanilla mnem only: this installs the upstream binary, nothing else.
#
# Install order:
#   1. Newest GitHub release that ships a Linux x86_64 tarball
#      (as of 2026-11-27 that is v0.1.3 — v0.1.6 ships only a Windows
#      binary and there is no v0.1.7 release tag; the script picks the
#      newest tag with the asset dynamically, falling back to v0.1.3).
#      sha256 is verified against the release's .sha256 file.
#   2. If no Linux release asset can be found, `cargo install --locked
#      mnem-cli --features bundled-embedder` (Rust 1.95+, ~5-15 min).
#
# The bundled embedder downloads the MiniLM-L6-v2 ONNX model (~92 MB)
# from HuggingFace on first use; if that download fails (restricted
# network/proxy), the script pre-seeds the cache with curl and re-runs
# `mnem reindex`. Without the model, mnem falls back to a mock embedder
# and retrieval returns nothing useful.
#
# Usage: bash setup-mnem.sh [--force-reinstall]
set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force-reinstall" ]]; then FORCE=1; fi

INSTALL_DIR="$HOME/.local/bin"
MNEM_BIN=""
if command -v mnem >/dev/null 2>&1; then
  MNEM_BIN="$(command -v mnem)"
elif [[ -x "$INSTALL_DIR/mnem" ]]; then
  MNEM_BIN="$INSTALL_DIR/mnem"
fi

# Find the newest release tag that ships the Linux x86_64 tarball.
# Prints "<tag> <tarball-url> <sha256-url>" or nothing.
find_linux_release() {
  local api tag asset_url sha_url
  api="$(curl -fsSL --max-time 30 "https://api.github.com/repos/Uranid/mnem/releases?per_page=20" 2>/dev/null || true)"
  if [[ -n "$api" ]]; then
    tag="$(printf '%s' "$api" | python3 -c "
import json, sys
try:
    rels = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in rels:
    for a in r.get('assets', []):
        if a.get('name') == 'mnem-x86_64-unknown-linux-gnu.tar.gz':
            print(r['tag_name'])
            sys.exit(0)
" 2>/dev/null || true)"
    if [[ -n "$tag" ]]; then
      echo "$tag https://github.com/Uranid/mnem/releases/download/$tag/mnem-x86_64-unknown-linux-gnu.tar.gz https://github.com/Uranid/mnem/releases/download/$tag/mnem-x86_64-unknown-linux-gnu.tar.gz.sha256"
      return 0
    fi
  fi
  return 1
}

install_via_release() {
  local found tag tar_url sha_url tmp
  if found="$(find_linux_release)"; then
    read -r tag tar_url sha_url <<<"$found"
  else
    echo "GitHub API unavailable or no Linux asset found; falling back to v0.1.3 (newest release known to ship a Linux tarball)."
    tag="v0.1.3"
    tar_url="https://github.com/Uranid/mnem/releases/download/v0.1.3/mnem-x86_64-unknown-linux-gnu.tar.gz"
    sha_url="https://github.com/Uranid/mnem/releases/download/v0.1.3/mnem-x86_64-unknown-linux-gnu.tar.gz.sha256"
  fi
  echo "Downloading mnem $tag (Linux x86_64 release binary)..."
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL -o "$tmp/mnem-x86_64-unknown-linux-gnu.tar.gz" --max-time 300 "$tar_url"
  curl -fsSL -o "$tmp/mnem-x86_64-unknown-linux-gnu.tar.gz.sha256" --max-time 30 "$sha_url"
  (cd "$tmp" && sha256sum -c mnem-x86_64-unknown-linux-gnu.tar.gz.sha256) || {
    echo "error: sha256 mismatch for $tar_url" >&2; return 1
  }
  mkdir -p "$INSTALL_DIR"
  tar xzf "$tmp/mnem-x86_64-unknown-linux-gnu.tar.gz" --no-same-owner -C "$tmp"
  # Keep bin/ and lib/ together: the binary finds its bundled
  # libonnxruntime via rpath; no LD_LIBRARY_PATH needed.
  cp "$tmp/mnem-x86_64-unknown-linux-gnu/bin/mnem" "$INSTALL_DIR/mnem"
  mkdir -p "$INSTALL_DIR/mnem-lib"
  cp "$tmp/mnem-x86_64-unknown-linux-gnu/lib/"*.so.* "$INSTALL_DIR/mnem-lib/" 2>/dev/null || true
  chmod +x "$INSTALL_DIR/mnem"
  export PATH="$INSTALL_DIR:$PATH"
  MNEM_BIN="$INSTALL_DIR/mnem"
  echo "Installed mnem $tag to $MNEM_BIN"
}

install_via_cargo() {
  if [[ -x "$HOME/.cargo/bin/cargo" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
  if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo not found. Install Rust 1.95+ first: https://rustup.rs/" >&2
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.95" >&2
    return 1
  fi
  echo "Installing mnem via cargo (builds from source, ~5-15 min first run)..."
  cargo install --locked mnem-cli --features bundled-embedder
  export PATH="$HOME/.cargo/bin:$PATH"
  MNEM_BIN="$HOME/.cargo/bin/mnem"
}

if [[ $FORCE -eq 1 || -z "$MNEM_BIN" ]]; then
  if [[ $FORCE -eq 1 && -n "$MNEM_BIN" ]]; then
    echo "Force reinstall requested; existing binary at $MNEM_BIN will be replaced."
  fi
  if ! install_via_release; then
    echo "Release-binary install failed; trying cargo install..."
    install_via_cargo || exit 1
  fi
fi

if [[ -z "$MNEM_BIN" || ! -x "$MNEM_BIN" ]]; then
  echo "error: mnem binary not found after install attempts." >&2
  exit 1
fi

echo "mnem binary: $MNEM_BIN"
"$MNEM_BIN" --version

# ---- smoke test in a throwaway directory -----------------------------------
TMPDIR_SMOKE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SMOKE"' EXIT
cd "$TMPDIR_SMOKE"

echo "--- smoke test: init ---"
"$MNEM_BIN" init

echo "--- smoke test: ingest ---"
printf '# Notes\n\nmnem is a versioned knowledge graph for AI agents.\n' > notes.md
# Note: ingest exits non-zero when its post-ingest reindex fails because
# the embedder model could not be downloaded. That is handled below
# (seed_model + reindex); the retrieve assertion is the real gate.
"$MNEM_BIN" ingest notes.md || echo "note: ingest exited non-zero (embedder download failure is handled below)"

# If the embedder model download failed, mnem falls back to a mock
# embedder and retrieval returns 0 items. Pre-seed the HF cache with
# curl (same layout mnem uses) and backfill embeddings.
seed_model() {
  local base="$HOME/.cache/huggingface/hub/models--Xenova--all-MiniLM-L6-v2/resolve/main"
  mkdir -p "$base/onnx"
  curl -fsSL -o "$base/onnx/model.onnx" --max-time 300 \
    "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx" || return 1
  curl -fsSL -o "$base/tokenizer.json" --max-time 60 \
    "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/tokenizer.json" || return 1
  "$MNEM_BIN" reindex
}

echo "--- smoke test: retrieve ---"
OUT="$("$MNEM_BIN" retrieve "what does mnem do" 2>&1)"
echo "$OUT"
if echo "$OUT" | grep -qi "mock embedder"; then
  echo "Embedder model download failed; pre-seeding the model cache via curl..."
  if seed_model; then
    OUT="$("$MNEM_BIN" retrieve "what does mnem do" 2>&1)"
    echo "$OUT"
  else
    echo "error: could not fetch the embedder model; retrieval cannot work without it." >&2
    exit 1
  fi
fi
if ! echo "$OUT" | grep -qi "mnem is a versioned knowledge graph"; then
  echo "error: smoke test retrieve did not return the ingested fact." >&2
  exit 1
fi
if ! echo "$OUT" | grep -qE "# [0-9]+ item\(s\), [0-9]+/unlimited tokens, [0-9]+ dropped, [0-9]+ candidates"; then
  echo "error: smoke test retrieve output is missing the token-accounting header." >&2
  exit 1
fi

echo "--- smoke test: status + log ---"
"$MNEM_BIN" status
"$MNEM_BIN" log -n 5

echo "OK: mnem $($MNEM_BIN --version) installed and smoke-tested."
echo "Next: cd to your project and run 'mnem init', or 'mnem integrate' to wire an agent host."
