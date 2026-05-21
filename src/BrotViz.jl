module BrotViz

using Mandelbrot
using Makie
using ColorSchemes, Colors

include("renderfractal.jl")
include("treecolors.jl")
include("treelayouts.jl")
include("showtree.jl")
include("showspider.jl")
include("showrays.jl")
include("mandelbrotset.jl")
include("juliaset.jl")
include("interiorbinarydecomp.jl")
include("recipes.jl")

export TreeLayout, generation_layout, reingold_tilford_layout,
       embeddedtreeplot, embeddedtreeplot!,
       generationtreeplot, generationtreeplot!,
       treeplot, treeplot!,
       mandelbrotsetplot, mandelbrotsetplot!,
       juliasetplot, juliasetplot!,
       spiderplot!, showspider,
       plotrays, plotrays!,
       dynamicraysplot, dynamicraysplot!,
       kneadingtable

end
