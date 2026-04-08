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

## Next release (v0.6.0) — public API for BrotViz and BrotRover

The v0.5.0 → v0.6.0 bump should be scoped around one goal: **give
BrotViz and BrotRover a stable public surface to build against, so that
neither downstream package has to reach into Mandelbrot.jl internals.**

Nothing in this section is a new piece of mathematics. It is almost
entirely renaming, exporting, docstringing, and tightening the
signatures of code that already exists, plus the two genuinely new
additions (`AbortToken`, `reference_orbit`) that both downstream
packages already assume in their own plans.

### Design principle: *the graph is the contract*

The Mandelbrot.jl README contains an "Algorithm Flow" mermaid diagram.
That graph **is** the public API of this package:

- **Each node in the graph is a named public type.** If the node has no
  corresponding exported type today, that is a gap to close in v0.6.0.
- **Each arrow in the graph is a named public function** that takes the
  source node type(s) and returns the target node type. Arrow direction
  is exactly function-application direction.
- **Nothing off the graph is public.** Spider legs, triods, graph
  adjacency primitives, `rho` sequences, majority-vote helpers, itinerary
  computations — all internal, free to refactor at will, not exported,
  not docstringed as user-facing.

This principle has three immediate consequences:

1. The README becomes usable as API documentation. A user who can read
   the flowchart can find the function they want.
2. Refactors inside algorithms (spider convergence fix, graph cleanup,
   sequence type stability) become free — they touch nothing on the
   graph and so break no contracts.
3. Additions to the graph are a visible, deliberate act. A new node or
   arrow in the README is a new public commitment.

### Gap analysis — graph nodes vs. current exports

| Graph node | Type in code | Exported? | v0.6.0 action |
|---|---|---|---|
| Rational angle (RA) | `Rational{Int}` (Julia built-in) | n/a | document the convention (θ ∈ [0,1)); no new type |
| Binary expansion of RA | `BinaryExpansion` | ✓ | keep; docstring |
| Angled internal address (AIA) | `AngledInternalAddress` | ✓ | keep; expose `bifurcate`, `nextaddress`, `newdenominator` |
| Internal address (IA) | `InternalAddress` | ✓ | keep; expose `denominators`, `admissible` |
| Kneading sequence (KS) | `KneadingSequence` | ✓ | keep |
| Combinatorial Hubbard tree (CHT) | `HubbardTree` | ✓ | keep; export `criticalpoint` |
| Oriented Hubbard tree (OHT) | `OrientedHubbardTree` | ✓ | keep; export `criticalanglesof`, `allanglesof` |
| Orbit portrait (OP) | — | ✗ | **new public type** `OrbitPortrait` wrapping whatever `allanglesof`/`characteristicset` already compute |
| Companion angles / minor leaf (CA) | returned as `Set`/tuple | ✗ | **new public type** `CompanionAngles` (or a named pair `MinorLeaf`) with documented fields |
| Critical orbit (CO) | lives inside `Spider.legs` | ✗ | **new public accessor** `reference_orbit(theta)` returning a `Sequence{Complex{BigFloat}}`; do **not** expose `Spider` itself |
| Center parameter (CP) | return value of `parameter()` | ✓ (function) | keep as bare `Complex{BigFloat}`; tighten signature (see below) |
| External rays (ER / ERout) | `ExternalRays` struct in `dynamicrays.jl:1` | ✗ | **export** `ExternalRays`, `dynamicrays`, `landingpoint`; document field layout |
| Branch parameters (BP) | — | ✗ | leave out of v0.6.0. Mark as a known gap in the graph and note "not yet implemented" in README; revisit when `EmbeddedHubbardTree` stabilizes |
| Embedded vertex Hubbard tree (EVHT) | part of `HyperbolicComponent` | partial | decide whether EVHT is a distinct public type or an internal intermediate; today it isn't split and I recommend keeping it internal for v0.6.0 |
| Embedded Hubbard tree (EHT) | `HyperbolicComponent` | ✓ | keep; consider renaming to `EmbeddedHubbardTree` for graph-consistency, with `HyperbolicComponent` kept as a deprecated alias for one release |

**Summary**: of 14 graph nodes, 7 already have clean exported types, 3
need promotion from internal to public (`OrbitPortrait`, `CompanionAngles`,
`ExternalRays`), 1 needs a new accessor function (`reference_orbit` for
CO), 1 needs a rename-with-alias (`HyperbolicComponent` →
`EmbeddedHubbardTree`), 1 is deferred (`BranchParameters`), and 1 is
built-in (`Rational`).

### Features to land for v0.6.0

Grouped by the kind of change. Item-level detail; ordered within each
group roughly by dependency.

#### F1. Type promotions / renames (no new math)

- **F1.1** — Export `ExternalRays` from `dynamicrays.jl`. Docstring its
  fields (`orb`, `rays`, `c` today) and lock their names.
