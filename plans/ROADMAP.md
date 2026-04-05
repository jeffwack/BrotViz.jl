# Mandelbrot.jl Development Roadmap

**Original version**: 2025-07-23 (Mandelbrot.jl v0.3.0)
**Revised**: 2026-04-05 (Mandelbrot.jl v0.5.0)

**Scope**: `Mandelbrot.jl` only — the mathematical core. Rendering and
terminal-UI plans have been moved into sibling documents:

- `ROADMAP_brotviz.md` — `BrotViz.jl`, all Makie-based rendering, the
  "order up" image export API, and any future InteractiveViz/Bonito work.
- `TODO_cli_interface.md` — `BrotRover.jl`, the Tachikoma-based terminal UI
  for navigating angled internal addresses.
- `FUTURE_browser_explorer.md` — deferred browser-based explorer app that
  combines BrotRover's navigation with an always-on high-res raster view.
  Out of scope for current work; referenced only so the roadmap
  acknowledges it exists as an eventual consumer of this package.

This document covers only work that lives in `Mandelbrot.jl/src/`.

## What changed since the original roadmap

The original roadmap was written against Mandelbrot.jl v0.3.0, when
visualization lived in `ext/GLMakieExt/` inside the package. Since then:

- **All rendering has been extracted to `BrotViz.jl`** (`916b9cc` "removed
  all plotting functionality and docs"). `treeplot`, `spiderplot`,
  `showspider`, `plotrays`, and all Makie recipes now live in BrotViz.
- **Dependencies trimmed**: `Mandelbrot/Project.toml` deps are now only
  `IterTools` and `Primes`. No `GLMakie`, `Colors`, or `ColorSchemes`.
  The "move visualization to main package?" question is resolved in the
  opposite direction: viz is now its own package.
- **`ext/` directory is gone.** There is no extension in Mandelbrot.jl.
- **Version bumped to v0.5.0** across two releases.
- **Docs**: Mandelbrot.jl docs now build using BrotViz for visualization
  examples (`f8e2ac2`), which is why BrotViz cannot take on heavy deps
  like Tachikoma or Bonito without compromising doc builds — the
  motivation for factoring BrotRover into its own package.

Things the original roadmap identified that **are still open**:

- Spider algorithm correctness + convergence (`src/spidermap.jl:97`
  periodic-case TODO is still present verbatim; fixed-iteration count at
  `:174` still in place). Tracked in `TODO_spider_convergence_fix.md` and
  `spider_algorithm_correctness_fix.md`.
- `src/Graphs.jl:1` still starts with the stub comment
  `#implement adj and you should be able to use all these functions?`.
- Test suite is still `test/runtests.jl` containing a single `@test`.
  Tracked in `TODO_hubbard_tree_tests.md`.
- Sequence framework extraction to its own package is still open
  (`TODO_sequence_package_extraction.md`).
- Sequence type-stability audit still open
  (`TODO_sequence_type_stability.md`).
- `sandbox/apps/Phonebook.jl` still exists, still slated for deletion
  once BrotRover reaches feature parity.

## Current package structure

**`Project.toml`** (v0.5.0):
- Deps: `IterTools`, `Primes`
- Julia compat: 1.11–1.12

**`src/Mandelbrot.jl`** include order:
```
Sequences.jl          — core sequence type with automatic period reduction
angledoubling.jl      — BinaryExpansion, KneadingSequence, InternalAddress,
                        AngledInternalAddress, admissibility, bifurcation
Graphs.jl             — custom abstract Graph + adjacency operations
HubbardTrees.jl       — triod-based tree construction
orienttrees.jl        — OrientedHubbardTree
dynamicrays.jl        — external dynamic rays
embedtrees.jl         — embedding computations
spiderfuncs.jl        — spider primitives
spidermap.jl          — spider algorithm (the `parameter(theta)` entry point)
```

**Exports**: `BinaryExpansion`, `Digit`, `KneadingSequence`,
`InternalAddress`, `HubbardTree`, `AngledInternalAddress`,
`OrientedHubbardTree`, `HyperbolicComponent`, `parameter`, `orbit`.

## Open work items (Mandelbrot.jl only)

Grouped by broad theme. Each item links to a companion TODO where one exists.

### A. Correctness / robustness

1. **Spider algorithm periodic case** — `TODO_spider_convergence_fix.md`
   and `spider_algorithm_correctness_fix.md`.
   - The TODO comment at `src/spidermap.jl:97` is still the clearest
     statement of the problem: the periodic branch depends on sentinel
     values that kneading sequences no longer carry.
   - The fixed iteration count at `:174` should become tolerance-based
     convergence with a max-iterations cap.
   - Leg intersections need subdivision detection.

2. **`AbortToken` / timeout API** — *new, blocks BrotRover Phase 0.*
   - Add `src/abort.jl` introducing `AbortToken(; timeout=Inf)`,
     `is_aborted`, `check_abort`, and an `Aborted <: Exception`.
   - Thread an optional `abort::AbortToken = AbortToken()` kwarg through:
     - `HubbardTree(K)` (inside the `iteratetriod` loop at
       `src/HubbardTrees.jl:82`)
     - spider iteration in `src/spidermap.jl` (each iteration checkpoint)
     - `dynamicrays` (per ray step)
   - Callers that pass no token see no behavior change (default token is
     a no-op with `Inf` deadline).
   - Coordinate with item A.1 — once spider iteration has a real
     convergence-tolerance loop, abort checks slot in naturally.
   - **Downstream consumer**: BrotRover depends on this to cancel
     long-running jobs when the user navigates away. See
     `TODO_cli_interface.md` §6.

### B. Testing

1. **Hubbard tree test suite** — `TODO_hubbard_tree_tests.md`.
   Scope: basic construction, mathematical properties (connectedness,
   acyclicity, critical-point presence), triod algorithm components,
   edge cases, reference cases from the literature. All tests live in
   `Mandelbrot.jl/test/`. Visual-validation plots, if any, belong in
   BrotViz's test suite — see `ROADMAP_brotviz.md`.

2. **Spider algorithm tests** — currently none. Deferred until A.1 lands
   so there is a deterministic convergence criterion to assert against.

3. **`AbortToken` tests** — land with A.2. Verify that each algorithm
   actually honors the token at its claimed checkpoints and returns
   promptly after abort.

### C. Architecture / code organization

1. **Sequences package extraction** — `TODO_sequence_package_extraction.md`.
   Move `src/Sequences.jl` (with automatic period reduction and hash
   support) into a standalone package. Mandelbrot.jl then depends on it.
   Not urgent — no external consumers yet — but cleanly self-contained.

2. **Sequence type stability** — `TODO_sequence_type_stability.md`.
   Audit `Sequence{T}` with `@code_warntype` / `JET.jl`. Fix any
   instabilities surfaced. Lighter lift than extraction.

3. **`Graphs.jl` cleanup.** The file opens with
   `#implement adj and you should be able to use all these functions?`
   — a genuine architectural question that's been deferred. Either:
   (a) document the `Graph` contract and delete the comment, or
   (b) admit the contract isn't used and simplify. Decide before adding
   any more graph operations. The AbstractTrees.jl migration proposed in
   the original roadmap has been **declined** ("I think it is fun to
   have re-implemented graphs").

4. **Bibliography via DocumenterCitations.jl** — mentioned in the
   original roadmap. Desirable for the Mandelbrot.jl docs (built with
   BrotViz). Low-effort; do when the next round of doc polishing happens.

### D. Enabling work for BrotViz rendering features

Mandelbrot.jl no longer contains any rendering or image-generation code,
and by the current package boundary it never will. The perturbative
escape-time backend that the original roadmap contemplated lives in
BrotViz (see `ROADMAP_brotviz.md` §1 and `TODO_perturbative_mandelbrot.md`).
Mandelbrot.jl's only role is to grow a small, focused public API that
lets BrotViz consume the spider algorithm's high-precision output
cleanly, without reaching into internals.

1. **`reference_orbit(theta::Rational)` accessor** — new public function.
   Runs the spider algorithm to convergence and returns the critical
   orbit as a `Sequence{Complex{BigFloat}}` ready for BrotViz to wrap in
   its own `CriticalOrbit` type. Must not expose spider leg layout or
   other internals. See `TODO_perturbative_mandelbrot.md` Phase 1 for
   the exact shape.
   - **Prerequisite**: A.1 (spider correctness/convergence). Without a
     trustworthy tolerance on the spider output, the reference orbit
     precision is not meaningful.

2. **Sequence indexing helpers, if needed.** If the natural extraction
   of the reference orbit from spider legs requires new indexing
   operations on `Sequence{T}` (e.g. across a sequence of collections),
   add them here rather than leaving BrotViz to work around them.
   Fold into `TODO_sequence_type_stability.md` if it stays small; break
   out its own TODO if it grows.

Any further mathematical features should go through the same filter:
if they exist to make rendering faster or prettier, they belong in
BrotViz. If they are new mathematics about the Mandelbrot set itself
(new invariants, new combinatorial structure, new tree operations),
they belong here.

## Strategic priorities

Ordered by dependency rather than by calendar:

1. **A.1 — Spider correctness + convergence.** Unblocks reliable use of
   `parameter(theta)`, unblocks A.2's checkpoint story, unblocks D.1's
   reference-orbit precision.
2. **A.2 — AbortToken API.** Lightweight once A.1 has a real iteration
   loop. Unblocks BrotRover Phase 0.
3. **B.1 — Hubbard tree tests.** Independent of A.*, can be done in
   parallel.
4. **C.2 — Sequence type stability.** Small, independent.
5. **D.1 — `reference_orbit` accessor.** Depends on A.1. Unblocks the
   BrotViz perturbative backend (`TODO_perturbative_mandelbrot.md`).
6. **C.1 — Sequences extraction.** Independent but disruptive to imports;
   schedule when other work is quiet.
7. **C.3, C.4 — Graphs cleanup, bibliography.** Housekeeping.

## API design principles

- **Backward compatibility**: existing public exports should keep their
  shapes. `AbortToken` is purely additive (optional kwarg with a no-op
  default).
- **Mathematical precision**: exact rational arithmetic in address
  calculations; `BigFloat` where spider precision matters; no unnecessary
  promotion.
- **No rendering dependencies**: Mandelbrot.jl must not take on any
  plotting, UI, or serialization dependencies. It is consumed by BrotViz
  (for plots) and BrotRover (for the TUI); those packages handle
  presentation.
- **Thread-safe where feasible**: algorithms that may be invoked from
  Tachikoma's `spawn_task!` in BrotRover should not mutate process-global
  state. Most current code already satisfies this — spot-check during A.2.

## References

- `src/Mandelbrot.jl` — module file and include order
- `src/spidermap.jl:97` — the persistent periodic-case TODO
- `src/Graphs.jl:1` — the persistent stub comment
- [Bruin, Kaffl, Schleicher](https://eudml.org/doc/283172) — Hubbard tree
  construction paper, already cited in docstrings (`7f9034a`)

---

*Original analysis by Claude Code and Jeff Wack, 2025-07-24. Rewritten
2026-04-05 after the BrotViz extraction to reflect Mandelbrot.jl v0.5.0
and the three-package split (Mandelbrot / BrotViz / BrotRover).*
