const DEFAULT_TREE_COLORSCHEME = Dict(
    :sn => "black",
    :a0 => "blue",
    :an => "turquoise",
    :a1 => "green",
    :b0 => "red",
    :bn => "orangered2",
    :b1 => "orange",
)

function classify_node(node, HC)
    firstchar = node.items[1]
    if firstchar == Mandelbrot.KneadingSymbol('*')
        return :sn
    elseif firstchar == Mandelbrot.KneadingSymbol('A')
        oz = HC.onezero[node]
        oz == Mandelbrot.Digit{2}(0) && return :a0
        oz === nothing && return :an
        oz == Mandelbrot.Digit{2}(1) && return :a1
    elseif firstchar == Mandelbrot.KneadingSymbol('B')
        oz = HC.onezero[node]
        oz == Mandelbrot.Digit{2}(0) && return :b0
        oz === nothing && return :bn
        oz == Mandelbrot.Digit{2}(1) && return :b1
    end
end

function classify_nodes(Nodes, HC)
    return [classify_node(node, HC) for node in Nodes]
end

const INTERIOR_TYPES = Set([:a0, :a1, :b0, :b1])

function edge_color(type_a, type_b, colorscheme)
    if type_a in INTERIOR_TYPES
        return colorscheme[type_a]
    elseif type_b in INTERIOR_TYPES
        return colorscheme[type_b]
    elseif type_a !== :sn
        return colorscheme[type_a]
    elseif type_b !== :sn
        return colorscheme[type_b]
    else
        return colorscheme[:sn]
    end
end