- **F1.2** — Promote `OrbitPortrait` to a first-class public type.
  Whatever shape `characteristicset` / `characteristicorbits`
  (`orienttrees.jl:71, 96`) currently return should be wrapped in a
  named struct with a `show` method that matches the graph node label.
- **F1.3** — Promote `CompanionAngles` (or `MinorLeaf`) to a first-class
  public type. This is what `allanglesof` and `criticalanglesof`
  (`embedtrees.jl:302, 355`) currently return as ad-hoc collections.
- **F1.4** — Rename `HyperbolicComponent` → `EmbeddedHubbardTree` so
  the graph node label and the Julia type name agree. Keep
  `const HyperbolicComponent = EmbeddedHubbardTree` for one release
  with a deprecation docstring.
- **F1.5** — Export `criticalpoint` (`HubbardTrees.jl:5`) — the obvious
  accessor for both CHT and OHT. Currently in the package but
  unexported.

#### F2. Function exports (BrotRover's navigation primitives)

BrotRover's ranger-style UI walks the AIA tree using functions that all
exist today but are currently unexported. `TODO_cli_interface.md` §
"Children generation" relies on all of these; today it would have to
use `Mandelbrot.newdenominator` etc., which is a brittle contract.

- **F2.1** — Export `bifurcate(::AngledInternalAddress)`
  (`angledoubling.jl:222`).
- **F2.2** — Export `nextaddress(::AngledInternalAddress)`
  (`angledoubling.jl:230`).
- **F2.3** — Export `newdenominator(::AngledInternalAddress, ::Int)`
  (`angledoubling.jl:285`).
- **F2.4** — Export the three `admissible` methods
  (`angledoubling.jl:141, 163, 172`).
- **F2.5** — Export `denominators(::InternalAddress)`
  (`angledoubling.jl:263`).
- **F2.6** — Export `period(theta)`, `num_choices`, `num_angles`,
  `num_partners` (`angledoubling.jl:317–331`). These are the metadata
  BrotRover displays on each row of its children column.
- **F2.7** — Export `allanglesof` and `criticalanglesof`
  (`embedtrees.jl:302, 349, 355, 395, 401`) once F1.3 gives them a
  named return type.

All of these are additive — no existing code breaks.

#### F3. `AbortToken` API (cross-cutting, additive)

Tracked separately as §A.2 above. Restated here for release scope:

- **F3.1** — New file `src/abort.jl` introducing `AbortToken(; timeout=Inf)`,
  `is_aborted`, `abort!`, `check_abort`, and `struct Aborted <: Exception`.
  Export all five.
- **F3.2** — Thread optional `abort::AbortToken = AbortToken()` kwarg
  through the three long-running entry points on the graph:
  `HubbardTree(::KneadingSequence)` (inside `iteratetriod`),
  `parameter(::Rational)` (inside the spider iteration loop),
  `dynamicrays` and `landingpoint` (per ray step).
  Default is a no-op token; no existing caller breaks.
- **F3.3** — Tests asserting each entry point actually honors the
  token within one checkpoint after `abort!` is called.

#### F4. `reference_orbit` accessor (new, needed by BrotViz)

- **F4.1** — New public function
  ```julia
  reference_orbit(theta::Rational;
                  tolerance::Real=1e-16,
                  max_iter::Int=...,
                  abort::AbortToken=AbortToken()) ::
      Sequence{Complex{BigFloat}}
  ```
  Runs the spider algorithm to convergence and returns the critical
  orbit in a form that BrotViz can wrap in its own `CriticalOrbit`
  type. Must not expose `Spider` or its leg layout.
- **F4.2** — `reference_orbit(::AngledInternalAddress)` convenience
  overload that picks the representative θ.
- **F4.3** — This is a new *arrow* on the README graph: an edge from
  RA (or AIA) directly into CO, labeled `reference_orbit`. Currently
  the graph shows RA → CO going via spider internals; the v0.6.0 graph
  should show the public arrow.

#### F5. `parameter()` signature stabilization

- **F5.1** — Change `parameter(theta::Rational, max_iter::Int)` at
  `spidermap.jl:203` to a kwarg form:
  ```julia
  parameter(theta::Rational;
            tolerance::Real=1e-16,
            max_iter::Int=...,
            abort::AbortToken=AbortToken()) :: Complex{BigFloat}
  ```
  Keep a deprecated method `parameter(theta, max_iter)` for one release
  that forwards to the kwarg form.
- **F5.2** — Add `parameter(::AngledInternalAddress; kwargs...)`
  overload. BrotRover and BrotViz both work in AIA-space, not θ-space,
  and today have to go AIA → θ → parameter manually.
- **F5.3** — Depends on **A.1** (spider convergence fix). Without a
  tolerance-based loop there is nothing meaningful for the `tolerance`
  kwarg to mean. If A.1 slips, F5.1 should slip with it — do not ship
  a `tolerance` kwarg that is quietly ignored.

