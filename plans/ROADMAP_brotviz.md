# BrotViz Roadmap — Rendering and Image Generation

**Scope**: `BrotViz.jl`. All Makie-based plotting, raster rendering of the
Mandelbrot and Julia sets, and the perturbative escape-time backend.

**Companion documents**:
- `ROADMAP.md` — Mandelbrot.jl (mathematical core). Only the *enabling*
  API changes for BrotViz features live there; the features themselves
  live here.
- `TODO_cli_interface.md` — BrotRover.jl (terminal UI, consumes BrotViz's
  image export API as its "camera").
- `TODO_perturbative_mandelbrot.md` — detailed implementation plan for the
  perturbative backend (retained filename for git history; scope is
  BrotViz despite the name).
- `FUTURE_browser_explorer.md` — deferred browser-based always-on
  explorer app (not currently prioritized).

## Current state (2026-04)

BrotViz is a standalone Makie-backed visualizer for Mandelbrot.jl. All
plotting that previously lived inside `Mandelbrot.jl/ext/GLMakieExt/` has
been extracted here as of Mandelbrot.jl v0.4/v0.5. Current surface:

- Recipes (`MakieCore.@recipe`): `hubbardtreeplot`, `mandelbrotsetplot`,
  `juliasetplot`
- User-facing: `treeplot`, `spiderplot`, `showspider`, `plotrays`
- Implementation files under `src/`: `showtree.jl`, `showspider.jl`,
  `showrays.jl`, `mandelbrotset.jl`, `juliaset.jl`,
  `interiorbinarydecomp.jl`, `renderfractal.jl`, `recipes.jl`

Deps: `Mandelbrot`, `Makie`, `Colors`, `ColorSchemes`. Used by the
Mandelbrot.jl docs build — any new hard dependency added here must be
cheap to load and compatible with Documenter.

## Open features

### 1. Perturbative Mandelbrot rendering

**Where the math lives**: here, in BrotViz. Mandelbrot.jl's job is only
to expose the spider algorithm's high-precision output in a form we can
index into cleanly (see §"Mandelbrot.jl enabling work" below). Everything
past that — the `CriticalOrbit` wrapper, the perturbation calculator, the
escape-time rendering — is BrotViz.

**Rationale**: perturbation is rendering-specific. It trades numerical
generality for image-generation speed in a bounded region. Mandelbrot.jl
is the precision kernel; BrotViz is the camera that uses that precision
to take faster pictures.

**Math sketch**:

Given a reference orbit `Z_n` at parameter `C` (produced by spider), a
nearby parameter `c = C + δc` satisfies
```
δz_{n+1} ≈ 2·Z_n·δz_n + δc
```
which is a linear recurrence, far cheaper than re-running the full
quadratic iteration. Fall back to direct iteration once `|δz|` grows past
a tolerance times `|Z_n|`.

**Core types** (BrotViz):

```julia
struct CriticalOrbit
    parameter::Complex{BigFloat}            # spider result
    sequence::Mandelbrot.Sequence{Complex{BigFloat}}  # reference orbit
end

struct PerturbationCalculator
    reference::CriticalOrbit
    tolerance::Float64
    max_iterations::Int
end

function escape_time(calc::PerturbationCalculator, c::Complex)
    δc = c - calc.reference.parameter
    δz = zero(ComplexF64)
    for n in 1:min(length(calc.reference.sequence), calc.max_iterations)
        Zn = calc.reference.sequence[n]
        δz = 2*Zn*δz + δc
        abs2(Zn + δz) > 4 && return n
        abs(δz) > calc.tolerance * abs(Zn) && return escape_time_direct(c, n)
    end
    return calc.max_iterations
end
```

**Tasks**:
- `src/perturb.jl` (new) containing `CriticalOrbit`, `PerturbationCalculator`,
  `escape_time`, and a fall-back `escape_time_direct`.
- `constructor` `CriticalOrbit(theta::Rational)` that calls into
  Mandelbrot.jl's spider API and extracts the reference orbit. This is
  where the Mandelbrot.jl enabling work (below) actually gets consumed.
- `renderfractal.jl` entry point `escape_time_image(calc, region, resolution)`
  producing a `Matrix{Int}` for a rectangular region.
- `mandelbrotsetplot` variant that takes an AIA / θ and auto-selects the
  perturbative backend when the viewport overlaps the component.
- `AbortToken` threading: `escape_time_image` checks `is_aborted` every
  row so BrotRover can cancel long-running renders. Needs `AbortToken`
  to exist in Mandelbrot.jl first (see `ROADMAP.md` Phase A.2).

**Detailed plan**: `TODO_perturbative_mandelbrot.md`.

#### Mandelbrot.jl enabling work (cross-package prerequisites)

These are the *only* things that need to change in Mandelbrot.jl to make
the BrotViz perturbative backend possible. They should land as part of
the Mandelbrot.jl roadmap, not here. Listed here to make the contract
explicit:

1. **Reliable high-precision spider output.** Depends on the spider
   correctness/convergence fixes tracked in `TODO_spider_convergence_fix.md`
   and `spider_algorithm_correctness_fix.md`. Without these, the reference
   orbit precision is not trustworthy.

