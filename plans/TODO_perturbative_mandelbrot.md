# TODO: Perturbative Mandelbrot Computation System

**Target package**: `BrotViz.jl` (the math is rendering-specific and
lives with the rest of BrotViz's image-generation code).
**Priority**: Medium.
**Status**: Concept described, no implementation exists.
**Filename**: retained for git history — the "Mandelbrot" in the name
refers to the mathematical object, not to Mandelbrot.jl the package.

## Package boundary

The perturbative backend is **BrotViz code**, because perturbation is a
rendering optimization: it trades numerical generality for image-
generation speed in a bounded region, which is exactly BrotViz's job.
Mandelbrot.jl stays the precision kernel and only grows small, focused
API additions to enable BrotViz to consume the spider algorithm's
high-precision output cleanly.

**What lives where**:
- **BrotViz** (this document): `CriticalOrbit`, `PerturbationCalculator`,
  `escape_time`, `escape_time_image`, integration into `mandelbrotsetplot`
  and the headless export API. All the new files live under `BrotViz/src/`.
- **Mandelbrot.jl**: a public `reference_orbit(theta)` accessor, any
  sequence-indexing helpers BrotViz needs to pull orbit data out
  ergonomically, and the `AbortToken` API (tracked separately in
  `ROADMAP.md` §A.2, shared with BrotRover).

A consumer — BrotRover's "order up" feature, the future browser explorer
app (`FUTURE_browser_explorer.md`), or ad-hoc scripts — only ever talks
to BrotViz; it never touches spider internals.

## Problem Statement

Implement perturbative computation of Mandelbrot escape times using
Mandelbrot.jl's spider algorithm output as high-precision reference
orbits, enabling efficient rendering around hyperbolic components at
deep zooms where direct iteration becomes prohibitive.

## Goal

A focused perturbative computation system in BrotViz that:
1. Takes a high-precision reference orbit from Mandelbrot.jl's spider
   algorithm (via a new public accessor — see below).
2. Performs perturbation expansions around a single hyperbolic component
   center, falling back to direct iteration when the perturbation grows
   outside its validity region.
3. Feeds `mandelbrotsetplot` and the headless `export_mandelbrot_patch`
   API so that deep components render fast.
4. Honors a Mandelbrot.jl `AbortToken` so long renders can be cancelled
   mid-row (required by BrotRover and the future browser explorer).

## Mathematical Background

**Standard Iteration**: `z_{n+1} = z_n^2 + c`

**Perturbative Approach**: Given reference orbit `Z_n` for parameter `C`, compute nearby `c = C + δc`:
- `δz_{n+1} ≈ 2Z_n δz_n + δc` (linear recurrence, much faster than full iteration)

**Spider Integration**: Spider algorithm provides high-precision hyperbolic component centers as optimal reference points.

## Implementation Plan

### Phase 1: Mandelbrot.jl enabling API (lands in Mandelbrot.jl, 1 commit)

**Prerequisites**: reliable high-precision spider output. Depends on
`TODO_spider_convergence_fix.md` and `spider_algorithm_correctness_fix.md`
being resolved, or at least stable enough that a documented tolerance
actually holds.

Add a new public accessor in Mandelbrot.jl:

```julia
# Mandelbrot.jl — in spidermap.jl or a new orbits.jl
"""
    reference_orbit(theta::Rational; tolerance=1e-16, max_iter=...) ::
        Sequence{Complex{BigFloat}}

Run the spider algorithm to convergence and return the critical orbit
as a high-precision sequence ready for perturbative rendering.
"""
function reference_orbit(theta::Rational; tolerance=1e-16, ...) end
```

This is the **only** signature BrotViz needs. It should never reach into
spider leg internals.

### Phase 2: Orbit Structure and Sequence Indexing (1-2 commits)

Most of this is BrotViz (the `CriticalOrbit` wrapper) with a small piece
in Mandelbrot.jl if the natural extraction needs new sequence indexing.

**BrotViz side** — `BrotViz/src/perturb.jl`:

```julia
struct CriticalOrbit
    parameter::Complex{BigFloat}                       # spider result
    sequence::Mandelbrot.Sequence{Complex{BigFloat}}   # reference orbit
end

function CriticalOrbit(theta::Rational; tolerance=1e-16)
    orbit = Mandelbrot.reference_orbit(theta; tolerance)
    CriticalOrbit(first(orbit), orbit)   # or whatever the convention is
end
```

**Mandelbrot.jl side** — only if `reference_orbit` can't cleanly return a
`Sequence{Complex{BigFloat}}` without new indexing helpers (e.g. needing
`legs[:, end]`-style extraction across a sequence of collections). If so,
fold that into `TODO_sequence_type_stability.md` — it's a single-package
change, not cross-cutting.

### Phase 3: Perturbation Engine (2 commits, BrotViz)

**Single-point perturbation** around one hyperbolic component, in
`BrotViz/src/perturb.jl`:

```julia
struct PerturbationCalculator
    reference::CriticalOrbit
    tolerance::Float64    # switch to direct iteration when |δz| > tolerance·|Z_n|
    max_iterations::Int
end

function escape_time(calc::PerturbationCalculator, c::Complex;
                     abort::Mandelbrot.AbortToken = Mandelbrot.AbortToken())
    δc = c - calc.reference.parameter
    δz = zero(ComplexF64)
    for n in 1:min(length(calc.reference.sequence), calc.max_iterations)
        Mandelbrot.is_aborted(abort) && return -1
        Zn = calc.reference.sequence[n]
        δz = 2*Zn*δz + δc
        abs2(Zn + δz) > 4 && return n
        abs(δz) > calc.tolerance * abs(Zn) && return escape_time_direct(c, n; abort)
    end
    return calc.max_iterations
end
```

### Phase 4: Image rendering + plot recipe integration (1-2 commits, BrotViz)

Produce rectangular escape-time grids and wire them into the existing
Makie recipes. No InteractiveViz.jl at this stage — see the scope note
below.

```julia
function escape_time_image(calc::PerturbationCalculator,
                           center::Complex, half_width::Real, resolution::Int;
                           abort::Mandelbrot.AbortToken = Mandelbrot.AbortToken())
    xs = range(real(center) - half_width, real(center) + half_width; length=resolution)
    ys = range(imag(center) - half_width, imag(center) + half_width; length=resolution)
    img = Matrix{Int}(undef, resolution, resolution)
    for (i, x) in enumerate(xs)
        Mandelbrot.is_aborted(abort) && return img
        for (j, y) in enumerate(ys)
            img[i, j] = escape_time(calc, complex(x, y); abort)
        end
    end
    img
end
```

Then extend `mandelbrotsetplot` so that, given an AIA or θ, it can
auto-select the perturbative path when the viewport overlaps the
corresponding component, and fall back to the existing direct-iteration
code otherwise. The existing recipe surface should not change; this is
purely a back-end swap.

### Phase 5: Headless export (1 commit, BrotViz)

Route `export_mandelbrot_patch` (see `ROADMAP_brotviz.md` §2) through
`escape_time_image` when applicable. This is the last step needed for
BrotRover to benefit from the perturbative backend.

#### Scope note: InteractiveViz.jl is not part of this TODO

The original (v0.3.0) version of this document had a Phase 4 describing
an InteractiveViz.jl data source for zoom-only exploration. That work
has been moved out of scope: it really belongs to the deferred browser
explorer app, not to BrotViz. See `FUTURE_browser_explorer.md`. The
perturbative backend described here is precisely the prerequisite that
unblocks that app whenever it gets picked up, so nothing is being lost —
it's just being built in the correct package.

## Key Questions to Resolve

1. **`reference_orbit` shape**: does the natural return type fit
   `Sequence{Complex{BigFloat}}` directly, or does Mandelbrot.jl need a
   new indexing helper to extract it from spider legs? Decided at Phase 1.
2. **Foot location**: confirm where in the spider leg structure the
   high-precision reference point lives. Read during Phase 1.
3. **Tolerance selection**: how to pick `PerturbationCalculator.tolerance`
   automatically as a function of zoom depth. Probably profile-driven.
4. **Perturbation validity boundary**: exact criterion for the fall-back
   from perturbative to direct iteration, and whether the fall-back
   should itself be cached per-pixel across refinement passes.

## Success Criteria

- [ ] `Mandelbrot.reference_orbit(theta)` exists and returns trustworthy
      high-precision orbits (depends on spider correctness work).
- [ ] `BrotViz.CriticalOrbit` / `PerturbationCalculator` / `escape_time`
      implemented and unit-tested against direct iteration.
- [ ] Perturbative computation ≥10× faster than direct iteration at
      zoom depths where the perturbation is valid.
- [ ] Accuracy within ±2 iterations of direct computation over the
      validity region.
- [ ] `mandelbrotsetplot` auto-selects the perturbative backend where
      applicable, with no user-visible API change.
- [ ] `AbortToken` honored at the per-row checkpoint in `escape_time_image`.
- [ ] Headless export (`export_mandelbrot_patch`) routes through the
      perturbative backend for deep components.

## Implementation Dependencies

1. **Mandelbrot.jl — spider algorithm fixes**
   (`TODO_spider_convergence_fix.md`, `spider_algorithm_correctness_fix.md`).
2. **Mandelbrot.jl — `reference_orbit` accessor** (new, Phase 1 of this TODO).
3. **Mandelbrot.jl — `AbortToken` API** (tracked in `ROADMAP.md` §A.2,
   shared with BrotRover).
4. **Mandelbrot.jl — sequence indexing enhancements** if Phase 1 needs
   them; may fold into `TODO_sequence_type_stability.md`.
5. **BrotViz — headless export API** (`ROADMAP_brotviz.md` §2).

## References

- `Mandelbrot.jl/src/spidermap.jl` — spider algorithm, source of the
  reference orbit
- `ROADMAP.md` — Mandelbrot.jl enabling work
- `ROADMAP_brotviz.md` — rendering roadmap; §1 summarizes this TODO
- `FUTURE_browser_explorer.md` — deferred consumer that motivates
  making this backend fast enough for interactive use
- `TODO_cli_interface.md` — BrotRover, immediate consumer via the
  headless export API
