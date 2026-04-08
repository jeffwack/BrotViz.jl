function plotrays!(ax, rays::Vector{Vector{ComplexF64}};
        colorscheme=ColorSchemes.cyclic_mygbm_30_95_c78_n256_s25)
    n = length(rays)
    for (j, ray) in enumerate(rays)
        lines!(ax, real(ray), imag(ray),
            color=get(colorscheme, float(j) / float(n)))
    end
    return ax
end

function plotrays(rays::Vector{Vector{ComplexF64}}; kwargs...)
    fig = Figure()
    ax = Axis(fig[1, 1], aspect=1)
    r = 2
    xlims!(-r, r)
    ylims!(-r, r)
    plotrays!(ax, rays; kwargs...)
    return fig, ax
end

"""
    dynamicraysplot!(ax, c::Complex, angle::Rational; R=100, res=10, depth=20, kwargs...)

Plot the dynamic rays of the quadratic polynomial ``z^2 + c`` at the given external angle.
Plots into an existing `Axis`.
"""
function dynamicraysplot!(ax, c::Complex, angle::Rational;
        R=100, res=10, depth=20, kwargs...)
    rays = collect(values(Mandelbrot.dynamicrays(c, Mandelbrot.BinaryExpansion(angle), R, res, depth)))
    plotrays!(ax, rays; kwargs...)
    return ax
end

"""
    dynamicraysplot(c::Complex, angle::Rational; R=100, res=10, depth=20, kwargs...)

Plot the dynamic rays of the quadratic polynomial ``z^2 + c`` at the given external angle.
Creates a new `Figure` and `Axis`.
"""
function dynamicraysplot(c::Complex, angle::Rational;
        R=100, res=10, depth=20, kwargs...)
    rays = collect(values(Mandelbrot.dynamicrays(c, Mandelbrot.BinaryExpansion(angle), R, res, depth)))
    plotrays(rays; kwargs...)
end
