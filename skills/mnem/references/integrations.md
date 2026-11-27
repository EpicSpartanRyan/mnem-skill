# Integrations: MCP, HTTP, mnem integrate, Python

mnem exposes the same retrieval engine through four interfaces. They all
hit the same graph.

## MCP server (primary agent interface)

`mnem mcp` starts an MCP JSON-RPC server over stdio. It runs in-process: no
separate daemon, no port to manage. The embedder is bundled (MiniLM-L6-v2,
ONNX); no network calls unless you wire a remote provider.

```bash
mnem mcp                        # start the server (stdio)
mnem mcp --repo ~/notes         # point it at a specific graph
```

The field-level schema of every tool lives in the upstream source at
`crates/mnem-mcp/src/tools/descriptions.rs` (there is no `--list-tools`
flag on the 0.1.7 CLI, despite what the upstream `docs/src/mcp.md` says).

Manual registration in any MCP client:

```json
{
  "mcpServers": {
    "mnem": {
      "command": "mnem",
      "args": ["mcp", "--repo", "/path/to/your-graph"]
    }
  }
}
```

### Tools (22 native tools in 0.1.7, prefix `mnem_` — 21 stable + 1 feature-gated; 19 in the 0.1.3 release binary, verified live via `tools/list`)

Every response carries `_meta` with `bytes`, `latency_micros`, and
`tokens_estimate`. Writes propagate `agent_id` and `task_id` into commit
metadata so provenance is always queryable.

> **Version note:** the 0.1.3 binary's `tools/list` returns 19 tools.
> Missing there (0.1.7+): `mnem_list_tags`, `mnem_incoming_edges`,
> `mnem_global_tombstone_node`. `mnem_community_summarize` **is**
> present in the 0.1.3 list; in the 0.1.7 source it is behind the
> `summarize` cargo feature.

**Introspection**

| Tool | Purpose |
|---|---|
| `mnem_stats` | Repo overview: op-head, head commit, ref summary, known labels. Cheap; call first to orient an agent to a new graph. |
| `mnem_schema` | Inspect node labels and edge predicates in the current commit. Use before writing queries or traversals. |
| `mnem_list_nodes` | Enumerate nodes at the current head, optionally filtered by label. Returns UUID + label + summary per node. |
| `mnem_list_tags` **(0.1.7+)** | List all named tags (`refs/tags/*`). |
| `mnem_recent` | Walk the op-log from HEAD backwards. Last N operations with time, author, `agent_id`, `task_id`, and message. |

**Retrieval**

| Tool | Purpose |
|---|---|
| `mnem_retrieve` | Primary retrieval tool. Hybrid semantic + sparse + graph search. Returns nodes pre-rendered to text plus `tokens_used` / `dropped` / `candidates_seen`. Supports graph-expand, community filter, PPR, and cross-encoder rerank. |
| `mnem_global_retrieve` | Same, but always targets the global graph (`~/.mnemglobal/.mnem/`). |
| `mnem_search` | Exact-property match with optional edge traversal. Fast and deterministic — no embedding required. |
| `mnem_vector_search` | Raw cosine-similarity nearest-neighbour search over stored node embeddings. Pass a model name and query vector; receive top-k matches. |
| `mnem_get_node` | Fetch a single node by UUID. Full props, content size, outgoing edge count. |
| `mnem_traverse` | From a start node, list outgoing neighbours reachable via specified edge labels. |
| `mnem_incoming_edges` **(0.1.7+)** | List all edges pointing to a node (reverse lookup). Equivalent to `mnem blame` in the CLI. |

**Writes**

