# Plain functions for Mandelbrot and Julia set visualizations
# Works with any Makie backend: GLMakie, CairoMakie, WGLMakie

# ============================================================================
# MandelbrotSetPlot
# ============================================================================

function mandelbrotsetplot!(ax, center, zoom;
        resolution=(1000, 1000), max_iterations=100,
        escape_radius=2.0, colormap=:PRGn_9,
        interior_color=:black, color_mode=:escape_time,
        modulus_period=50)

    # Create coordinate patch
    patch = create_mandelbrot_patch(center, zoom, resolution)

    # Compute escape times
    problem_array = mproblem_array(patch, escape(escape_radius), max_iterations)
    escape_data = escapetime.(problem_array)

    # Apply coloring based on mode
    if color_mode == :escape_time
        pic = [x[1] for x in escape_data]
    elseif color_mode == :modulus
        pic = mod.([x[1] for x in escape_data], modulus_period)
    elseif color_mode == :binary
        pic = [isnan(x[1]) ? 0 : 1 for x in escape_data]
    else
        error("Unknown color_mode: $color_mode")
    end

    # Create the heatmap
    heatmap!(ax, pic, colormap=colormap, nan_color=interior_color)

    return ax
end

function mandelbrotsetplot(center, zoom; kwargs...)
    fig = Figure()
    ax = Axis(fig[1,1])
    mandelbrotsetplot!(ax, center, zoom; kwargs...)
    return fig, ax
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
# JuliaSetPlot
# ============================================================================

function juliasetplot!(ax, parameter, bounds;
        resolution=(500, 500), max_iterations=100,
        escape_threshold=1e4, colormap=:grayC,
        binary_decomposition=false,
        interior_color=RGBf(172/255, 88/255, 214/255))

    # Create Julia set patch
    patch = julia_patch(0.0+0.0im, bounds+0.0im)

    # Define the function
    f(z) = z*z + parameter

    if binary_decomposition
        # Binary decomposition version
        epsilon = 1.0 / escape_threshold
        problem_array = jproblem_array(patch, f, escape(1/epsilon), max_iterations)
        escape_data = escapetime.(problem_array)
        pic = assignbinary.(escape_data)
    else
        # Standard escape-time version
        problem_array = jproblem_array(patch, f, escapeorconverge(escape_threshold), max_iterations)
        escape_data = escapetime.(problem_array)
        pic = [x[1] for x in escape_data]
    end

    # Create the heatmap
    heatmap!(ax, pic, colormap=colormap, nan_color=interior_color)

    return ax
end

function juliasetplot(parameter, bounds; kwargs...)
    fig = Figure()
    ax = Axis(fig[1,1])
    juliasetplot!(ax, parameter, bounds; kwargs...)
    return fig, ax
end

"""
    juliasetplot(angle::Rational, bounds::Real; kwargs...)

Plot the Julia set for the parameter corresponding to the given external angle.
Uses the spider algorithm to find the parameter.
"""
function juliasetplot(angle::Rational, bounds::Real; kwargs...)
    param = parameter(angle, 500)
    juliasetplot(param, bounds; kwargs...)
end