#### F6. Documentation (the graph becomes the index)

- **F6.1** — Docstring every public type and function listed above.
  Docstrings should use the graph node label in their first line so
  that the README diagram doubles as a table of contents.
- **F6.2** — Update the README "Algorithm Flow" diagram to include the
  new `reference_orbit` arrow (F4.3). Consider adding a second mermaid
  diagram that renders node labels as their Julia type names, to make
  the graph-is-the-contract principle legible at a glance.
- **F6.3** — Add a section to the docs titled "Public API" that simply
  walks the graph in dependency order. This is where
  `DocumenterCitations.jl` (item C.4) can finally pay off.
- **F6.4** — Explicitly mark internals: `Graphs.jl`, `Spider`,
  `iteratetriod`, `majorityvote`, `thetaitinerary`, `rho`, `rhosequence`,
  `addsequence`, `extend`, `firstaddress`, `standardspider`,
  `standardlegs`, `grow!`, `prune!`, `stats`, `mapspider!`,
  `spideriterates`, `goesto`, `standardrays`, `extend!`, `longpath`,
  `edgepath`, `refinedtree`, `refinetree!`, `standardedges`,
  `angleclusters`, `labelonezero`, `anglesofbranch`, `angle_echo`,
  `valid_binary`, `findone`, `isbetween`, `nodepath`, `agrees`,
  `forwardimages`, `preimages`, `forwardorbit`, `grandorbit`,
  `dynamiccomponents`, `ischaracteristic`, `characteristicset`,
  `characteristicorbits`, `orientnode`, `orientcharacteristic`,
  `orientpreimages`, `addboundary`, `numembeddings`. None of these are
  on the graph; none of these should get user-facing docstrings.
  They stay internal and refactorable.

### What is explicitly **out of scope** for v0.6.0

- **Perturbative rendering backend.** Lives in BrotViz
  (`TODO_perturbative_mandelbrot.md`). Mandelbrot.jl ships only F4
  (`reference_orbit`) as enablement.
- **Branch parameters (BP).** Keep the node as a known README gap;
  revisit when there is a concrete consumer.
- **Sequences package extraction (C.1).** Disruptive to imports;
  schedule separately after v0.6.0.
- **AbstractTrees.jl migration.** Declined.
- **Graphs.jl contract decision (C.3).** Internal, can move independently.
- **Tolerance parameter on algorithms that don't yet have convergence
  loops.** Ship A.1 first or ship F5.1 without tolerance — do not ship
  an ignored kwarg.

### Release dependency order

A minimal path from HEAD to v0.6.0-ready:

1. **A.1** — spider correctness + convergence loop. Blocks F4, F5.
2. **F3** — `AbortToken` API. Independent; lands alongside A.1 since
   the convergence loop is the natural place to add the checkpoint.
3. **F1** — type promotions / renames. Independent; can land in parallel
   with A.1 / F3.
4. **F2** — function exports. Independent; can land in parallel.
5. **F5** — `parameter` signature. Depends on A.1 + F3.
6. **F4** — `reference_orbit`. Depends on A.1 + F3.
7. **B.1** — Hubbard tree tests. Land before F1.4's rename so the
   rename has a safety net.
8. **F6** — docs pass. Last step; catches everything.

A pragmatic minimum viable release is F1 + F2 + F3 + B.1 + F6, shipped
as v0.6.0, followed by v0.6.1 adding F4 + F5 once A.1 lands. That way
BrotRover is unblocked immediately on navigation primitives and
`AbortToken`, while BrotViz's perturbative backend waits one more
point release for the spider fixes it actually needs anyway.

### Release checklist

- [ ] Every graph node in the README has an exported Julia type, or is
      explicitly marked "not yet implemented" in the README.
- [ ] Every arrow in the README has an exported function whose signature
      matches the node types.
- [ ] `AbortToken` exists and is honored by `HubbardTree`, `parameter`,
      and `dynamicrays` / `landingpoint`, verified by tests.
- [ ] `reference_orbit(theta)` exists, is documented, and has a test
      comparing its output against direct spider iteration.
- [ ] `parameter(theta; tolerance, max_iter, abort)` exists;
      `parameter(theta, max_iter)` deprecated with a warning.
- [ ] `HyperbolicComponent` deprecated in favor of `EmbeddedHubbardTree`,
      with alias.
- [ ] All items from F6.4's internals list have no user-facing docstrings
      and are absent from the `export` statement in `Mandelbrot.jl`.
- [ ] CHANGELOG entry lists every new export.
- [ ] BrotRover's children-generation code compiles against the new
      exports with no `Mandelbrot.foo` qualified accesses.
- [ ] `using Mandelbrot` followed by `?AngledInternalAddress`,
      `?bifurcate`, `?reference_orbit`, etc. all return docstrings that
      reference the graph node by its README label.

**Backward compatibility**: existing public exports should keep their
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
