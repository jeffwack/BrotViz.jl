# TODO: Ranger-Style TUI for Angled Internal Address Navigation

**Status**: Design finalized 2026-04-05. Pre-implementation.
**Supersedes**: the earlier `REPL.TerminalMenus` + hand-rolled ANSI sketch in
prior revisions of this file.
**Related ROADMAP entry**: `sandbox/ROADMAP.md` §"Ranger-Style TUI".

## Goal

A terminal UI for exploring the combinatorial structure of the Mandelbrot set
by ranger-style navigation through the space of angled internal addresses
(AIAs). The app emphasizes **text / combinatorial** representations — the
preview pane is a text rendering of the Hubbard tree — with high-resolution
raster plots of Julia sets and Mandelbrot patches available on demand but
treated as peripheral, not core.

## Key design decisions

1. **New, separate package** — working name `BrotRover.jl`.
   - NOT an extension of BrotViz. Extensions have been painful to develop and
     maintain in this project.
   - NOT a hard dependency added to BrotViz, because BrotViz is used to build
     the Mandelbrot.jl documentation and docs builds must not pull in
     Tachikoma, terminal backends, async runtimes, etc. Instead, BrotViz is a hard
    dependency of BrotRover, it is the 'camera' on board which can be triggered
    when the user wants to 'take a picture' of the current location.
   - Dependency graph:
     ```
     BrotRover ──► Mandelbrot        (mathematical core)
             ──► Tachikoma         (TUI framework)
             ──► BrotViz  (for "ordering up" images)
     ```

2. **Text-first previews.** The default preview is an ASCII/Unicode rendering
   of the Hubbard tree for the currently-highlighted AIA, drawn into a
   Tachikoma `Block`/`Canvas`. No sixel or kitty graphics are required to use
   the app. Image previews are an "order up" feature: the user presses a key,
   a render job is queued, and on completion a file path is written to the
   log pane (plus an optional sixel blit if the terminal supports it).

3. **Mandelbrot.jl will grow a cancellation/timeout API.** See §6. The TUI
   depends on this: every long-running call must accept an abort token and
   honor it at inner-loop checkpoints. This work is coupled with
   ROADMAP Phase 1 (spider-algorithm robustness) and should land first or in
   lockstep.

4. **Tachikoma's async task system is the concurrency model.** No threads
   outside `spawn_task!`. Results arrive as `TaskEvent`s on the model's
   `TaskQueue`, drained per frame by the Elm loop. Reference implementation
   lives at `~/.julia/packages/Tachikoma/*/demos/TachikomaDemos/src/async_demo.jl`.

5. **No requirement on kitty/sixel terminals.** Text mode is the baseline.
   Any pixel output is progressive enhancement.

## Package layout (`BrotRover.jl`)

```
BrotRover/
  Project.toml          # deps: Mandelbrot, Tachikoma; weakdep: BrotViz
  src/
    BrotRover.jl          # module, exports brotrover()
    model.jl            # NavModel <: Tachikoma.Model; update!/view
    navigator.jl        # AddressNavigator: current, history, bookmarks
    children.jl         # generate_children(aia) over newdenominator/admissible
    compute.jl          # async job dispatch, cancel tokens, timeouts
    cache.jl            # LRU keyed by AngledInternalAddress
    treeascii.jl        # text rendering of HubbardTree (the core preview)
    panels/
      miller.jl         # three Miller columns (parent / current / children)
      previewpanel.jl   # ASCII Hubbard tree + address metadata
      logpanel.jl       # stdout capture + job status
      statusbar.jl
    keymap.jl
    orderup.jl          # optional BrotViz-backed image exports (weakdep-guarded)
    persistence.jl      # bookmarks + cache to ~/.config/brotui/, ~/.cache/brotui/
  test/
    runtests.jl
    tui/                # Tachikoma TestBackend-based render/input tests
```

## Architecture overview

Elm pattern (`Tachikoma.Model` / `update!` / `view`):

```julia
using Tachikoma
using Mandelbrot

@kwdef mutable struct NavModel <: Tachikoma.Model
    nav::AddressNavigator
    cache::NavCache           = NavCache(capacity=256)
    tq::TaskQueue             = TaskQueue()
    jobs::Dict{JobKey, JobHandle} = Dict{JobKey,JobHandle}()
    log::Vector{LogLine}      = LogLine[]
    preview_kind::Symbol      = :hubbard_tree  # default; others: :metadata, :kneading
    quit::Bool                = false
end

Tachikoma.task_queue(m::NavModel) = m.tq
Tachikoma.should_quit(m::NavModel) = m.quit
```

