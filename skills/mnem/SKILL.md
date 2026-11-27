---
name: mnem
description: Use mnem (Git for AI agent knowledge) as a versioned, content-addressed knowledge graph — init, ingest, hybrid retrieve, commit/branch/merge, and share via MCP or HTTP — whenever an agent needs memory that survives sessions, is inspectable, and can be diffed and merged like code.
license: MIT
---

# mnem — Git for AI Agent Knowledge

mnem is a persistent, versioned knowledge layer for AI agents. It stores
facts, decisions, and conventions as nodes and typed edges in a queryable
knowledge graph inside your project's `.mnem/` directory. Every write is a
versioned commit; branch, diff, merge, or roll back any write the same way
you would source code.

Upstream: https://github.com/Uranid/mnem — license Apache-2.0. This skill is
a vanilla wrapper: it documents mnem as it ships and adds nothing on top.
**Verified against the mnem 0.1.3 release binary** (the newest release with
a Linux asset as of 2026-11-27 — see the install caveat below) **and the
0.1.7 tag source.** Commands marked **(0.1.7+)** exist in the 0.1.7 tag
source but not in the 0.1.3 binary; everything else was run against the
0.1.3 binary.

## When to use

- An agent needs memory that survives sessions and is shared across agents
  or machines (commit `.mnem/` alongside the code).
- You need to inspect what changed between sessions (`mnem log`, `mnem diff`),
  undo a bad ingest (`mnem revert`, `mnem tombstone`), or run two experiments
  in parallel on branches and merge the winner.
- You need retrieval with an explicit token budget — every query reports
  `tokens_used`, `candidates_seen`, and `dropped`; nothing is silently
  truncated.

## When NOT to use

- **Do NOT deploy the mnem store on Vercel or any serverless platform.**
  The store is an embedded redb database on local disk; serverless
  invocations have ephemeral disk and no long-lived process, so each request
  would see a different or empty store and writes would be lost. mnem needs
  a live process with a disk: a VPS, Fly.io/Railway with a volume, or a
  Docker container running `mnem http`.
- Not a transactional OLTP database (append-only, versioned history; no
  row-level UPDATE/DELETE semantics).
- Not sub-50 ms cloud-scale retrieval at 10k+ QPS; mnem is local-first.
- Not concurrent multi-writer: the redb store is single-writer (one writer
  at a time, many concurrent readers). Concurrent agent writes need an
  external queue or separate repos merged with `mnem merge`.

## Install

`mnem` is a single ~40 MB binary. No daemon, no external database, fully
offline. The bundled embedder is ONNX MiniLM-L6-v2, in-process — no API
keys, no Ollama, no network call for retrieval.

```bash
# Recommended: from source (Rust 1.95+; Linux needs g++), ~5-15 min
cargo install --locked mnem-cli --features bundled-embedder

# Or a prebuilt binary — see the caveat below about which releases
# actually ship a Linux tarball. v0.1.3 does:
# https://github.com/Uranid/mnem/releases/download/v0.1.3/mnem-x86_64-unknown-linux-gnu.tar.gz
# (extract; keep bin/ and lib/ together — the binary finds its bundled
# libonnxruntime via rpath; no LD_LIBRARY_PATH needed)

mnem --version   # confirm install
mnem doctor      # checks embedder + store + config, green/yellow/red
```

Or run `scripts/setup-mnem.sh` in this skill (downloads the newest
release binary that ships a Linux asset, verifies its sha256, then
smoke-tests it).

> **Embedder model download (verified 2026-11-27):** the "bundled"
> embedder is not in the binary — on first use mnem downloads the
> MiniLM-L6-v2 ONNX model (~92 MB) from HuggingFace into
> `~/.cache/huggingface/hub/models--Xenova--all-MiniLM-L6-v2/`. If that
> download fails (restricted network/proxy), nodes are still added but
> **without embeddings**, and retrieval falls back to a mock embedder
> and returns nothing useful. Workaround: download the two files with
> curl into the cache layout yourself
> (`onnx/model.onnx` and `tokenizer.json` under
> `.../models--Xenova--all-MiniLM-L6-v2/resolve/main/`), then re-run
> `mnem reindex` to backfill embeddings.

