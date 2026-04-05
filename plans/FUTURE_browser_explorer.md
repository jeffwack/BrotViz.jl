# FUTURE: Browser-Based Mandelbrot Explorer

**Status**: Out of scope. Not currently prioritized. This document captures
the shape of the idea so that when it does get picked up, the constraints
and architectural choices from the BrotRover design are already in mind.

**Related**:
- `TODO_cli_interface.md` — BrotRover.jl, the terminal sibling this app
  would eventually absorb the features of.
- `ROADMAP_brotviz.md` — BrotViz rendering; the browser app would consume
  it the same way BrotRover does.

## Concept

A browser-based application that combines everything BrotRover does
(ranger-style navigation through the combinatorial space of angled
internal addresses, Hubbard tree previews, bookmarks, search) with
something BrotRover intentionally doesn't do: an **always-on, high-
resolution raster view** of the Mandelbrot set that smoothly tracks the
user's navigation.

The centerpiece is the rendered pane, not the combinatorial panels. As
the user navigates to a new AIA, the raster view **flies to** the
corresponding hyperbolic component with interpolated pan+zoom, rather
than cutting or requiring an explicit "take a picture" action. The user
can interrupt the camera at any time with mouse pan/scroll-zoom to free-
explore, then snap back to tracking.

## Contrast with BrotRover

| | BrotRover | Browser Explorer |
|---|---|---|
| Frontend | Terminal (Tachikoma) | Browser (likely Bonito or raw WebGL/JS) |
| Raster view | Ordered up on demand, written to disk | Always visible, continuously rendered |
| Camera | User explicitly requests pictures | Auto-tracks navigation with animated transitions |
| Mouse | Not used | Primary free-navigation input, overrides auto-camera |
| Deployment | `julia> brotrover()` locally | Local web server, possibly hosted |
| Audience | Terminal users, combinatorial emphasis | Anyone, raster emphasis |

BrotRover is the correct first target because it is dramatically smaller
in scope (no rendering pipeline, no WebGL, no camera interpolation, no
mouse handling for a 2D continuous space) and because it lets us debug
the navigation model against a minimal UI before committing to a browser
stack.

## Architectural sketch (for when this is picked up)

This would almost certainly be its **own package** — call it
`BrotExplorer.jl` or similar — following the same separation-of-concerns
pattern as BrotRover:

```
BrotExplorer ──► Mandelbrot   (math core, AIA navigation primitives)
            ──► BrotViz       (rendering backend, perturbative escape times)
            ──► BrotRover     (navigation model? or re-implemented?)
            ──► Bonito        (or InteractiveViz.jl, or a raw JS stack — TBD)
```

The navigation model (history stack, bookmarks, address generation,
cache) should be **shared with BrotRover**, not re-implemented. Two
options:

1. Factor BrotRover's `navigator.jl` + `children.jl` + `cache.jl` into
   a small headless library (`BrotNav.jl`?) that both BrotRover and
   BrotExplorer depend on. Cleanest long-term.
2. Have BrotExplorer depend directly on BrotRover and re-use its
   non-TUI parts. Simpler initially, awkward if BrotRover ever grows
   terminal-specific dependencies into the navigation core.

Option 1 should be adopted once there are two consumers — not before.

## Key technical challenges

1. **Rendering pipeline.** The escape-time rendering must be fast enough
   to track smooth camera motion. This essentially requires the
   perturbative backend (`ROADMAP_brotviz.md` §1) to be in place, plus
   some form of GPU path or incremental-refinement strategy. At minimum,
   a coarse-to-fine sampling strategy similar to InteractiveViz.jl.

2. **Camera interpolation.** Given the current raster view's `(center,
   zoom)` and the target component's `(center', zoom')`, compute a
   smooth trajectory. Logarithmic interpolation in zoom is a must
   (linear interpolation looks wrong over many orders of magnitude).
   User interruption must be instant and must not "snap back" unless
   the user asks for it.

3. **Numerical precision at deep zoom.** Deep components require
   `BigFloat` precision in the reference orbit but `Float64` in the
   perturbation deltas. This is exactly what the perturbative backend
   is designed for; the browser app is its main customer.

4. **JS/Julia boundary.** Bonito is the obvious starting point since
   it's pure Julia and composes with Makie, but historically it has had
   performance issues with tight interactive loops on complex scenes.
   A hybrid where the Julia side serves escape-time tiles over WebSocket
   and the browser side does pan/zoom compositing in JS may be necessary.
   Research before committing.

5. **Address → camera target mapping.** Each AIA corresponds to a
   hyperbolic component with a known center (via the spider algorithm)
   and a known approximate size (via the internal address depth). The
   mapping `AIA → (center, zoom)` is the glue between the navigation
   model and the camera. Belongs in the shared `BrotNav.jl` or
   equivalent.

## Prerequisites before any work starts

These must exist before the browser app is viable:

- [ ] BrotRover shipped and usable. Proves the navigation model.
- [ ] BrotViz perturbative backend shipped
      (`ROADMAP_brotviz.md` §1 all phases).
- [ ] Mandelbrot.jl `reference_orbit` accessor and `AbortToken` API
      (`ROADMAP.md` §A.2 and the perturbative enabling work).
- [ ] Decision: shared-navigation package `BrotNav.jl` or direct
      dependency on BrotRover's internals.
- [ ] Decision: Bonito vs. hybrid Julia+JS vs. InteractiveViz.jl.

Until all of these exist, any work on the browser app is premature.

## Scope decisions deferred to pick-up time

- Single-user local app vs. hostable multi-user web service.
- Persistence model (shared with BrotRover's `~/.config/brotrover/`?
  separate? browser-localstorage?).
- Export formats (PNG, SVG, shareable URLs encoding `(AIA, camera state)`).
- Keyboard parity with BrotRover for terminal users who also use the
  browser app.
- Mobile / touch input. Probably say no, but decide explicitly.

## Why this is currently deferred

- BrotRover is the smaller, lower-risk way to validate the navigation
  model first.
- The perturbative backend this app depends on does not yet exist.
- The browser stack choice (Bonito vs. alternatives) needs more data
  from how BrotRover feels in daily use.
- Single maintainer; parallel UI projects are expensive.

Revisit after BrotRover Phase 7 ships.
