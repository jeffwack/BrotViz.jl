# Shared helpers

function _tree_node_labels(nodes, criticalorbit)
    labels = String[]
    for node in nodes
        idx = findall(x->x==node, criticalorbit.items)
        if isempty(idx)
            push!(labels, repr("text/plain", node))
        else
            push!(labels, string(idx[1]-criticalorbit.preperiod-1))
        end
    end
    return labels
end

function _colored_tree_data(angle::Rational; colorscheme=DEFAULT_TREE_COLORSCHEME)
    HC = HyperbolicComponent(angle)
    htree = HC.htree
    (E, nodes) = Mandelbrot.adjlist(htree.adj)
    nodetypes = classify_nodes(nodes, HC)
    nodecolors = [colorscheme[t] for t in nodetypes]
    edgecolorfn = (ii, n) -> edge_color(nodetypes[ii], nodetypes[n], colorscheme)
    return HC, htree, E, nodes, nodecolors, edgecolorfn
end

function _tree_data(H::HubbardTree)
    (E, nodes) = Mandelbrot.adjlist(H.adj)
    return E, nodes, "black", nothing
end

# Generation layout algorithm

function generationposition(E, root)
    T = [[root], E[root]]

    nadded = 1 + length(T[2])
    n = length(E)

    while nadded < n
        parents = T[end]
        children = []
        for parent in parents
            s = Mandelbrot.findone(x-> x in T[end-1], E[parent])
            for u in circshift(E[parent], -s)
                if !(u in T[end-1])
                    push!(children, u)
                end
            end
        end
        push!(T, children)
        nadded += length(children)
    end
    Ngens = length(T)

    X = zeros(Float64, n)
    Y = zeros(Float64, n)

    for (gen, vertices) in enumerate(T)
        k = length(vertices)
        for (ii, u) in enumerate(vertices)
            X[u] = 2*ii/(k+1) - 1
            Y[u] = 2*(1 - gen/(Ngens+1)) - 1
        end
    end

    return Point.(X, Y)
end


# ============================================================================
# Embedded Tree Plot (Rational only — requires HyperbolicComponent)
# ============================================================================

@recipe(EmbeddedTreePlot, angle) do scene
    Attributes(
        show_rays = true,
        show_julia = true,
        node_size = 10,
        ray_colormap = :rainbow,
        julia_resolution = 20,
        colorscheme = DEFAULT_TREE_COLORSCHEME,
        show_labels = true
    )
end

function Makie.plot!(plot::EmbeddedTreePlot)
    angle = plot[1][]
    colorscheme = plot[:colorscheme][]
    HC, htree, EdgeList, Nodes, nodecolors, edgecolorfn = _colored_tree_data(angle; colorscheme)
    criticalorbit = orbit(htree.criticalpoint)

    # Julia set background
    if plot[:show_julia][]
        julia = inverseiterate(HC.parameter, plot[:julia_resolution][])
        scatter!(plot, real(julia), imag(julia), markersize=1, color=:black)
    end

    # Edges
    for (ii, p) in enumerate(EdgeList)
        for n in p
            cmplxedge = HC.edges[Set([Nodes[ii], Nodes[n]])][2]
            realedge = Point.(real.(cmplxedge), imag.(cmplxedge))
            col = edgecolorfn(ii, n)
            lines!(plot, realedge, color=col, linewidth=1, transparency=true, overdraw=true)
        end
    end

    # External rays
    if plot[:show_rays][]
        rays = collect(values(HC.rays))
        nrays = length(rays)
        for (j, ray) in enumerate(rays)
            lines!(plot, real(ray), imag(ray), color=get(ColorSchemes.rainbow, float(j)/float(nrays)))
        end
    end

    # Nodes
    zvalues = [HC.vertices[node] for node in Nodes]
    pos = Point.(real.(zvalues), imag.(zvalues))
    scatter!(plot, pos, color=nodecolors, markersize=plot[:node_size][])

    # Labels
    if plot[:show_labels][]
        labels = _tree_node_labels(Nodes, criticalorbit)
        text!(plot, pos, text=labels)
    end

    return plot
