function spiderplot!(ax, S)
    n = length(S.legs)
    for (j, leg) in enumerate(S.legs)
        lines!(ax, real(leg), imag(leg), color=get(ColorSchemes.viridis, float(j)/float(n)))
        text!(ax, real(leg[end]), imag(leg[end]); text="$j")
    end
    r = 6
    limits!(ax, -r-1, r-1, -r, r)
    return ax
end

function showspider(angle::Rational, frames::Int; save_frames=false)
    S0 = Mandelbrot.standardspider(angle)
    list = Mandelbrot.spideriterates(S0, frames)

    fig = Figure()
    ax = Axis(fig[1, 1])

    num = angle.num
    den = angle.den

    if save_frames
        for i in 1:frames
            empty!(ax)
            spiderplot!(ax, list[i])
            save("$(num).$(den)_$i.png", fig)
        end
    else
        record(fig, "$num.$den.gif", 1:frames; framerate=1) do i
            empty!(ax)
            spiderplot!(ax, list[i])
        end
    end
end