> **Known install caveat (verified 2026-11-27):** GitHub release v0.1.6
> ships only a Windows binary (`mnem.exe`); there is no v0.1.7 release tag
> and no Linux tarball under v0.1.6/v0.1.7. **v0.1.3 is the newest release
> with a Linux tarball** (`mnem-x86_64-unknown-linux-gnu.tar.gz`,
> sha256 `bc6d69a99322f474ee3aac7b6cee66061e5fcfaeae7387577eef7220e89b1e9d`).
> Because of that, `pip install mnem-cli` (0.1.7) fails on Linux with a
> 404 from its runtime downloader, and `cargo binstall mnem-cli` resolves
> to the same missing release archives. Prefer `cargo install` for 0.1.7,
> or the v0.1.3 release binary.

## Core workflow

```bash
mnem init                                   # once per project; creates .mnem/
mnem ingest README.md                       # file -> Doc + Chunk + Entity nodes
mnem ingest docs/ --recursive               # whole directory
mnem ingest --text "Deploy window is Tuesdays 10-11 AM UTC"   # (0.1.7+)
mnem retrieve "what did we decide about the API rate-limit design"

mnem add node --label Fact -s "Payments API uses idempotency keys"
mnem add edge --from <uuid> --to <uuid> --label depends_on
mnem get <uuid>                             # fetch a node by UUID (0.1.7+)
mnem tombstone <uuid> --reason "superseded" # soft-delete: hidden from
                                            # retrieval, kept in audit log (0.1.7+)
mnem status                                 # op-head, head commit, refs
mnem log                                    # walk the op-log backwards
```

Every ingest, add, tombstone, and delete produces a new commit. Commits chain
by parent CID; older commits are immutable and reachable. Re-ingesting an
unchanged file is a no-op (same bytes always produce the same CIDs).

### Versioning — branches and merges

```bash
mnem branch create experiment     # branch from current head
mnem branch list                  # * marks the branch at the current head
mnem switch main                  # switch HEAD (alias: mnem checkout main) (0.1.7+)
mnem merge experiment             # 3-way merge into HEAD
mnem merge experiment --dry-run   # preview outcome, persist nothing
mnem merge --continue             # finish after editing .mnem/MERGE_CONFLICTS.json
mnem merge --abort                # cancel; restore HEAD from ORIG_HEAD
mnem diff HEAD <cid>              # what changed between two ops
mnem revert <op-cid>              # undo one committed op (new inverse commit) (0.1.7+;
                                  # stub in 0.1.3 — use export + import as workaround)
mnem export backup.car            # snapshot as a CAR v1 archive
mnem import backup.car            # restore it on any machine
```

Conflicts land in `.mnem/MERGE_CONFLICTS.json` for explicit resolution.
See `references/versioning.md`.

> **0.1.3 branch quirk (verified):** in 0.1.3, new commits do **not**
> advance any branch ref — `main` stays at the init (seed anchor)
> commit, and a branch created with `branch create` stays at the head
> it was created from. After further commits the head is detached (no
> `*` in `branch list`), and `mnem merge` then fails with
> "cannot fast-forward: no `refs/heads/*` ref matches the current head".
> Fix: pin the head first — `mnem branch create <name>` at the current
> head — then merge. `mnem switch` (0.1.7+) is the proper way to move
> HEAD between branches.

### Local vs global graph

- Local: `.mnem/` in the project — project-specific facts, travels with the repo.
- Global: `~/.mnemglobal/.mnem/` — facts that span all projects (people,
  preferences, team conventions). Use `mnem global retrieve`, `mnem global
  add`, `mnem global ingest` (`get`/`tombstone`/`delete` on the global
  graph are 0.1.7+). The global graph is created by `mnem integrate`
  (verified: `mnem global add` fails with "Global graph not initialised"
  until `mnem integrate` has run once). `mnem integrate` wires agents to
  read local first and fall back to global automatically.

### Target a specific repo

```bash
mnem -R ~/notes status            # -R <path> redirects any command
```

## Retrieval

Hybrid semantic + keyword + graph retrieval in a single pass; results are
fused and the query reports exactly what it found, skipped, and cost.

```bash
mnem retrieve "what is our API retry policy"
mnem retrieve "..." --limit 20
mnem retrieve "..." --graph-expand 20              # multi-hop traversal
mnem retrieve "..." --graph-expand 20 --graph-mode ppr
mnem retrieve "..." --explain   # per-item lane scores
```

Output includes `tokens_used`, `candidates_seen`, `dropped`. If `dropped > 0`,
widen the budget (`--budget N`), tighten the query, or flag it to the user.
See `references/retrieval.md`.

## Agent surfaces

