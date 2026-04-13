# TODO: Spider Solver Convergence + Performance

**Priority**: High  
**Location**: `Mandelbrot/src/spidermap.jl` — `parameter()` function

## Current State

`parameter()` is working: it calls `spider_map` in a loop, checks `abs(c - c_last) < 1e-15`, and returns the parameter. `grow!` is called inside `spider_map`. `stats()` is fixed and usable.

## Remaining Work

### 1. Tolerance as a keyword argument

Replace hardcoded `1e-15` with a `tol` kwarg. Keep `parameter(theta, max_iter)` convenience method.

### 2. Move `grow!` into the solver

Growth is about numerical stability, not the mathematical map. Moving it out of `spider_map` into `parameter()` makes the map a pure transformation and gives the solver control over growth parameters.

### 3. Verbose mode via `stats()`

Add a `verbose` flag that calls `stats()` each iteration. `stats()` currently prints `c`, point count, and max radius — could also show convergence error.

### 4. `prune!()`

Counterbalances `grow!` and future intersection refinement. Remove points that are far from the origin and closely spaced (redundant resolution), or on nearly-straight sections. Runs in the solver loop.

### 5. Intersection check integration

Per the correctness plan: after each `spider_map` call, check for leg-leg intersections, refine if needed, then proceed to convergence check.

## Target solver shape

```julia
function parameter(S::Spider; max_iter=1000, tol=1e-15, verbose=false)
    c_last = S.legs[2][end] / 2
    for ii in 1:max_iter
        S = spider_map(S)
        # intersection check + refinement (correctness plan)
        grow!(S.legs, 10, 10)
        # prune!(S.legs)  # future
        c = S.legs[2][end] / 2
        if verbose
            stats(S.legs)
        end
        if abs(c - c_last) < tol
            return c
        end
        c_last = c
    end
    @warn "Spider did not converge after $max_iter iterations"
    return S.legs[2][end] / 2
end
```

## Implementation Order

1. Move `grow!` out of `spider_map` into `parameter()`
2. Add `tol` kwarg
3. Add `verbose` flag
4. Implement intersection check (see correctness plan)
5. Implement `prune!()`

## References

- `Mandelbrot/src/spidermap.jl`
- `BrotViz/plans/spider_algorithm_correctness_fix.md`
