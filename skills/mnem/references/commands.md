# mnem CLI reference

Verified against the mnem **0.1.3 release binary** (live smoke test,
2026-11-27 — the newest release with a Linux asset) and the **0.1.7 tag
source** (the `Cmd` enum in `crates/mnem-cli/src/main.rs` and the CLI
source). **(0.1.7+)** marks a command/flag that exists in the 0.1.7 tag
source but is absent from the 0.1.3 binary. Every command accepts
`--help`. Global flag: `mnem -R <path>` redirects any command to a
specific repo directory.

Running bare `mnem` with no subcommand starts an interactive setup wizard.

## Setup and health

| Command | What it does |
|---|---|
| `mnem init [path]` | Create `.mnem/` in path (default: cwd). Required once per project before ingest/retrieve. |
| `mnem doctor` | Probe embedder + store + config; green/yellow/red checklist. Exits 1 if any check fails. Non-mutating. |
| `mnem stats` | One-line summary: nodes, edges, refs, store size. |
| `mnem status` | Op-head CID, head commit, all named refs, label counts. |
| `mnem completions <bash\|zsh\|fish\|powershell\|elvish>` | Emit a shell completion script. |

## Writing

| Command | What it does |
|---|---|
| `mnem ingest <file>` | Parse a file into Doc + Chunk + Entity nodes. Type auto-detected: Markdown uses heading-aware chunking; source code uses Tree-sitter function/class-level parsing; PDFs use sliding-window extraction. No LLM call at ingest; same bytes always produce the same CIDs; re-ingesting an unchanged file is a no-op. |
| `mnem ingest <dir> --recursive` | Ingest a whole directory. |
| `mnem ingest --text "..."` **(0.1.7+)** | Ingest inline text without a file. Not in 0.1.3 (`error: unexpected argument '--text' found` — verified). |
| `mnem ingest --chunker <auto\|paragraph\|recursive\|sentence_recursive\|session\|structural>` | Chunking strategy (default: auto). 0.1.3's help text names only `session \| paragraph \| recursive` as explicit choices. |
| `mnem ingest --extractor keybert <file>` | Keyphrase enrichment for stronger sparse retrieval. |
| `mnem ingest --max-tokens N <file>` | Token budget per chunk (default: 512). |
| `mnem ingest --overlap N <file>` | Overlap tokens between chunks (default: 32). |
| `mnem add node -s "..."` | Commit a single fact node. Also: `-m/--message`, `--no-embed` (skip the embedder for this node), `--id <uuid>` (caller-supplied node UUID), `--deterministic` (derive the UUID from label + sorted props). |
| `mnem add node --label Fact -s "..."` | Node with a label; labels let retrieval filter by type later. |
| `mnem add node --label Person --prop name=Alice -s "..."` | Node with properties. |
| `mnem add edge --from <uuid> --to <uuid> --label depends_on` | Connect two existing nodes with a typed edge. |
| `mnem get <uuid>` **(0.1.7+)** | Fetch a node by UUID (label, summary, props). |
| `mnem get <uuid> --content` **(0.1.7+)** | Also print the content body. |
| `mnem tombstone <uuid>` **(0.1.7+)** | Soft-delete: hidden from retrieval and query, kept in blockstore and op-log for auditing. Prefer over `delete` when an audit trail matters. |
| `mnem tombstone <uuid> --reason "..."` **(0.1.7+)** | Record why it was forgotten. |
| `mnem delete <uuid>` **(0.1.7+)** | Hard-delete from the current view. No audit trail; the block remains until `mnem gc`. |

## Reading

