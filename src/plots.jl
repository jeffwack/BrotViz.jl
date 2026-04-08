function spiderplot end

function showspider end

"""
    mandelbrotsetplot(center::Complex, zoom::Real; kwargs...)

Plot the Mandelbrot set. Requires a Makie backend (GLMakie, CairoMakie, or WGLMakie).

# Keyword Arguments
- `resolution = (1000, 1000)`: Image resolution as (width, height)
- `max_iterations = 100`: Maximum escape-time iterations
- `escape_radius = 2.0`: Escape radius threshold
- `colormap = :PRGn_9`: Color scheme for visualization
- `interior_color = :black`: Color for points in the Mandelbrot set
- `color_mode = :escape_time`: Coloring method (`:escape_time`, `:modulus`, `:binary`)
- `modulus_period = 50`: Period for modulus coloring
"""
function mandelbrotsetplot end
function mandelbrotsetplot! end

"""
    juliasetplot(parameter::Complex, bounds::Real; kwargs...)
    juliasetplot(angle::Rational, bounds::Real; kwargs...)

Plot a Julia set. Requires a Makie backend (GLMakie, CairoMakie, or WGLMakie).

# Keyword Arguments
- `resolution = (500, 500)`: Image resolution as (width, height)
- `max_iterations = 100`: Maximum iterations for escape-time
- `escape_threshold = 1e4`: Escape threshold for convergence test
- `colormap = :grayC`: Colormap for visualization
- `binary_decomposition = false`: Use binary decomposition coloring
- `interior_color = RGBf(172/255, 88/255, 214/255)`: Color for interior points
"""
function juliasetplot end
function juliasetplot! end
