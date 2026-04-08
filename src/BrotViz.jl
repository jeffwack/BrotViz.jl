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
       EmbeddedTreePlot,
       generationtreeplot, generationtreeplot!,
       GenerationTreePlot,
       mandelbrotsetplot, mandelbrotsetplot!,
       MandelbrotSetPlot,
       juliasetplot, juliasetplot!,
       JuliaSetPlot,
       spiderplot, showspider,
       plotrays,
       kneadingtable

end