| Tool | Purpose |
|---|---|
| `mnem_commit` | Add nodes and/or edges as a single commit. Returns the new op-id, commit CID, and created node UUIDs. |
| `mnem_commit_relation` | Compound write: resolve-or-create a subject node, resolve-or-create an object node, and connect them with a typed edge — all in one call. Prevents the duplicate-entity problem. |
| `mnem_resolve_or_create` | Find-or-create a node by a primary-key property. If a matching `(label, anchor-property) == value` exists, its UUID is returned; otherwise a new node is committed. |
| `mnem_ingest` | Ingest a file path or inline text as a `Doc + Chunk + Entity` subgraph. Accepts `{path: "notes.md"}` or `{text: "...", source: "label"}`. Chunker options: `auto`, `paragraph`, `recursive`, `sentence_recursive`, `session`, `structural`. |
| `mnem_global_ingest` | Same as `mnem_ingest` but writes to the global graph. |
| `mnem_global_add` | Write nodes and/or edges directly to the global graph. |

`mnem_commit_relation` example:

```json
{
  "subject": "Alice",
  "subject_kind": "Entity:Person",
  "predicate": "works_at",
  "object": "Globex",
  "object_kind": "Entity:Organization",
  "agent_id": "onboarding-agent"
}
```

**Deletes**

| Tool | Purpose |
|---|---|
| `mnem_tombstone_node` | Soft-delete: marks a node as forgotten. Hidden from retrieval by default; the node CID and all prior commits remain intact for auditing. Use when a user says "forget X" or revokes consent. |
| `mnem_global_tombstone_node` **(0.1.7+)** | Same, on the global graph. |
| `mnem_delete_node` | Hard-delete: removes the node from the current head. Prior commits that referenced it remain addressable. Use only to free storage, not for memory hygiene. |

**Optional (feature-gated)**

| Tool | Purpose |
|---|---|
| `mnem_community_summarize` | Extractive Centroid + MMR summarizer over a caller-supplied set of node UUIDs. No LLM call — picks `k` sentences balancing proximity to the community centroid against diversity. Enabled via the `summarize` cargo feature (0.1.7 source); present in the 0.1.3 binary's `tools/list` as shipped. |

**Local vs global:** `mnem_retrieve` searches the repo the server is
pointed at. `mnem_global_retrieve` always searches
`~/.mnemglobal/.mnem/` regardless of `--repo`.

## `mnem integrate` — wire into an agent host

One command wires mnem into your agent host. For MCP-aware hosts it adds
the MCP server, an auto-retrieval trigger where the host supports hooks,
and the mnem system prompt where the host has a rules file. Restart the
host (close and reopen the application, not just the terminal) and the agent
starts using mnem automatically. Verify: send any message — you should see
`mnem: N item(s)` before the model replies. `0 item(s)` means the graph is
empty but the integration is working.

```bash
mnem integrate                           # interactive: detect hosts, prompt
mnem integrate claude-code               # wire a specific host
mnem integrate hermes                    # wire Hermes pre/post LLM hooks only (0.1.7+)
mnem integrate --all                     # wire every detected host, no prompt
mnem integrate --check                   # report wired state; nothing changes
mnem integrate --dry-run                 # preview what would be written
mnem integrate --show claude-code        # print the MCP JSON block for manual copy-paste
mnem integrate --no-hooks                # skip UserPromptSubmit hook wiring
mnem integrate --no-system-prompt        # skip system prompt wiring
mnem integrate --target-repo ~/notes     # point the MCP server at a specific
                                         # graph, not the global one

mnem unintegrate                         # interactive: pick hosts to remove
mnem unintegrate claude-code             # remove one host
mnem unintegrate --all                   # remove all wired hosts
```

Auto-detected hosts: Claude Code, Claude Desktop, Cursor, Continue, Zed,
Gemini CLI (verified in the 0.1.3 binary's `doctor` and
`integrate --check` output), plus Hermes Agent in 0.1.7+. Any other
MCP-aware host works via a hand-edited `mcpServers` entry pointing at
`mnem mcp --repo <path>`.

What gets wired:

- **MCP server** (`mcpServers.mnem`) — via `mnem mcp --repo <graph>`;
  defaults to the global graph (`~/.mnemglobal/.mnem`).
