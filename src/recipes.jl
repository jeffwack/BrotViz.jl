# Makie Recipes for Mandelbrot Package Visualizations
# Works with any Makie backend: GLMakie, CairoMakie, WGLMakie
#
# Tree plot recipes (EmbeddedTreePlot, GenerationTreePlot, DendrogramTreePlot)
# are defined in showtree.jl

# ============================================================================
# MandelbrotSetPlot Recipe
# ============================================================================

"""
    MandelbrotSetPlot(center, zoom)

Recipe for plotting the Mandelbrot set.

## Attributes
- `resolution::Tuple{Int,Int} = (1000, 1000)`: Image resolution
- `max_iterations::Int = 100`: Maximum escape-time iterations
- `escape_radius::Real = 2.0`: Escape radius threshold
- `colormap::Symbol = :PRGn_9`: Colormap for visualization
- `interior_color = :black`: Color for points in the Mandelbrot set
- `color_mode::Symbol = :escape_time`: Coloring method (`:escape_time`, `:modulus`, `:binary`)
- `modulus_period::Int = 50`: Period for modulus coloring

## Examples
```julia
using BrotViz, CairoMakie
mandelbrotsetplot(0+0im, 2.0)  # Standard view
mandelbrotsetplot(-0.5+0.5im, 0.1, max_iterations=500)  # Zoomed detail
```
"""
@recipe(MandelbrotSetPlot, center, zoom) do scene
    Attributes(
        resolution = (1000, 1000),
        max_iterations = 100,
        escape_radius = 2.0,
        colormap = :PRGn_9,
        interior_color = :black,
        color_mode = :escape_time,
        modulus_period = 50
    )
end

function Makie.plot!(plot::MandelbrotSetPlot)
    center = plot[1][]
    zoom = plot[2][]

    # Create coordinate patch
    patch = create_mandelbrot_patch(
        center,
        zoom,
        plot[:resolution][]
    )

    # Compute escape times
    problem_array = mproblem_array(
        patch,
        escape(plot[:escape_radius][]),
        plot[:max_iterations][]
    )

    escape_data = escapetime.(problem_array)

    # Apply coloring based on mode
    if plot[:color_mode][] == :escape_time
        pic = [x[1] for x in escape_data]
    elseif plot[:color_mode][] == :modulus
        pic = mod.([x[1] for x in escape_data], plot[:modulus_period][])
    elseif plot[:color_mode][] == :binary
        pic = [isnan(x[1]) ? 0 : 1 for x in escape_data]
    else
        error("Unknown color_mode: $(plot[:color_mode][])")
    end

    # Create the heatmap
    heatmap!(plot, pic,
             colormap = plot[:colormap][],
             nan_color = plot[:interior_color][])

    return plot
end

function create_mandelbrot_patch(center::Complex, zoom::Real, resolution::Tuple{Int,Int})
    width, height = resolution

    # Calculate bounds
    aspect_ratio = height / width
    half_width = zoom / 2
    half_height = half_width * aspect_ratio

    # Create coordinate grid
    x_range = LinRange(real(center) - half_width, real(center) + half_width, width)
    y_range = LinRange(imag(center) - half_height, imag(center) + half_height, height)

    # Create complex coordinate matrix
    return [x + y*im for y in reverse(y_range), x in x_range]
end

# ============================================================================
# JuliaSetPlot Recipe
# ============================================================================

"""
    JuliaSetPlot(parameter, bounds)

Recipe for plotting Julia sets.

## Attributes
- `resolution::Tuple{Int,Int} = (500, 500)`: Image resolution
- `max_iterations::Int = 100`: Maximum iterations for escape-time
- `escape_threshold::Real = 1e4`: Escape threshold for convergence test
- `colormap::Symbol = :grayC`: Colormap for visualization
- `binary_decomposition::Bool = false`: Use binary decomposition coloring
- `interior_color = RGBf(172/255, 88/255, 214/255)`: Color for interior points

## Examples
```julia
using BrotViz, CairoMakie
juliasetplot(-0.3+0.0im, 2.0)  # Julia set for c = -0.3
juliasetplot(-0.7269+0.1889im, 1.5, binary_decomposition=true)  # Binary coloring
```
"""
@recipe(JuliaSetPlot, parameter, bounds) do scene
    Attributes(
        resolution = (500, 500),
        max_iterations = 100,
        escape_threshold = 1e4,
        colormap = :grayC,
        binary_decomposition = false,
        interior_color = RGBf(172/255, 88/255, 214/255)
    )
end

function Makie.plot!(plot::JuliaSetPlot)
    parameter = plot[1][]
    bounds = plot[2][]

    # Create Julia set patch
    patch = julia_patch(0.0+0.0im, bounds+0.0im)

    # Define the function
    f(z) = z*z + parameter

    if plot[:binary_decomposition][]
        # Binary decomposition version
        epsilon = 1.0 / plot[:escape_threshold][]
        problem_array = jproblem_array(patch, f, escape(1/epsilon), plot[:max_iterations][])
        escape_data = escapetime.(problem_array)
        pic = assignbinary.(escape_data)
    else
        # Standard escape-time version
        problem_array = jproblem_array(patch, f, escapeorconverge(plot[:escape_threshold][]), plot[:max_iterations][])
        escape_data = escapetime.(problem_array)
        pic = [x[1] for x in escape_data]
    end

    # Create the heatmap
    heatmap!(plot, pic,
             colormap = plot[:colormap][],
             nan_color = plot[:interior_color][])

    return plot
end

# ============================================================================
# Convenience functions
# ============================================================================

"""
    juliasetplot(angle::Rational, bounds::Real; kwargs...)

Plot the Julia set for the parameter corresponding to the given external angle.
Uses the spider algorithm to find the parameter.
"""
function juliasetplot(angle::Rational, bounds::Real; kwargs...)
    param = parameter(angle, 500)
    juliasetplot(param, bounds; kwargs...)
end