2. **Clean accessor for the reference orbit.** Today, extracting the
   "foot" of each spider leg requires reaching into internals. The public
   API should expose something like:
   ```julia
   Mandelbrot.reference_orbit(theta::Rational; tolerance=1e-16) ::
       Sequence{Complex{BigFloat}}
   ```
   returning the critical orbit in high precision, ready to feed into a
   `CriticalOrbit` on the BrotViz side. Exact shape TBD, but the point is
   that BrotViz should never touch spider internals.

3. **Sequence custom indexing for orbit extraction** — if the natural
   shape of `reference_orbit()` requires indexing tricks like
   `legs[:, end]` across a sequence of collections, add that to the
   Sequence type. May fold naturally into `TODO_sequence_type_stability.md`.

4. **`AbortToken`** — already tracked in `ROADMAP.md` §A.2 for BrotRover;
   the perturbative renderer is a second consumer with the same checkpointing
   requirements (inside `parameter`/spider iteration).

None of these change Mandelbrot.jl's dependency footprint or add any
rendering knowledge to the math core.

### 2. Headless "order up" image API for BrotRover

BrotRover (see `TODO_cli_interface.md`) depends on BrotViz as its "camera":
the user navigates the combinatorial address space in the terminal, and
when they want a picture of the current location BrotRover calls into
BrotViz to render a PNG to disk.

**What BrotViz needs to expose** (exact signatures TBD, shape is clear):

```julia
export_julia_set(addr::AngledInternalAddress, path::AbstractString;
                 resolution::Int, abort::Mandelbrot.AbortToken) :: String
export_mandelbrot_patch(addr::AngledInternalAddress, path::AbstractString;
                        resolution::Int, abort::Mandelbrot.AbortToken) :: String
```

Requirements:
- Accept an `AbortToken` from Mandelbrot.jl and check it between rows of
  the escape-time grid.
- Use `CairoMakie` (or another headless backend) internally — BrotRover
  runs in a terminal and must not pop a GLMakie window.
- Write to disk, return the final path. No on-screen output.
- Deterministic filenames derived from the AIA, so the same address
  always writes to the same file and a re-request is idempotent.
- Internally, these can (and eventually should) route through the
  perturbative backend from §1 for deep components, with direct iteration
  as fallback for shallow ones.

This is the main new API surface BrotViz needs to grow for BrotRover Phase 6.

### 3. Bonito.jl web interface — reconsidered

The original (v0.3.0) roadmap flagged a Bonito web interface as High
Priority. After the package split and the BrotRover design, this overlaps
heavily with the deferred browser-explorer app (see
`FUTURE_browser_explorer.md`). It is **no longer a separate BrotViz
task** — if a web UI is built, it will be that future app, which would
live in its own package consuming BrotViz the same way BrotRover does.

### 4. Text-mode Hubbard tree rendering — belongs to BrotRover, not here

Noted so it doesn't accidentally land in BrotViz: the ASCII/Unicode
Hubbard-tree renderer used as BrotRover's default preview pane belongs
in `BrotRover/src/treeascii.jl`, not in BrotViz. It uses no Makie. It
*may* reuse the color classification logic at `BrotViz/src/showtree.jl`
(nodes colored by binary-expansion class) by factoring that classifier
into a tiny shared helper — but the renderer itself is BrotRover-only.

## Tests

- Existing: `test/runtests.jl` (currently light — expand as features land).
- Visual regressions: consider `ReferenceTests.jl` for the plot recipes
  once the perturbative backend lands, since escape-time images are
  sensitive to any numerical change in Mandelbrot.jl.
- Headless rendering: ensure `export_julia_set` / `export_mandelbrot_patch`
  work under `CairoMakie` without a display, exercised in CI.
- Perturbative accuracy: for each test component, compare perturbative
  escape times against direct iteration at matched precision; assert
  agreement to within ±2 iterations over the validity region.

## Phased delivery

1. **Headless "order up" export API** (§2, direct iteration only).
   Independent of everything else; unblocks BrotRover Phase 6.
2. **Perturbative backend math** (§1 core types and `escape_time`).
   Depends on Mandelbrot.jl exposing `reference_orbit` and having
   trustworthy spider output — i.e. Mandelbrot.jl roadmap items A.1
   and the new reference-orbit accessor.
3. **Perturbative rendering integration** (§1 `escape_time_image`,
   `mandelbrotsetplot` auto-selection). Depends on 2.
4. **Export API routing through perturbative backend** (§2 revisited).
   Depends on 3.

## References

- `src/renderfractal.jl`, `src/mandelbrotset.jl`, `src/juliaset.jl`
- `TODO_perturbative_mandelbrot.md` — detailed implementation plan
- `TODO_cli_interface.md` — BrotRover, primary consumer of the export API
- `FUTURE_browser_explorer.md` — deferred browser app that would also
  consume this package
- `ROADMAP.md` — Mandelbrot.jl, where the enabling work (AbortToken,
  reference-orbit accessor, spider robustness) is tracked