- **Auto-retrieval trigger** — Claude Code gets a `UserPromptSubmit` hook;
  Hermes Agent gets `pre_llm_call` / `post_llm_call` shell hooks in
  `$HERMES_HOME/config.yaml` (default `~/.hermes/config.yaml`). Both
  retrieve from the local graph first (walking up from the current
  directory) and fall back to `mnem global retrieve`.
- **System prompt** — mnem usage instructions injected into hosts with
  project-rules files. Hermes is deliberately excluded: its hook contract
  is designed for +1 user-context enrichment rather than system-prompt
  edits. `mnem integrate hermes` writes the hooks plus
  `$HERMES_HOME/hooks/mnem/hermes-hook.py`; `pre_llm_call` retrieves local
  memory and falls back to global; `post_llm_call` commits the turn back.
  A timestamped `.bak-*` file is written before config changes.

Troubleshooting: not seeing `mnem: N item(s)`? Close and reopen the
**application** (not just the terminal); open the application from inside
the directory containing `.mnem/`; run `mnem doctor`; run
`mnem integrate --check`.

## HTTP API

```bash
mnem http                                # JSON API, loopback 127.0.0.1:9876
mnem http --bind 0.0.0.0:9876            # expose (requires MNEM_HTTP_ALLOW_NON_LOOPBACK=1)
mnem http --in-memory                    # ephemeral in-memory store (no .mnem/ required)
mnem http --metrics / --no-metrics      # force /metrics endpoint on/off
```

`mnem http` runs in the foreground; Ctrl+C stops it. For a persistent
background server use your OS process manager (`nohup mnem http &` on
Linux/macOS). Concurrency: any number of concurrent readers, one writer at
a time (single-writer lock). `mnem reindex` while the server is active
waits for in-progress writes; ongoing reads keep working but may see stale
embeddings until the reindex commit lands.

Docker:

```bash
docker run --rm -p 9876:9876 -e MNEM_HTTP_ALLOW_NON_LOOPBACK=1 \
  ghcr.io/uranid/mnem:latest http --bind 0.0.0.0:9876
```

> **Note:** the upstream Docker image's own CMD uses `http serve`, which
> the 0.1.3 CLI rejects (`error: unexpected argument 'serve' found`,
> verified). Override the command as above — plain `http --bind ...`.

Authentication: by default `mnem http` has no authentication. Set
`MNEM_HTTP_AUTH_TOKEN=<token>` on the server to require a bearer token on
write routes; the server rejects wrong/missing tokens with HTTP 401.

### Routes

| Method | Route | Purpose |
|---|---|---|
| GET | `/v1/healthz` | Liveness probe. |
| GET | `/v1/stats` | Head op-id, commit CID, ref + label counts. |
| GET | `/v1/log` **(0.1.7+)** | Op-log (default limit 20; `?limit=N`). Fields: `cid`, `description`. Returns 404 on 0.1.3 (verified). |
| GET | `/v1/export` **(0.1.7+)** | Export the graph as a CAR archive. Returns 404 on 0.1.3 (verified). |
| GET | `/v1/blocks/{cid}` **(0.1.7+)** | Fetch one block by CID. |
| POST | `/v1/import` **(0.1.7+)** | Import a CAR archive. |
| GET | `/v1/diff` **(0.1.7+)** | Diff two ops. |
| POST | `/v1/merge` **(0.1.7+)** | 3-way merge. |
| POST | `/v1/nodes` | Commit a new node (label + summary + props). |
| POST | `/v1/nodes/bulk` | Commit several nodes at once. |
| POST | `/v1/edges` **(0.1.7+)** | Commit a new directed edge. |
| GET/DELETE | `/v1/nodes/{id}` | Fetch / delete a node. (GET on `/v1/nodes` itself is 405 on 0.1.3 — there is no list endpoint there.) |
| GET | `/v1/nodes/{id}/embedding` **(0.1.7+)** | Fetch a stored embedding vector. |
| POST | `/v1/nodes/{id}/tombstone` | Tombstone a node. |
| GET/POST | `/v1/retrieve` | Agent-facing retrieval (`?text=&budget=&limit=`). |
| POST | `/v1/ingest` | Ingest a file or inline text. |
| POST | `/v1/explain` | Explain a retrieve result. |
| POST | `/v1/traverse_answer` | Traversal-based answering. |
| GET/POST | `/v1/branches` **(0.1.7+)** | List / create branches. Returns 404 on 0.1.3 (verified). |
| DELETE | `/v1/branches/{*name}` **(0.1.7+)** | Delete a branch by name. |
| GET/POST | `/v1/tags` **(0.1.7+)** | List / create tags. Returns 404 on 0.1.3 (verified). |
| DELETE | `/v1/tags/{*name}` **(0.1.7+)** | Delete a tag by name. |
| GET | `/remote/v1/refs` | Transport: list refs (push/pull). |
| POST | `/remote/v1/fetch-blocks` | Transport: fetch blocks. |
| POST | `/remote/v1/push-blocks` | Transport: push blocks (auth). |
| POST | `/remote/v1/advance-head` | Transport: advance head (auth). |
| GET | `/metrics` | Prometheus text exposition (only when metrics enabled). |