`update!(m, ::KeyEvent)` mutates navigator state and *requests* jobs (never
runs them inline). `update!(m, ::TaskEvent)` files completed results into
`m.cache` and updates `m.jobs`. `view(m, f::Frame)` reads cache + job state
and draws — always cheap, no math.

## Screen layout (Miller columns, text-only)

```
┌ Parent ────────┬ Current ──────────────┬ Children (8) ───────┬ Preview ──────────────┐
│  1             │  1-1/2-2              │ ● [24]  1/13 p=24  •│  Hubbard tree (text): │
│  1-1/2-2       │  1-1/2-2-1/3-6        │   [26]  1/14 p=26  ·│                       │
│ ●1-1/2-2-1/3-6 │  1-1/2-2-1/3-6-2/5-12 │   [28]  1/15 p=26  ⋯│    ●───●               │
│                │                       │   [30]  2/15 p=26  ·│    │   │               │
│                │                       │   …                 │    ●───●───●           │
│                │                       │                     │  period: 24           │
│                │                       │                     │  θ ≈ 0.0101…₂         │
├────────────────┴───────────────────────┴─────────────────────┴───────────────────────┤
│ log: [captured stdout from Mandelbrot.jl]              ⠋ 2 jobs active   cache 47/256│
├──────────────────────────────────────────────────────────────────────────────────────┤
│ j/k move  h/l back/fwd  g goto  / search  b bookmark  v export  x cancel  ? help  q  │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

Columns are laid out with Tachikoma `split_layout(Layout(Horizontal, ...))`.
Children-row glyphs encode cache/job state: `·` unseen, `⋯` running, `•`
cached, `!` failed, `⧖` timed out.

## Key bindings

| Key | Action |
|---|---|
| `j`/`k` or ↓/↑ | move cursor in children column; schedules speculative prefetch |
| `l` / → / Enter | descend into highlighted child; push onto history |
| `h` / ← | pop history (back) |
| `g` | goto modal: accept θ as rational, decimal, or AIA text |
| `/` | search modal: `period:N`, `addr:1-2-4`, fuzzy |
| `b` / `B` | toggle / list bookmarks |
| `p` | cycle preview kind (hubbard tree ↔ metadata ↔ kneading sequence) |
| `v` | order up an image export (Julia set / Mandelbrot patch) — only if BrotViz loaded |
| `x` | cancel currently-highlighted in-flight job |
| `X` | cancel all in-flight jobs |
| `?` | help overlay (Tachikoma built-in) |
| `q` / Ctrl-C | quit (drains and cancels queue first) |

All parsing happens in `keymap.jl`; `update!` dispatches on the parsed action.

## Children generation

Thin wrapper over existing Mandelbrot.jl functions:

```julia
function generate_children(aia::AngledInternalAddress; lookahead::Int=20,
                           abort::AbortToken=AbortToken())
    out = AngledInternalAddress[]
    last = aia.addr[end]
    for next_int in (last+1):(last+lookahead)
        is_aborted(abort) && return out
        k = Mandelbrot.newdenominator(aia, next_int)       # angledoubling.jl:285
        for num in 1:(k-1)
            gcd(num, k) == 1 || continue
            cand_addr   = vcat(aia.addr,   [next_int])
            cand_angles = vcat(aia.angles, [num//k])
            cand = AngledInternalAddress(cand_addr, cand_angles)
            Mandelbrot.admissible(InternalAddress(cand_addr)) || continue  # :141
            push!(out, cand)
        end
    end
    sort!(out, by = x -> x.addr[end])
    out
end
```

Because the user's gut-feel ordering is by period, we sort by the final
address entry (which is the period of the new component). `lookahead` is
initially fixed but should become adaptive once we have real depth data.

## Long-running computations — concrete plan

This is the central engineering concern. Policies, in order of importance:

### (a) AbortToken in Mandelbrot.jl (prerequisite)

Add to Mandelbrot.jl (new file `src/abort.jl`):

```julia
struct AbortToken
    flag::Threads.Atomic{Bool}
    deadline::Float64          # Inf for none
end
AbortToken(; timeout::Real=Inf) =
    AbortToken(Threads.Atomic{Bool}(false),
               timeout == Inf ? Inf : time() + Float64(timeout))

abort!(t::AbortToken) = Threads.atomic_xchg!(t.flag, true)
is_aborted(t::AbortToken) =
    t.flag[] || (isfinite(t.deadline) && time() > t.deadline)

struct Aborted <: Exception end
check_abort(t::AbortToken) = is_aborted(t) && throw(Aborted())
```

Thread an optional `abort::AbortToken = AbortToken()` kwarg through:

- `HubbardTree(K)` (`HubbardTrees.jl:18`) — check inside the `iteratetriod`
  loop at `:82`.
- `spidermap`/spider iteration (`spidermap.jl:97`, `:174`) — check each
  iteration; this also gives us the tolerance-based convergence from
  ROADMAP Phase 1 "for free" (abort on too many iterations).
- `dynamicrays` — check per ray step.
- `admissible(K, m)` (`angledoubling.jl:141`) — only if profiling shows it
  matters at high period.

Callers that don't pass a token get the default no-op token and see no
behavior change. This is the cleanest possible migration.

### (b) Tachikoma async dispatch

Jobs are values, identified by `(kind, addr)`:

```julia
struct JobKey
    kind::Symbol  # :children | :tree | :kneading | :rays | :image_julia | :image_patch
    addr::AngledInternalAddress
end

mutable struct JobHandle
    token::Mandelbrot.AbortToken
    started_at::Float64
    stage::Symbol   # :running | :done | :cancelled | :failed | :timed_out
end

function request!(m::NavModel, key::JobKey; timeout::Real=job_timeout(key.kind))
    haskey(m.cache, key) && return
    haskey(m.jobs,  key) && return
    token = Mandelbrot.AbortToken(timeout=timeout)
    m.jobs[key] = JobHandle(token, time(), :running)
    spawn_task!(m.tq, key.kind) do
        try
            (key, run_job(key, token))
        catch e
            e isa Mandelbrot.Aborted ? (key, :aborted) : rethrow()
        end
    end
end
```

`run_job` dispatches on `key.kind` to the real Mandelbrot.jl routine,
passing `token` through. On completion, `TaskEvent(key.kind, (key, value))`
flows back to `update!`, which files the result into `m.cache` and marks
`m.jobs[key].stage = :done`.

Default timeouts (tunable at runtime via settings overlay):

| Kind | Timeout |
|---|---|
| `:children` | 10 s |
| `:kneading` | 15 s |
| `:tree` | 60 s |
| `:rays` | 120 s |
| `:image_julia` / `:image_patch` | 300 s |

On timeout the row gets the `⧖` glyph and an offer in the status bar to
re-run unbounded.

### (c) Speculative prefetch with cancel-on-navigate-away

When the children-column cursor lands on an address, `update!` calls
`request!(m, JobKey(:tree, addr))` (the preview the user is most likely to
want). When the cursor leaves, if that address is neither current nor in
any visible column, `cancel!` its token. The worker notices at its next
`check_abort` and returns early. Bounded by the fact that only O(1)
addresses are "hot" at any moment.

### (d) LRU cache

`NavCache` wraps a `Dict{JobKey, Any}` with an insertion-order queue, capped
at 256 entries (tunable). Addresses hash cheaply (Mandelbrot.jl already
supports it — see ROADMAP §Sequences notes). Persisted to
`~/.cache/brotui/cache.jls` on exit and reloaded on startup, because deep
addresses can represent minutes of compute that we don't want to throw away
between sessions. Invalidate on Mandelbrot.jl version bump (store version
in file header).

### (e) Progress reporting

Where algorithms have natural iteration counts, the worker pushes
intermediate `TaskEvent(:progress, (key, frac))` into `m.tq.channel`. The
status bar renders a progress bar for the highlighted job. For monolithic
routines we settle for the spinner in the status bar driven by
`m.tq.active[]` (same idiom as `async_demo.jl:144`).

## Preview pane — text Hubbard tree

`treeascii.jl` implements:

```julia
render_hubbard_ascii(tree::HubbardTree; width::Int, height::Int) :: Matrix{Char}
```

Approach: take the combinatorial structure from `HubbardTree`, do a simple
layered layout (critical point at root, BFS by depth), and draw edges with
box-drawing characters (`─│┌┐└┘├┤┬┴┼`). Node glyph encodes the binary
expansion class used in `BrotViz/src/showtree.jl:14-31` — reuse that color
logic via Tachikoma `Style`s.

For small trees the full layout fits; for large trees fall back to an
indented outline view (like `tree(1)`). The preview kind `p` cycles between:

1. Hubbard tree (layered box drawing)
2. Hubbard tree (indented outline)
3. Address metadata: period, denominators, # angles, AIA pretty-print
4. Kneading sequence (raw symbol string with highlighting)

All four are text-only. None require a graphics-capable terminal.

## "Order up" image exports

`orderup.jl` is contains functionality dependent on `BrotViz`

```julia
function export_julia_set(addr, path; resolution, abort)     end
function export_mandelbrot_patch(addr, path; resolution, abort) end
```

Triggered by `v` → modal asks which (Julia / patch), resolution, output
path (default `~/brotui-exports/<addr>.png`). Runs as a normal `JobKey`
through the same async system. On completion the log pane prints the path;
if the terminal advertises sixel/kitty support and the image is small
enough, we *additionally* blit it inline via Tachikoma's `PixelImage`
widget. The fallback is always "image saved to disk".

## Persistence

- `~/.config/brotrover/bookmarks.jls` — `Dict{String, AngledInternalAddress}`
- `~/.config/brotrover/settings.jls` — timeouts, cache size, default preview
- `~/.config/brotrover/session.jls` — last visited address + history (auto-restore on launch)
- `~/.cache/brotrover/cache.jls` — LRU cache contents, versioned

Use `Serialization.serialize` for simplicity; switch to a stable format if
we ever need cross-version compatibility.

## Testing

Tachikoma ships `TestBackend` (see `~/.julia/packages/Tachikoma/*/src/test_backend.jl`)
with `char_at`, `style_at`, `row_text`, `find_text`. Test plan:

- **Unit**: `generate_children` against known AIAs; `NavCache` LRU semantics;
  `AbortToken` honored by each patched Mandelbrot.jl routine.
- **Elm logic**: construct `NavModel`, feed synthetic `KeyEvent`s, assert
  navigator state and emitted `JobKey`s. No TTY needed.
- **Render**: drive `view(m, f)` through `TestBackend`, assert that the
  current address appears in the current column and that a busy address
  shows `⋯`.
- **Async**: inject a fake `run_job` that sleeps + checks a token; assert
  that cancel-on-navigate-away delivers a `:cancelled` stage within N
  frames.

## Phased delivery

Each phase is one-or-two commits and should leave `main` runnable.

**Phase 0 — Mandelbrot.jl abort API (prerequisite).**
Add `AbortToken`, thread it through `HubbardTree`, `spidermap`,
`dynamicrays`. Land tolerance-based convergence for `spidermap` at the same
time (ROADMAP Phase 1 spider fix). Tests that abort actually interrupts.

**Phase 1 — BrotRover skeleton.** New package, `NavModel`, `app(m)` launches,
`q` quits, static children column using synchronous `generate_children`.

**Phase 2 — Miller columns + navigation.** `h/j/k/l`, history stack,
children sorted by period, status bar, log pane (with `on_stdout` capture
from `app()` kwargs).

**Phase 3 — Async job system.** `TaskQueue`, `JobKey`/`JobHandle`, cache,
row glyphs, spinner. All previously-synchronous computes go through
`request!`. Speculative prefetch + cancel-on-navigate-away. Timeouts.

**Phase 4 — Text Hubbard tree preview.** `treeascii.jl`, `previewpanel.jl`,
`p` cycles preview kinds. This is the "core" preview per the design
emphasis on combinatorial representations.

**Phase 5 — Search, goto, bookmarks, session save/restore.**

**Phase 6 — BrotViz image export.** `v` key, export jobs,
optional sixel inline blit.

**Phase 7 — Polish.** Settings overlay for timeouts, themes, persistence
format stability, README + screenshots.

## Integration points

- `Mandelbrot.newdenominator` (`angledoubling.jl:285`)
- `Mandelbrot.admissible` (`angledoubling.jl:141`, `:163`, `:172`)
- `Mandelbrot.bifurcate` (`angledoubling.jl:222`)
- `Mandelbrot.HubbardTree` (`HubbardTrees.jl:18`)
- `Mandelbrot.AngledInternalAddress(theta)` (`angledoubling.jl:183`)
- `BrotViz.juliasetplot`, `BrotViz.mandelbrotsetplot` (extension-only)
- `Tachikoma.app`, `Tachikoma.TaskQueue`, `Tachikoma.spawn_task!`,
  `Tachikoma.TaskEvent`, `Tachikoma.KeyEvent`, widgets listed in
  `~/.julia/packages/Tachikoma/*/src/widgets/`

## Open items (not blocking Phase 0)

- Whether to depend on `Serialization` stdlib directly or use a stabler
  format (JLD2?) for the on-disk cache — defer until Phase 3 is working.
- Adaptive `lookahead` in `generate_children` once we have depth telemetry.
- Whether bookmarks should also store a user-supplied label/note.

## References

- `sandbox/ROADMAP.md` — broader package roadmap
- `~/.julia/packages/Tachikoma/*/README.md` — framework overview
- `~/.julia/packages/Tachikoma/*/src/app.jl` — Elm loop, `task_queue` hook
- `~/.julia/packages/Tachikoma/*/src/async.jl` — `TaskQueue`, `spawn_task!`,
  `CancelToken`
- `~/.julia/packages/Tachikoma/*/demos/TachikomaDemos/src/async_demo.jl` —
  reference implementation of the long-running-work pattern used here
- `~/.julia/packages/Tachikoma/*/src/widgets/treeview.jl` — not used for the
  AIA navigator (Miller columns instead) but useful reference for the
  text Hubbard tree renderer