- **MCP (primary agent interface):** `mnem mcp` starts the server over
  stdio; `mnem integrate` wires it into Claude Code, Claude Desktop,
  Cursor, Continue, Zed, or Gemini CLI automatically (Hermes, hook-only,
  is 0.1.7+). 22 native tools prefixed `mnem_` in 0.1.7 (`mnem_retrieve`,
  `mnem_commit`, `mnem_ingest`, `mnem_tombstone`, global-graph tools,
  and more) — 19 of them in the 0.1.3 release binary (verified live via
  `tools/list`). Every response carries `_meta` with `bytes`,
  `latency_micros`, and `tokens_estimate`.
- **HTTP:** `mnem http` starts a JSON API on loopback (`127.0.0.1:9876` by
  default). **Note: the command is `mnem http`, not `mnem http serve`** —
  upstream docs and the Docker image's CMD use `http serve`, but the CLI
  rejects it ("unexpected argument 'serve' found", verified on 0.1.3).
  Docker: `docker run -p 9876:9876 -e MNEM_HTTP_ALLOW_NON_LOOPBACK=1
  ghcr.io/uranid/mnem:latest http --bind 0.0.0.0:9876`.
- **Python:** `pip install mnem-py`, `import pymnem` — dense vector
  retrieval only in v0.1.0; keyword search and graph traversal are not
  available from Python (use the CLI or HTTP API instead).

See `references/integrations.md` for the MCP tool table, the HTTP route
table, `mnem integrate` options, and the Python API.

## Configuration

```bash
mnem config set user.name "ci-agent"
mnem config set embed.provider ollama
mnem config set embed.model nomic-embed-text
mnem config set embed.base_url http://localhost:11434
mnem config get embed.provider
mnem config list
```

Config sources, highest precedence first: `MNEM_*` environment variables,
per-repo `.mnem/config.toml`, user-global `~/.mnem/config.toml`. API keys
live in environment variables — never written to disk. mnem rejects config
values that look like raw secrets (`embed.api_key`, any `embed.*` /
`rerank.*` value starting with `sk-`); use `api_key_env` (the name of an
environment variable) instead.

## Troubleshooting

- `mnem: command not found` — open a new terminal (PATH changes need a new
  session); pip installs to `~/.local/bin` on Linux — add it to PATH.
- `embedder not configured` — you installed without the bundled embedder.
  Reinstall with `--features bundled-embedder`, or set an embedder provider
  in config (`mnem config set embed.provider ollama`).
- `mnem retrieve` returns nothing — check you are in (or below) a directory
  containing `.mnem/`; use `mnem -R <path>` to point at a graph explicitly.
  Run `mnem doctor` first: it reports embedder, store, and config health.
  If `doctor` says the embedder cache is missing, the model download
  failed — see the install note above (pre-seed via curl, then
  `mnem reindex`). Nodes added while the embedder was unreachable have no
  vector; `mnem reindex` backfills them.
- `mnem global add/retrieve` errors "Global graph not initialised" — run
  `mnem integrate` once (it creates `~/.mnemglobal/.mnem/`).
- `mnem merge` fails "cannot fast-forward: no `refs/heads/*` ref matches
  the current head" (0.1.3) — pin the head first with
  `mnem branch create <name>`, then merge; see the branch quirk above.
- `mnem revert` / `mnem fsck` / `mnem gc` report "not yet implemented" —
  you are on 0.1.3; they are implemented in 0.1.7 (install via cargo), or
  use `mnem export` + `mnem import` as the interim workaround.
- `mnem integrate` wired but the agent sees `0 item(s)` — that means the
  graph is empty but the integration works. If no `mnem: N item(s)` appears
  at all: close and reopen the host application (not just the terminal) and
  launch it from inside the directory containing `.mnem/`.
- Push/pull blocks while `mnem http` runs against the same store — both take
  the single-writer lock. Stop the HTTP server first, or coordinate writes
  through an external queue.
- `pip install mnem-cli` 404 on Linux — known, see the install caveat above;
  use `cargo install --locked mnem-cli --features bundled-embedder`.

## References

- `references/commands.md` — full CLI reference (every subcommand and flag;
  verified against the 0.1.3 release binary, with (0.1.7+) markers for
  commands confirmed only in the 0.1.7 tag source).
- `references/retrieval.md` — hybrid retrieval lanes, fusion, token-budget
  transparency, GraphRAG flags.
- `references/versioning.md` — commits, branches, 3-way merge, CAR
  export/import, push/pull/clone, global vs local graph.
- `references/integrations.md` — MCP server and tools, HTTP API routes,
  `mnem integrate`, Python API.
