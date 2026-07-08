# LSP configs — notes

## TL;DR — what `roslyn_ls.lua` does

| Setting | Purpose |
| --- | --- |
| `capabilities.workspace.didChangeWatchedFiles.dynamicRegistration = false` | Decline **client-side** (neovim) file watching. roslyn falls back to its own efficient in-process watcher. |
| `cmd_env.DOTNET_gcServer = "0"` | Use **Workstation GC** instead of Server GC. The big memory win. |
| `cmd_env.DOTNET_GCConserveMemory = "9"` | Tell the GC to aggressively favour low RAM over CPU (0–9 scale). |
| `cmd_env.DOTNET_GCHeapHardLimit = "0x140000000"` | Hard ~5 GB ceiling on the managed heap. Safety backstop. |
| `settings["csharp\|background_analysis"] = "openFiles"` | Only run diagnostics on open files, not the whole solution. |

Everything else (`cmd`, `DOTNET_ROOT*`) is just how mason launches the server
and points it at the right dotnet.

---

## The problem this solves

Symptom: the WSL terminal (sometimes all of WSL) froze hard while working in
the `~/Projects/RPA` solution, and once after leaving the machine idle. Root
cause was **memory exhaustion → WSL2 OOM → VM thrash/freeze**, driven by roslyn.

Why roslyn got so big on this repo specifically:

- **RPA is huge:** ~3.9 GB, **231 `.csproj`**, 86 `bin`/`obj` dirs.
- **WSL2 was capped at 15 GB RAM** (no `.wslconfig` tuning), 32 logical CPUs.
- A **single** roslyn instance was observed climbing **3.6 GB → 8.7 GB** and
  still going. Two of the three drivers below were doing that; the third was a
  CPU/idle-freeze driver.

Live evidence from a freeze (`journalctl -b -1`):

```
kernel: Out of memory: Killed process (roslyn-language) anon-rss:6384128kB ... global_oom
```

After the fixes below, roslyn settles at **~1.5 GB** — roughly a 6–10x drop.

---

## Background — how roslyn actually works (so the settings make sense)

**It loads the whole solution, not just the open file.**
When roslyn attaches it starts from `RPA.sln`, MSBuild-evaluates all 231
projects to learn each project's source files + references, reads those source
files **itself from disk** (not through the editor), and builds an in-memory
**semantic model** — syntax trees plus a fully-resolved symbol/type graph
across every project. That whole-solution graph is what makes cross-project
go-to-definition work, and it's what dominates memory.

- Files you have **open** in neovim: roslyn uses the editor's live buffer
  (via `didOpen`/`didChange`).
- Files that are **closed**: roslyn uses the copy it read from disk.

**File watching** is how roslyn keeps those closed-file copies fresh when they
change on disk behind its back (e.g. `git pull`, `dotnet restore`, codegen).
There are two ways to do it:

- **Client-side:** roslyn asks neovim to watch the filesystem and report
  changes (`workspace/didChangeWatchedFiles`). Good in theory (one shared
  watcher across all your LSP servers), but neovim's recursive watcher over a
  231-project tree is extremely expensive on WSL — this was a freeze source.
- **Server-side:** roslyn runs its own in-process .NET `FileSystemWatcher`.

We set `dynamicRegistration = false`, which makes neovim decline. Verified from
the LSP log, roslyn responds with:

```
DelegatingFileChangeWatcher: We are unable to use LSP file watching;
falling back to our in-process watcher.
```

So **watching is not disabled — it moved to roslyn's cheaper in-process
watcher.** The model still stays up to date after external changes; we just
stopped neovim from doing the heavy recursive watch.

**Garbage collection (the memory driver).**
.NET is managed; roslyn's objects live on a GC heap. Two GC modes:

- **Server GC** (roslyn's shipped default): creates **one heap per logical CPU**
  — 32 here — each hoarding its own memory reserve and slow to return it to the
  OS. Optimised for server throughput, terrible footprint on a 32-core dev box.
  This is why one instance ballooned to ~8.7 GB (mostly reservation, not live
  data).
- **Workstation GC** (`DOTNET_gcServer=0`): single heap, low footprint, plenty
  responsive for an interactive editor. This one change did most of the
  8.7 GB → 1.5 GB drop.

`DOTNET_GCConserveMemory=9` squeezes further (collect more often, compact more,
release sooner) at a small CPU cost. `DOTNET_GCHeapHardLimit=0x140000000`
(= 5 GB) is a hard ceiling so a single instance — or a brief restart overlap —
can never take the whole WSL VM down again.

**Diagnostics scope.**
`dotnet_*_diagnostics_scope = "openFiles"` stops roslyn continuously running
analyzers/compiler diagnostics across all 231 projects. It does **not** reduce
cross-project intelligence (go-to-def, completion, hover, rename still work
solution-wide) — it only limits which files get red/yellow squiggles to the
ones you have open. This is why the live set stopped growing after init.

---

## Related gotcha: `dotnet test` / build leftovers (not fixed in config)

`dotnet build`/`test` spawn MSBuild worker nodes with `nodeReuse=true`, so
~20–30 idle `dotnet` nodes (~5 GB) linger after the command finishes. On the old
8.7 GB roslyn this stacked straight into OOM. With roslyn now capped at ~1.5 GB
there's enough headroom that this is no longer fatal on its own, so node reuse
is left **on** (it keeps builds fast).

To reclaim that memory manually when stepping away:

```sh
dotnet build-server shutdown
```

(If the old-style `/nodemode` workers stick around, kill them directly.)

---

## Trade-offs we accepted

- Slightly slower allocation-heavy phases (initial load, big operations) from
  Workstation GC + `GCConserveMemory=9`. Steady-state editing is unaffected and
  usually feels faster because the box isn't near OOM. If speed matters more
  than RAM now that headroom is large, `GCConserveMemory` can be dialled down or
  dropped — `gcServer=0` alone carries most of the win.
- `didChangeWatchedFiles=false` gives up sharing one watcher across servers for
  C# files, but roslyn is the only server that cares about that tree, so the
  cost is negligible.

## Heads-up for the future

- **`basedpyright`** in `other.lua` uses `diagnosticMode = "workspace"` — the
  Python equivalent of roslyn's full-solution analysis, and it uses neovim's
  client-side watcher. Fine for small Python projects; on a large one it could
  reproduce this exact storm. Consider `openFilesOnly` there if that happens.
- These `DOTNET_*` env vars override roslyn's shipped `runtimeconfig.json`, so
  the fix survives mason updates that overwrite the server package.
