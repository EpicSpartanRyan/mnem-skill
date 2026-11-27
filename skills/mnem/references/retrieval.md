# Hybrid retrieval

Every `mnem retrieve` call fans out across up to three lanes and fuses the
results into a single ranked list. No lane is a separate query — it is one
pass, one budget.

## The three lanes

| Lane | What it does | When it runs |
|---|---|---|
| **Vector** | HNSW approximate nearest-neighbour search over dense embeddings stored in per-commit sidecar buckets. Finds semantically similar content even when the wording differs. | Always on when an embedder is configured. |
| **Sparse** | BM25 keyword matching (+ SPLADE learned-sparse where configured). Exact term overlap; strong for proper nouns, IDs, and precise queries. | Config-driven: enabled by a `[sparse]` block in `config.toml`. There is no `--sparse` flag — sparse participation is driven by config. |
| **Graph** | Multi-hop traversal over authored edges. Follows relationships between nodes to find connected context. | Opt-in per query with `--graph-expand N`. |

The embedding lives in a per-commit sidecar bucket, not on the node, so two
nodes with the same text but different embedders share one CID.

## Fusion

Results from all active lanes are fused into one ranked list via
Reciprocal Rank Fusion (RRF) — the retrieve code path fuses with
`weighted_reciprocal_rank_fusion` (verified in the 0.1.7 source and in
the 0.1.3 binary's behaviour). There is no `--fusion` flag: the 0.1.3
binary's `retrieve --help` top text mentions `--fusion rrf`, but the
flag does not exist in the binary or in the 0.1.7 source — that
description is stale. (Some upstream prose mentions a min-max convex
combination instead; that is the other fusion function in the codebase,
not the one the CLI retrieve path uses.)

Vector-only is the default and is what the 0.1.0 benchmark headline numbers
measure. Benchmarks use dense-only retrieval (no sparse/BM25 lane).

## Token-budget transparency

Every retrieve response reports three counters:

| Field | Meaning |
|---|---|
| `tokens_used` | How many tokens the returned results consume. |
| `candidates_seen` | How many nodes were evaluated before the token budget was applied. |
| `dropped` | How many candidates were cut at the budget boundary. |

Most memory systems silently truncate at the budget. mnem makes the cut
explicit: if `dropped > 0`, the agent can widen the budget (`--budget N`),
tighten the query, or flag the situation to the user. The decision is
visible, not hidden.

CLI example output (verified live against the 0.1.3 binary):

```
$ mnem retrieve "what does mnem do"
# 6 item(s), 278/unlimited tokens, 0 dropped, 6 candidates
---
[0] score=0.6388 tokens=28 id=00000000-0000-7000-8000-6d6e656d0001 Meta
  ntype: Meta
  id: 00000000-0000-7000-8000-6d6e656d0001
  summary: mnem is a persistent knowledge graph.
  name: mnem
---
[1] score=0.5373 tokens=44 id=01a21bee-c34c-78e0-b581-9485de50bc1a Doc
  ntype: Doc
  summary: mnem is a versioned knowledge graph for AI agents.
```

The header line is the token accounting: `N item(s), <tokens>/<budget>
tokens, <dropped> dropped, <candidates> candidates`. With `--limit 5`
on the same query the header became
`# 5 item(s), 229/unlimited tokens, 1 dropped, 6 candidates` — the cut
is explicit.

Via MCP, every tool response carries `_meta` with `bytes`,
`latency_micros`, and `tokens_estimate` so callers can reason about the
cost of their own calls.

## Flags

| Flag | Effect |
|---|---|
| `--limit N` / `-n N` | Final returned set size (no limit by default). |
| `--budget N` / `-b N` | Max rendered tokens in the combined output (default: unlimited). |
| `--vector-cap N` | Lift the dense pool size from default 256. Higher = better long-tail recall, +cost. |
| `--graph-expand N` | Add N neighbours of top-K seeds via authored edges. Audit-recommended default `20` when graph is on. |
| `--graph-mode <decay\|ppr>` | `decay` (default) weights by hop distance. `ppr` uses Personalised PageRank; better multi-hop recall, higher cost. |
| `--graph-decay <F>` | Score decay factor for expanded neighbours (default 0.7). |
| `--graph-etype <ETYPE>` | Restrict graph-expand to edges of this type (repeatable). |
| `--ppr-damping <F>` / `--ppr-iter <N>` | PPR damping (default 0.85) and power-iteration cap (default 15); only honored with `--graph-mode ppr`. |
| `--label <X>` / `-l <X>` **(0.1.7+)** | Post-retrieval filter by node type; repeatable. The budget/limit applies before filtering. Not in 0.1.3. |
| `--hyde [PROVIDER:MODEL]` | HyDE: ask an LLM to generate a hypothetical answer, embed that instead of the query. Requires `[llm]` config. |
| `--multi-query [N]` | RAG-Fusion: N query variations + the original, RRF-fused (default N=4). Requires `[llm]` config. Mutually exclusive with `--hyde`. |
| `--community-filter` | Cluster content; drop low-coverage communities before fusion. (Experiment E1: with no pre-computed `CommunityAssignment` wired in, the flag is a no-op — the pipeline stays byte-identical to `--community-filter=false`.) |
| `--community-min-coverage F` | Minimum fraction of top-K fused weight surviving communities must cover (default `0.5`). Requires `--community-filter`. |
| `--rerank <provider:model>` | Post-fusion cross-encoder reorder. Supports `cohere:rerank-english-v3.0`, `voyage:rerank-1`, `jina:jina-reranker-v3`, local. Requires the provider API key in the env var named by `rerank.api_key_env` (defaults: `COHERE_API_KEY`, `VOYAGE_API_KEY`, `JINA_API_KEY`). On any adapter error the retriever silently falls back to the fused order. |
| `--rerank-top-k N` | Top-K of the fused list to re-score (default: 25). Requires `--rerank`. |
| `--summarize` | Centroid + MMR summary of the top-K, with diversity. |
| `--summarize-k N` | Summary sentences to pick (default 3; ignored unless `--summarize`). |
| `--explain` | Print extra diagnostic lines (multi-query variant list, HyDE preview). Off by default so scripts see clean output. |
| `--where KEY=VALUE` | Property-equality gate on results (VALUE parses as JSON when possible, otherwise as a string). |
| `--no-vector` | Disable the cosine-vector ranker for this call, even when an embedder is configured. |
| `--embed-model <model>` | Override the configured embedding model for this call only. |

## Staged examples

```bash
# Dense baseline
mnem retrieve "what does this project do"

# Add multi-hop graph traversal
mnem retrieve "..." --graph-expand 20

# Full stack: graph-expand + community-filter + PPR + rerank
mnem retrieve "..." --graph-expand 20 --community-filter --graph-mode ppr --rerank cohere:rerank-english-v3.0

# Ingest with KeyBERT keyphrase enrichment (strengthens sparse + community signals)
mnem ingest --extractor keybert notes.md
```

## When to enable which stage

- **Single-document corpus, simple queries**: leave graph off; vector alone is enough.
- **Multi-hop / compositional questions**: `--graph-expand 20`.
- **Long history with cross-document references**: add `--community-filter`.
- **Recall ceiling needed**: stack `--rerank` on top.
- **Keyphrase-enriched ingest**: `mnem ingest --extractor keybert` at ingest time.

## Embedder providers

The bundled default is ONNX MiniLM-L6-v2 (`all-MiniLM-L6-v2`, 22M params,
384-dim, English), running in-process. Switch providers with one line of
config — no code change:

```toml
# .mnem/config.toml
[embed]
provider = "ollama"
model = "nomic-embed-text"
base_url = "http://localhost:11434"
```

Providers: `onnx` (bundled; also `bge-large-en-v1.5` via Xenova ONNX),
`ollama`, `openai`, `cohere`, `mock` (tests). The ONNX provider's own
default model string is `bge-large-en-v1.5`; the `bundled-embedder` cargo
feature pins the default to `all-MiniLM-L6-v2` (verified in source:
`BUNDLED_EMBEDDER_DEFAULT_MODEL` in `crates/mnem-cli/src/config.rs`).

> **Model download (verified 2026-11-27):** the ONNX model is not in
> the binary — mnem downloads it from HuggingFace on first use
> (~92 MB, cached at
> `~/.cache/huggingface/hub/models--Xenova--all-MiniLM-L6-v2/`).
> If the download fails, mnem prints a note
> ("ONNX embedding failed ...") and falls back to a **mock embedder**:
> nodes are added without vectors and `mnem retrieve` returns
> `0 item(s)` with a warning ("using mock embedder for retrieval -
> semantic results unreliable"). Fix: pre-seed the cache with curl
> (`onnx/model.onnx` + `tokenizer.json`, see SKILL.md), then
> `mnem reindex` to backfill embeddings.

`mnem reindex` backfills embeddings after switching providers or models.
