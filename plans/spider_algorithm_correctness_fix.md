# Spider Algorithm Correctness Fix: Intersection Detection

## Overview

The spider algorithm implementation (`spider_map` in `Mandelbrot/src/spidermap.jl`) is working correctly for branch selection. The remaining correctness issue is that spider legs can intersect during iteration, violating the injectivity requirement. This plan covers detecting and resolving those intersections.

## Current State

All of the following are done:
- `spider_map` is the single trusted implementation (shoulder-based, using `sector()`)
- `parameter()` calls `spider_map`, converges correctly
- `stats()` fixed
- Dead code removed from `spiderfuncs.jl`
- `KneadingSymbol{N}` parametric type with 2→3 embedding and 4→3 forgetting conversions

## Remaining Work: Intersection Detection and Refinement

### Problem

After `spider_map` computes all new legs, some legs may cross each other. This violates the mathematical requirement that legs are disjoint (except at infinity).

### Algorithm

The check runs in the solver (`parameter()`), after `spider_map` returns:

1. **Check all pairs of legs for intersection** using `test_intersection` on all segment pairs between each leg pair.
2. **If intersections found**: Refine the source legs (add midpoints at the segments involved) and recompute the preimage legs.
3. **Re-check** and repeat up to some budget.

### Functions to implement

```julia
function legs_intersect(legs::Vector{Vector{ComplexF64}})
    # Returns list of (i, j) pairs of intersecting leg indices
end

function refine_leg!(leg::Vector{ComplexF64}, segment_indices)
    # Insert midpoints at the given segments to increase resolution
end
```

### Integration into solver

```
for each iteration:
    S = spider_map(S)
    while legs_intersect(S.legs) and budget > 0:
        refine source legs at intersection sites
        recompute affected legs
        budget -= 1
    check convergence
```

The refinement increases resolution on the source legs so that `path_sqrt` can track the branch cut more accurately, pulling the preimage legs apart.

## Testing

- Known-good parameter values: θ = 1//3, 1//7
- Angles that previously caused convergence failures (likely due to undetected intersections)
- Verify intersection detection fires on problematic cases and refinement resolves them

## References

1. Hubbard, J.H. & Schleicher, D. (1995): "The Spider Algorithm"
2. `Mandelbrot/src/spidermap.jl`
3. `Mandelbrot/src/spiderfuncs.jl` — `test_intersection`, `path_sqrt`
