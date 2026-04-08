module BrotViz

using Mandelbrot
using Makie
using ColorSchemes, Colors

include("renderfractal.jl")
include("treecolors.jl")
include("showtree.jl")
include("showspider.jl")
include("showrays.jl")
include("mandelbrotset.jl")
include("juliaset.jl")
include("interiorbinarydecomp.jl")
include("recipes.jl")

export embeddedtreeplot, embeddedtreeplot!,
       generationtreeplot, generationtreeplot!,
       mandelbrotsetplot, mandelbrotsetplot!,
       juliasetplot, juliasetplot!,
       spiderplot!, showspider,
       plotrays, plotrays!,
       dynamicraysplot, dynamicraysplot!,
       kneadingtable

end