end

# ============================================================================
# Generation Tree Plot (HubbardTree or Rational)
# ============================================================================

@recipe(GenerationTreePlot) do scene
    Attributes(
        node_size = 10,
        colorscheme = DEFAULT_TREE_COLORSCHEME,
        show_labels = true
    )
end

function Makie.plot!(plot::GenerationTreePlot)
    input = plot[1][]

    if input isa Rational
        _, htree, E, nodes, nodecolors, edgecolorfn = _colored_tree_data(input; colorscheme=plot[:colorscheme][])
        H = htree
    else
        H = input
        E, nodes, nodecolors, edgecolorfn = _tree_data(H)
    end

    root = H.criticalpoint
    rootindex = findall(x->x==root, nodes)[1]
    pos = generationposition(E, rootindex)

    # Edges
    for (ii, p) in enumerate(E)
        for n in p
            col = edgecolorfn === nothing ? "black" : edgecolorfn(ii, n)
            lines!(plot, [pos[ii], pos[n]], linewidth=1, color=col)
        end
    end

    # Nodes
    scatter!(plot, pos, color=nodecolors, markersize=plot[:node_size][])

    # Labels
    if plot[:show_labels][]
        criticalorbit = orbit(root)
        labels = _tree_node_labels(nodes, criticalorbit)
        text!(plot, pos, text=labels)
    end

    return plot
end


# ============================================================================
# Convenience functions
# ============================================================================

function embeddedtreeplot(angle::Rational; kwargs...)
    fig = Figure()
    ax = Axis(fig[1,1])
    embeddedtreeplot!(ax, angle; kwargs...)
    limits!(-2, 2, -2, 2)
    return fig
end

function kneadingtable(angles::Vector{<:Rational})
    nrows = length(angles)
    height = 400
    width = 600
    fig = Figure(size=(width, height))

    for (row, angle) in enumerate(angles)
        K = KneadingSequence(angle)
        ia = InternalAddress(K)
        H = HubbardTree(ia)

        Label(fig[row, 1], repr("text/plain", K), tellwidth=false)
        Label(fig[row, 2], repr("text/plain", ia), tellwidth=false)

        ax = Axis(fig[row, 3], aspect=1, height=height/nrows, limits=(-1, 1, -1, 1))
        hidedecorations!(ax)
        hidespines!(ax)
        generationtreeplot!(ax, H; show_labels=false)
    end

    return fig
end

# ============================================================================
# Legacy functions
# ============================================================================

function plotedges!(scene, edgevectors)
    for edge in edgevectors
        line = edge[2][2]
        lines!(scene, real.(line)/2, imag(line)/2, color="black")
    end
    return scene
end

function plotedges(edgevectors)
    scene = Scene(size=(1000, 1000), aspect=1)
    return plotedges!(scene, edgevectors)
end

function embedanim(AIA::AngledInternalAddress, frames)
    OHT = OrientedHubbardTree(AIA)
    (E, c) = Mandelbrot.standardedges(OHT)

    edgelist = [E]
    for ii in 1:frames
        E = Mandelbrot.refinetree(OHT, c, E)
        push!(edgelist, E)
    end

    scene = Scene(size=(1000, 1000), aspect=1)
    record(scene, "embedding.gif", 1:frames, framerate=3) do ii
        empty!(scene)
        plotedges!(scene, edgelist[ii])
    end
end

function embedanim(angle::Rational, frames)
    AIA = AngledInternalAddress(angle)
    return embedanim(AIA, frames)
end

function showtree!(scene, angle::Rational)
    E = Mandelbrot.refinedtree(angle, 8)
    return plotedges!(scene, E)
end

function showtree(angle::Rational)
    scene = Scene(size=(500, 500))
    return showtree!(scene, angle)
end
