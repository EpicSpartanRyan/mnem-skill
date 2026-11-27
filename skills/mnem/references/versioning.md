# Versioning: commits, branches, merges, sync

mnem treats every write as a commit — the same way git treats every save as
a snapshot. Every node and edge you add becomes part of a content-addressed
commit in a Merkle DAG.

## Core concepts

- **Node** — content + metadata, addressed by its **CID** (content
  identifier derived from a hash of canonical bytes). Two nodes with
  identical content collapse to one CID. Nodes carry `text`, a `label`
  (string scope; queries can filter by label), and `metadata` (opaque JSON
  map). The embedding lives in a per-commit sidecar bucket, not on the
  node, so two nodes with the same text but different embedders share one
  CID.
- **Commit** — a snapshot of the graph at a point in time. Every ingest,
  every edit, every tombstone produces a new commit. Commits chain by
  parent CID; the head commit is the working tree's "current state". Older
  commits are immutable and reachable.
- **Label** — an opt-in namespace string attached to nodes at ingest time.
  Used for per-user / per-conversation isolation, bench harness scoping, and
  coarse multi-tenancy. A query without a label sees the whole repo; a query
  with a label sees only nodes carrying that label.
- **CID** — content-addressed ID. Objects are encoded as DAG-CBOR (a
  canonical binary format) and hashed with BLAKE3. The same bytes always
  produce the same CID, on any machine. Stable identifiers (`NodeId`,
  `EdgeId`) are separate from CIDs: editing a node's text changes its CID
  (new content) but not its `NodeId` (stable logical identity), so a node's
  history can be tracked across mutations.
- **HEAD** — the tip of the current op-log (most recent commit).
- **op-log** — the append-only log of all write operations.
- **ref** — a named pointer to a commit CID (e.g. `refs/heads/main`).

Consequences of content addressing: determinism (two systems ingesting the
same document produce byte-identical graphs), deduplication (identical
content collapses to one CID), auditability (recompute a CID from its
bytes), replayability (reproduce any historical state from the same input).

## Inspecting history

```bash
mnem status                    # op-head CID, head commit, refs, label counts
mnem log                       # walk the op-log backwards, last 20 entries
mnem log -n 50 --oneline       # more entries, compact
mnem log --format json         # machine-readable JSON stream
mnem show                      # decode the current op-head block
mnem show <cid>                # decode any block by CID
mnem cat-file <cid>            # raw DAG-CBOR bytes
mnem cat-file <cid> --json     # decode to DAG-JSON (pipe into jq)
mnem diff HEAD <cid>           # ref deltas + structural node/edge diff
mnem diff <op-a-cid> <op-b-cid>
mnem stats                     # compact one-liner: CIDs, ref count, label names
mnem schema                    # node labels, indexed props, adjacency index (0.1.7+)
```

## Branches and tags

Branches are `refs/heads/<name>` pointers; tags are `refs/tags/<name>`.
mnem does not distinguish branches from tags at the data layer — the
`refs/heads/*` / `refs/tags/*` convention follows git.

```bash
mnem branch create experiment          # branch from current head
mnem branch create hotfix --from <cid> # branch from a specific commit
mnem branch list                       # * marks the branch at the current head
mnem branch delete old-experiment
mnem tag create v1.0                   # at the current head (0.1.7+)
mnem tag create v1.0 --from <cid>      # (0.1.7+)
mnem tag list                          # (0.1.7+)
mnem switch main                       # switch HEAD (alias: mnem checkout main) (0.1.7+)
mnem ref list                          # every ref
mnem ref set refs/heads/main <cid>     # point a ref at a commit CID
mnem ref delete refs/heads/scratch
```

> **0.1.3 branch quirk (verified live):** in 0.1.3, new commits do **not**
> advance any branch ref. `main` stays at the init (seed anchor) commit
> for the whole session, and a branch created with `branch create` stays
> at the head it was created from. After further commits the head is
> detached (no `*` in `branch list`), and `mnem merge` fails with
> "cannot fast-forward: no `refs/heads/*` ref matches the current head".
> Workaround on 0.1.3: pin the head first — `mnem branch create <name>`
> at the current head (verified: the merge then succeeds with
> "fast-forward: advanced refs/heads/<name> -> <cid>"). On 0.1.7 use
> `mnem switch` to move HEAD between branches.

## 3-way merge

Same model as `git merge`, but for knowledge: LCA + structured conflict
detector + executor with `ours` / `theirs` / `manual` strategies. Two agents
working offline reconcile on reconnect — no fact is silently overwritten,
and the full provenance of every node is preserved.