| Command | What it does |
|---|---|
| `mnem retrieve "query"` | Hybrid retrieval (vector + sparse + graph). Returns nodes pre-rendered to text plus `tokens_used` / `candidates_seen` / `dropped`. |
| `mnem retrieve "..." --limit N` / `-n N` | Max items to return (no limit by default). |
| `mnem retrieve "..." --budget N` / `-b N` | Max rendered tokens in the combined output (default: unlimited). |
| `mnem retrieve "..." --where KEY=VALUE` | Property-equality gate on results. |
| `mnem retrieve "..." --vector-cap N` | Widen the dense candidate pool (default: 256). |
| `mnem retrieve "..." --graph-expand N` | Add N graph neighbours of top-K seeds (multi-hop traversal). |
| `mnem retrieve "..." --graph-mode <decay\|ppr>` | Graph scoring: `decay` (default, weights by hop distance) or `ppr` (Personalised PageRank; better multi-hop recall, higher cost). |
| `mnem retrieve "..." --graph-decay <F>` | Score decay factor for expanded neighbours (default 0.7). |
| `mnem retrieve "..." --graph-etype <ETYPE>` | Restrict graph-expand to edges of this type (repeatable). |
| `mnem retrieve "..." --ppr-damping <F>` / `--ppr-iter <N>` | PPR damping (default 0.85) and power-iteration cap (default 15); only honored with `--graph-mode ppr`. |
| `mnem retrieve "..." --label <X>` / `-l <X>` **(0.1.7+)** | Post-retrieval filter by node type; repeatable. Not in 0.1.3 (the `add node` help text mentions it, but the flag does not exist there — verified). |
| `mnem retrieve "..." --hyde [PROVIDER:MODEL]` | HyDE: ask an LLM to generate a hypothetical answer, embed that instead of the query. Requires `[llm]` config. |
| `mnem retrieve "..." --multi-query [N]` | RAG-Fusion: N query variations + the original, RRF-fused (default N=4). Requires `[llm]` config. Mutually exclusive with `--hyde`. |
| `mnem retrieve "..." --community-filter` | Drop low-coverage communities before fusion. |
| `mnem retrieve "..." --rerank <provider:model>` | Post-fusion cross-encoder rerank, e.g. `cohere:rerank-english-v3.0`, `voyage:rerank-1`. Requires the provider API key in the env var named by `rerank.api_key_env`. |
| `mnem retrieve "..." --rerank-top-k N` | Top-K of the fused list to re-score (default: 25). Requires `--rerank`. |
| `mnem retrieve "..." --summarize` | Centroid + MMR summary of the top-K. |
| `mnem retrieve "..." --summarize-k N` | Summary sentences to pick (default 3; ignored unless `--summarize`). |
| `mnem retrieve "..." --explain` | Print extra diagnostic lines (multi-query variant list, HyDE preview). Off by default. |
| `mnem retrieve "..." --no-vector` | Disable the cosine-vector ranker for this call. |
| `mnem retrieve "..." --embed-model <model>` | Override the configured embedding model for this call only. |
| `mnem query --where name=Alice` | Exact-match property filter with optional edge traversal. No embedding needed — fast and deterministic. |
| `mnem query --where kind=Person -n 25 --with-outgoing knows` | Follow outgoing edges; repeat `--with-outgoing` to chain hops. |
| `mnem traverse <node-uuid>` **(0.1.7+)** | List outgoing neighbours, optionally `--edge-label knows` (repeatable with `-e`), `--limit N`, `--json`. |
| `mnem blame <node-uuid>` | List all incoming edges to a node — who points at it, in which commit. |
| `mnem blame <node-uuid> --etype authored` | Filter to one edge type. |
| `mnem blame <node-uuid> --first-writer` | Oldest ancestor commit per edge (BFS over op ancestry). |
| `mnem schema` / `mnem schema --json` **(0.1.7+)** | Node labels, indexed props, adjacency index presence. |

## History and versioning

| Command | What it does |
|---|---|
| `mnem log` | Walk the op-log backwards, last 20 entries. |
| `mnem log -n 50` / `--oneline` / `--format json` | More entries, compact format, machine-readable JSON. |
| `mnem show` / `mnem show <cid>` | Decode and pretty-print the current op-head block, or any block by CID. |
| `mnem cat-file <cid>` / `mnem cat-file <cid> --json` | Emit raw DAG-CBOR bytes for any block, or decode to DAG-JSON. |
| `mnem diff <op-a-cid> <op-b-cid>` | Ref deltas plus structural node/edge diff. `mnem diff HEAD <cid>` is the common form. |
| `mnem branch list` | List all branches; `*` marks the branch at the current head (no `*` when the head is detached — see the 0.1.3 quirk in SKILL.md). |
| `mnem branch create <name>` | Branch from current head. |
| `mnem branch create <name> --from HEAD` / `--from <cid>` | Branch from a ref, branch name, or CID. A positional start point works too (`mnem branch create <name> <start-point>`). |
| `mnem branch delete <name>` | Delete a local branch pointer. |
| `mnem tag list` / `mnem tag create v1.0 [--from <cid>]` / `mnem tag delete v0.9` **(0.1.7+)** | Tags (`refs/tags/*`). |
| `mnem switch <branch>` **(0.1.7+)** | Switch HEAD to an existing branch. Alias: `mnem checkout <branch>`. |
| `mnem merge <branch>` | 3-way merge into HEAD (LCA + structured conflict detector). |
| `mnem merge <branch> --strategy=ours\|theirs` | Auto-resolve: keep current side / take incoming side. Default is `manual` (conflicts left for review). |
| `mnem merge <branch> --dry-run` | Preview outcome without persisting anything. |
| `mnem merge --continue` | Finish after editing `.mnem/MERGE_CONFLICTS.json`. |
| `mnem merge --abort` | Cancel; restore HEAD from ORIG_HEAD. |
| `mnem revert <op-cid>` **(0.1.7+)** | Undo a single committed op by replaying its inverse (new commit). `--message "reason"` optional. Reverting a revert restores the original. In 0.1.3 this is an unimplemented stub (verified error: "mnem revert: not yet implemented"). |
| `mnem ref list` | List all refs (`refs/heads/*`, `refs/remotes/*`, ...). |
| `mnem ref set <name> <target-cid>` | Point a ref at a commit CID. |
| `mnem ref delete <name>` | Delete a named ref. |
| `mnem export backup.car` | Export the subtree reachable from HEAD as a CAR v1 archive. |
| `mnem export --from refs/heads/main out.car` / `--from <cid>` | Export from a specific ref or commit. |
| `mnem export -` | Write CAR to stdout (pipe over SSH). |
| `mnem import <path>` / `mnem import -` | Import a CAR archive (file or stdin). Every block is CID-verified before storage. |

