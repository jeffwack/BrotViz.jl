module BrotViz

using Mandelbrot
using Makie
using ColorSchemes, Colors

include("renderfractal.jl")
include("showtree.jl")
include("showspider.jl")
include("showrays.jl")
include("mandelbrotset.jl")
include("juliaset.jl")
include("interiorbinarydecomp.jl")
include("recipes.jl")

export hubbardtreeplot, hubbardtreeplot!,
       mandelbrotsetplot, mandelbrotsetplot!,
       juliasetplot, juliasetplot!,
       HubbardTreePlot, MandelbrotSetPlot, JuliaSetPlot,
       spiderplot, treeplot, showspider,
       plotrays

end