```bash
mnem merge feature                    # merge refs/heads/feature into HEAD
mnem merge feature --strategy=ours    # keep current side on conflict
mnem merge feature --strategy=theirs  # take incoming side on conflict
mnem merge feature --dry-run          # preview outcome, persist nothing
mnem merge --continue                 # finish after editing .mnem/MERGE_CONFLICTS.json
mnem merge --abort                    # cancel; restore HEAD from ORIG_HEAD
```

Conflicts land in `.mnem/MERGE_CONFLICTS.json` for explicit resolution.

## Revert and forgetting

```bash
mnem revert <op-cid>                          # undo one op (new inverse commit) (0.1.7+;
                                              # stub in 0.1.3 — use export + import instead)
mnem revert <op-cid> --message "reason"      # with a reason (0.1.7+)
mnem tombstone <uuid> --reason "superseded"  # soft-delete: hidden from
                                              # retrieval, kept in audit log (0.1.7+)
mnem delete <uuid>                            # hard-delete from current view (0.1.7+)
```

Reverting an already-reverted op is a no-op; chained reverts work (revert
the revert to restore). Root-op reverts (the very first operation) are
supported. `DiffEntry::Changed` (node/edge updates) is fully supported: the
revert restores the previous value of each changed field.

## CAR export / import

Export any snapshot as a standard CAR v1 archive (Content Addressed
aRchive, an IPFS-compatible binary format). Import it on any machine, any
platform. Every block is CID-verified before storage.

```bash
mnem export backup.car
mnem export -                              # write CAR to stdout (pipe over SSH)
mnem export --from refs/heads/main out.car # export from a specific ref
mnem export --from <cid> backup.car        # export from a specific commit CID
mnem import <path>                         # import a CAR archive
mnem import -                              # read CAR from stdin
```

## Push / pull / clone

The wire format is CAR v1. Register a remote first:

```bash
mnem remote add origin http://my-server:9876
mnem remote add origin http://my-server:9876 --token-env MNEM_REMOTE_ORIGIN_TOKEN
mnem remote list
mnem remote show origin
mnem remote remove origin

mnem push                 # push HEAD to origin/main
mnem push origin main     # explicit remote + branch
mnem pull                 # fast-forward origin/main into HEAD
mnem pull origin main
mnem fetch                # fetch without merging (default remote)
mnem fetch upstream

mnem clone <url> [<dir>]          # clone a CAR archive
mnem clone file:///tmp/repo.car ./copy
mnem clone ./repo.car ./copy      # bare path shorthand (must end in .car)
```

Server side: on the target machine, `MNEM_HTTP_ALLOW_NON_LOOPBACK=1 mnem
http --bind 0.0.0.0:9876`. Authentication (bearer token): server sets
`MNEM_HTTP_AUTH_TOKEN=<token>`; client registers the remote with
`--token-env MNEM_REMOTE_ORIGIN_TOKEN` and exports the same token. The
server rejects wrong/missing tokens with HTTP 401; if the env var is unset
at push time, `mnem push` exits 1 with "missing authentication token"
before making any network request. Never hard-code the token value in
commands — use environment variables.

> **Verification scope:** `mnem clone file:///tmp/repo.car ./copy` was
> smoke-tested end to end on the 0.1.3 binary (88 blocks cloned, repo
> readable afterwards). `push`/`pull`/`fetch` against a live HTTP server
> were **not** smoke-tested (single machine, no second server); the
> commands above are documented from the 0.1.7 source and `mnem remote
> --help`. `mnem pull` is fast-forward only — use
> `mnem merge <remote>/<branch>` for 3-way merges.

Single-writer note: `mnem push`/`pull` acquire the write lock on the local
store. If `mnem http` runs against the same store, the push blocks until
the server releases any in-progress write (no corruption, but it waits).
Stop the HTTP server first for a clean push. For concurrent CI pipelines
writing to the same remote, use an external queue or separate repos merged
with `mnem merge`. `mnem pull` is fast-forward only — use
`mnem merge <remote>/<branch>` for 3-way merges.

## Local vs global graph

| Use local `.mnem/` for | Use `mnem global` (`~/.mnemglobal/.mnem/`) for |
|---|---|
| Project-specific facts, decisions, code context | People, preferences, facts that span all projects |
| Per-repo memory that travels with the repo | Knowledge every session and every agent should see |
| Anything you'd commit alongside the code | Cross-session continuity |

`mnem integrate` sets agents up to read local first and fall back to
global automatically. `mnem global` subcommands (`retrieve`, `add`,
`ingest`, `get`/`tombstone`/`delete` (0.1.7+)) operate exclusively on the
global graph. The global graph is created by `mnem integrate` — before
that, global commands fail with "Global graph not initialised" (verified
on 0.1.3).