## Sync (remotes)

Remotes are registered with `mnem remote add <name> <url>`; `<url>` is an
HTTP(S) server address (`http://my-server:9876`) or a `file://` CAR path.
Wire format is CAR v1.

| Command | What it does |
|---|---|
| `mnem remote add <name> <url>` | Register a remote. |
| `mnem remote add <name> <url> --token-env MNEM_REMOTE_ORIGIN_TOKEN` | Bearer token via env var (never hard-code the token). |
| `mnem remote list` / `mnem remote show <name>` / `mnem remote remove <name>` | Manage remotes. |
| `mnem push` | Push HEAD to origin/main. `mnem push <remote> <branch>` for explicit targets. |
| `mnem pull` | Fast-forward origin/main into HEAD. `mnem pull <remote> <branch>`. |
| `mnem fetch` / `mnem fetch <remote>` | Fetch without merging (tracking refs under `refs/remotes/<name>/*`). |
| `mnem clone <url> [<dir>]` | Clone a CAR archive: `file:///tmp/repo.car`, or a bare `.car` path. |

Server side for push/pull: `MNEM_HTTP_ALLOW_NON_LOOPBACK=1 mnem http
--bind 0.0.0.0:9876`, plus `MNEM_HTTP_AUTH_TOKEN=<token>` to require a
bearer token (client: `MNEM_REMOTE_ORIGIN_TOKEN=<token>`). Without a token
the server has no authentication. Single-writer note: push/pull take the
write lock; if `mnem http` runs against the same store, the push blocks
until the server releases any in-progress write — stop the server first for
a clean push.

## Global graph

All subcommands operate exclusively on `~/.mnemglobal/.mnem/`:

```bash
mnem global retrieve "query"
mnem global add node --label Convention -s "..."
mnem global ingest contacts.md
mnem global get <uuid>          # (0.1.7+)
mnem global tombstone <uuid>    # (0.1.7+)
mnem global delete <uuid>       # (0.1.7+)
```

The global graph is created by `mnem integrate` (verified: before that,
`mnem global add` fails with "Global graph not initialised ... hint: run
`mnem integrate` to create it").

## Embeddings and maintenance

| Command | What it does |
|---|---|
| `mnem reindex` | Backfill embeddings for nodes that lack one. |
| `mnem reindex --label Doc` / `--since <commit>` / `--force` / `--dry-run` | Restrict scope, re-embed indexed nodes, or count only. |
| `mnem embed --force` / `mnem embed --label Person` | Re-embed already-indexed nodes (label-scoped). |
| `mnem embedding get <node-uuid> <model>` **(0.1.7+)** | Print a stored vector as space-separated floats. |
| `mnem embedding ls <node-uuid>` **(0.1.7+)** | List stored model identifiers for a node. |
| `mnem embedder audit` | CI check: every provider declares a noise floor. |
| `mnem fsck` | Check the object DAG for corruption (reachability-only). **Stub in 0.1.3** (verified: "not yet implemented"); implemented in 0.1.7. |
| `mnem gc` | Garbage-collect unreferenced blocks. **Stub in 0.1.3** (verified: "not yet implemented"); implemented in 0.1.7. |
| `mnem config set <key> <value>` / `get` / `unset` / `list` | See SKILL.md "Configuration" for known keys. |
| `mnem repos list` / `set-default <path>` / `prune` | Registry of repos wired with `mnem integrate`. |

## Serving

| Command | What it does |
|---|---|
| `mnem mcp` | MCP JSON-RPC server over stdio. |
| `mnem mcp --repo ~/notes` | Point the server at a specific graph. |
| `mnem http` | HTTP JSON API; loopback bind `127.0.0.1:9876` by default. |
| `mnem http --bind 0.0.0.0:9876` | Expose on all interfaces (requires `MNEM_HTTP_ALLOW_NON_LOOPBACK=1`). |
| `mnem http --in-memory` | Ephemeral in-memory store (no `.mnem/` required). |
| `mnem http --metrics` / `--no-metrics` | Force the `/metrics` endpoint on/off. |
| `mnem integrate [host]` | Wire mnem into an agent host (see `references/integrations.md`). |
| `mnem unintegrate [host]` / `--all` / `--dry-run` | Remove the wiring. |
| `mnem bench` | Benchmark harness (TUI; `mnem bench run --benches longmemeval --limit 50 --non-interactive`). |

Note: upstream docs in two places show `mnem http serve`; the CLI takes
no `serve` subcommand — the server command is plain `mnem http`. Verified
live on the 0.1.3 binary (`mnem http serve` → `error: unexpected argument
'serve' found`) and in the 0.1.7 source (`ServeArgs` has
`--repo/--bind/--in-memory/--metrics/--no-metrics` and no subcommand).
The upstream Docker image's own CMD uses `http serve`, which fails on
the 0.1.3 binary — override it with `http --bind 0.0.0.0:9876` (see
SKILL.md).