Unmarked routes were verified live against the 0.1.3 HTTP server (the
server prints its route list at startup; `/v1/healthz`, `/v1/stats`,
and `/v1/retrieve` were also exercised with curl). **(0.1.7+)** routes
come from the route table in `crates/mnem-http/src/lib.rs`,
`route_table()`, in the 0.1.7 tag source. Field names follow the CLI
wire format; the `main` branch has since renamed `POST /v1/edges`
response field `edge_id` → `id` and `GET /v1/log` fields `op_id`/`message`
→ `cid`/`description` — check the CHANGELOG when upgrading past 0.1.7.

## Python API (`mnem-py`)

Dense vector retrieval only (v0.1.0). Keyword search (BM25/SPLADE) and
graph traversal (`--graph-expand`, `--graph-mode ppr`) are not available
from Python — use the CLI or HTTP API instead; all three work on the same
on-disk graph.

```bash
pip install mnem-py
pip install sentence-transformers   # optional — or supply embeddings yourself
```

```python
import pymnem
from sentence_transformers import SentenceTransformer

model = SentenceTransformer("all-MiniLM-L6-v2")   # downloaded once, ~23 MB
MODEL_NAME = "all-MiniLM-L6-v2"                    # must match at ingest AND retrieve

repo = pymnem.Repo.open_or_init("my-graph/")      # creates .mnem/ if missing

with repo.transaction(author="agent", message="seed") as tx:
    for text in ["Alice lives in Berlin", "Bob moved to Paris"]:
        tx.add_node(ntype="Memory", summary=text)
        tx.add_embedding_f32(MODEL_NAME, model.encode(text).tolist())

query_vec = model.encode("Alice Berlin").tolist()
result = repo.retrieve(vector=query_vec, model=MODEL_NAME, token_budget=500, limit=5)
for item in result:
    print(f"{item.score:.3f}  {item.summary}")
print(f"tokens_used={result.tokens_used}  tokens_budget={result.tokens_budget}")
```

Rules that bite:

- `MODEL_NAME` at retrieve time **must match** the one at ingest time. A
  mismatch silently returns zero results — no exception is raised. Recover
  with `mnem reindex` after configuring the correct model in
  `.mnem/config.toml`.
- `add_embedding_f32` must immediately follow its paired `add_node` call;
  calling it before `add_node` raises an error.
- `open_or_init("my-graph/")` is relative to the working directory when
  Python runs — use an absolute path to avoid opening a different graph.
- `init_memory()` is in-memory only; data is lost when the process exits.
- Any embedding model works as long as it returns a fixed-length float
  list (OpenAI, Cohere, any local HuggingFace model) — use the same
  `MODEL_NAME` string at both ingest and retrieve time.
