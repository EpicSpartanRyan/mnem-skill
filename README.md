# mnem skill

An Agent Skill that wraps [mnem](https://github.com/Uranid/mnem) — Git for AI
Agent Knowledge. A vanilla wrapper: it documents mnem exactly as it ships,
adds no features, and changes no behavior.

mnem is a persistent, versioned knowledge layer for AI agents: a
content-addressed knowledge graph (DAG-CBOR + BLAKE3 CIDs) with git-style
commits, branches, diff and 3-way merge, hybrid retrieval (HNSW vector +
BM25/SPLADE sparse + multi-hop graph traversal fused via RRF), a bundled
in-process ONNX MiniLM-L6-v2 embedder (no API keys, no Ollama, no network),
and one ~40 MB binary that runs as a CLI, an HTTP server, an MCP server, or
a Python library. No daemon, no external database, fully offline.

## Install

```bash
npx skills add EpicSpartanRyan/mnem-skill
```

The skill itself is a `SKILL.md` plus references; the
mnem binary is installed separately (see below).

## Install mnem

The skill needs the `mnem` binary on PATH. The script
`skills/mnem/scripts/setup-mnem.sh` does it for you (downloads the newest
release binary that ships a Linux asset, verifies its sha256, smoke-tests
it), or install by hand:

```bash
# Recommended: build from source (Rust 1.95+, g++ on Linux), ~5-15 min
cargo install --locked mnem-cli --features bundled-embedder

# Or a prebuilt binary — v0.1.3 is the newest release with a Linux tarball:
# https://github.com/Uranid/mnem/releases/download/v0.1.3/mnem-x86_64-unknown-linux-gnu.tar.gz
# (extract; keep bin/ and lib/ together — the binary finds its bundled
# libonnxruntime via rpath)

mnem --version   # confirm install
mnem doctor      # checks embedder + store + config
```

> **Known install caveat (verified 2026-11-27):** the GitHub release v0.1.6
> ships only a Windows binary (`mnem.exe`); there is no v0.1.7 release tag
> and no Linux tarball under v0.1.6/v0.1.7, so `pip install mnem-cli`
> (0.1.7) 404s on Linux and `cargo binstall mnem-cli` resolves to the same
> missing release archives. Prefer `cargo install` for 0.1.7, or the v0.1.3
> release binary. Also note: the "bundled" embedder downloads the MiniLM
> model (~92 MB) from HuggingFace on first use; if that download fails,
> pre-seed the cache with curl (see SKILL.md) and run `mnem reindex`.

## Quick start

```bash
mkdir my-graph && cd my-graph
mnem init          # creates .mnem/ — the local graph for this project
mnem ingest notes.md        # file -> Doc + Chunk + Entity nodes
mnem ingest --text "mnem is a versioned knowledge graph for AI agents"  # (0.1.7+)
mnem retrieve "what does mnem do"
```

```bash
# Wire an agent host (Claude Code, Cursor, Continue, Zed, Gemini CLI; Hermes is 0.1.7+)
mnem integrate
```

## What the skill contains

```
skills/mnem/
  SKILL.md               # the skill: what mnem is, when to use it, core workflow
  references/
    commands.md          # full verified CLI reference
    retrieval.md         # hybrid retrieval, fusion, token-budget transparency
    versioning.md        # commits, branches, 3-way merge, CAR export/import
    integrations.md      # MCP server, HTTP API, mnem integrate, Python API
  scripts/
    setup-mnem.sh        # install the mnem binary + smoke test
```

## When NOT to use mnem

- **Do not deploy the store on Vercel or any serverless platform.** The
  store is an embedded redb database on local disk; serverless has ephemeral
  disk and no long-lived process, so writes would be lost. mnem needs a live
  process with a disk (a VPS, Fly.io, Railway with a volume, or a Docker
  container).
- Not a transactional OLTP database, not sub-50 ms cloud-scale retrieval,
  not concurrent multi-writer (single-writer lock; concurrent writers need
  an external queue or separate repos merged with `mnem merge`).

## Upstream

- mnem repo: https://github.com/Uranid/mnem
- mnem docs: https://docs.mnem.ai (book source in the repo under `docs/`)
- mnem license: **Apache-2.0** (this wrapper skill is MIT; see `LICENSE`)

## Skill version

Verified against the **mnem 0.1.3 release binary** (smoke-tested end to end
on Linux x86_64, 2026-11-27) and the **0.1.7 tag source**. Commands marked
(0.1.7+) exist in the 0.1.7 source but not in the 0.1.3 binary. mnem is
pre-1.0: CLI commands, MCP tool names, and Python bindings are stable for
v0.1.x; check the upstream CHANGELOG before upgrading.
