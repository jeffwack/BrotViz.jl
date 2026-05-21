# ============================================================================
# Tree layouts
#
# Pure geometric layouts of a Mandelbrot.HubbardTree. A layout assigns 2-D
# positions to nodes; a *renderer* (Makie axis, Tachikoma buffer, future
# ASCII grid) consumes a layout and draws it.
#
# Position type matters: `TreeLayout{Float64}` carries continuous positions
# (CairoMakie / Makie); `TreeLayout{Int}` carries lattice positions (ASCII
# renderer). Int positions can promote to Float for Makie; Float positions
# cannot demote to Int for ASCII. So the layout's type tells you which
# renderers can consume it.
#
# Today: `generation_layout` and `reingold_tilford_layout` both return
# Float64 layouts. Future: an `ascii_layout` returning Int positions, paired
# with an ASCII renderer.
# ============================================================================

"""
    TreeLayout{T<:Real}

Geometric layout of a HubbardTree's nodes.

* `positions` — one `(x, y)` per node, in the order returned by
  `Mandelbrot.adjlist(H.adj)`. **Convention: y increases downward** (screen
  coordinates), so the root is at the smallest y. Makie-side renderers
  flip y when plotting.
* `edges` — undirected edge index pairs `(i, j)` with `i < j`.
* `rootindex` — index of the critical point within `positions`.

The type parameter `T` is the position element type: `Float64` for
continuous layouts, `Int` for lattice layouts (planned ASCII).
"""
struct TreeLayout{T<:Real}
    positions::Vector{Tuple{T, T}}
    edges::Vector{Tuple{Int, Int}}
    rootindex::Int
end

# ── Shared graph plumbing ────────────────────────────────────────────────

function _adj_root_kids(H::Mandelbrot.HubbardTree)
    E, nodes = Mandelbrot.adjlist(H.adj)
    rootindex = findfirst(==(H.criticalpoint), nodes)
    rootindex === nothing &&
        throw(ArgumentError("critical point not found in tree's node list"))
    n = length(nodes)
    parent = fill(0, n); parent[rootindex] = -1
    kids = [Int[] for _ in 1:n]
    queue = [rootindex]
    while !isempty(queue)
        u = popfirst!(queue)
        for v in E[u]
            if parent[v] == 0
                parent[v] = u
                push!(kids[u], v)
                push!(queue, v)
            end
        end
    end
    return E, nodes, rootindex, kids
end

function _undirected_edges(E)
    out = Tuple{Int, Int}[]
    seen = Set{Tuple{Int, Int}}()
    for (i, ns) in enumerate(E), j in ns
        a, b = i < j ? (i, j) : (j, i)
        (a, b) in seen && continue
        push!(seen, (a, b))
        push!(out, (a, b))
    end
    return out
end

# ── Generation layout (BFS by depth, normalized to [-1, 1]) ──────────────

"""
    generation_layout(H::HubbardTree) -> TreeLayout{Float64}

BFS-by-depth layout. Nodes at each depth are spread evenly across the
`[-1, 1]` x-range; depth runs top-down from `+1` (root) to `-1` (leaves).
Within each generation, children are ordered using their cyclic position
in the parent's adjacency list (the same heuristic the original
`generationposition` used).
"""
function generation_layout(H::Mandelbrot.HubbardTree)::TreeLayout{Float64}
    E, nodes, rootindex, _ = _adj_root_kids(H)
    n = length(nodes)

    T = [[rootindex], copy(E[rootindex])]
    nadded = 1 + length(T[2])
    while nadded < n
        parents = T[end]
        children = Int[]
        for parent in parents
            s = Mandelbrot.findone(x -> x in T[end - 1], E[parent])
            for u in circshift(E[parent], -s)
                u in T[end - 1] && continue
                push!(children, u)
            end
        end
        push!(T, children)
        nadded += length(children)
    end
    Ngens = length(T)

    X = zeros(Float64, n)
    Y = zeros(Float64, n)
    for (gen, verts) in enumerate(T)
        k = length(verts)
        for (ii, u) in enumerate(verts)
            X[u] = 2 * ii / (k + 1) - 1
            # y-down: root (gen=1) at smallest y, leaves at largest y
            Y[u] = 2 * gen / (Ngens + 1) - 1
        end
    end

    positions = [(X[i], Y[i]) for i in 1:n]
    edges = _undirected_edges(E)
    return TreeLayout{Float64}(positions, edges, rootindex)
end

# ── Reingold-Tilford layout (naive, no contour packing yet) ──────────────

"""
    reingold_tilford_layout(H::HubbardTree) -> TreeLayout{Float64}

Layered layout rooted at the critical point: leaves laid out left-to-right
in DFS order, internal nodes positioned at the midpoint of their
children's x-range, depth running top-down by row.

This is the naive variant — sibling subtrees are spaced by leaf count, not
by true contour. Good enough for typical Hubbard trees; a contour-packing
upgrade can drop in later without changing the interface.
"""
function reingold_tilford_layout(H::Mandelbrot.HubbardTree)::TreeLayout{Float64}
    E, nodes, rootindex, kids = _adj_root_kids(H)
    n = length(nodes)
    x = zeros(Float64, n)
    y = zeros(Float64, n)

    leaf_counter = Ref(0)
    function assign_x(u)
        if isempty(kids[u])
            leaf_counter[] += 1
            x[u] = Float64(leaf_counter[])
        else
            for c in kids[u]
                assign_x(c)
            end
            cxs = [x[c] for c in kids[u]]
            x[u] = (minimum(cxs) + maximum(cxs)) / 2
        end
    end
    assign_x(rootindex)

    function assign_y(u, depth)
        y[u] = Float64(depth)
        for c in kids[u]
            assign_y(c, depth + 1)
        end
    end
    assign_y(rootindex, 0)

    positions = [(x[i], y[i]) for i in 1:n]
    edges = _undirected_edges(E)
    return TreeLayout{Float64}(positions, edges, rootindex)
end
