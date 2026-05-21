using Tachikoma
import CairoMakie
import CairoMakie: Figure, PolarAxis, poly!, hidedecorations!, rlims!, Point2f
import Colors
using Colors: RGBA, RGB, HSV, N0f8

# ── Kneading sequence ─────────────────────────────────────────────────
# Port of the Python kneading_widget: external angle (num/den) under the
# angle-`degree`-tupling map. We follow the orbit until we revisit an
# angle, recording at each step which of the `degree` boundary sectors
# the current angle lies in (or on).

function kneading_seq(num::Int, den::Int, degree::Int)
    den == 0 && return Int[]
    boundaries = [num // den + bb // degree for bb in 0:degree]
    push!(boundaries, 1 // 1)
    pushfirst!(boundaries, 0 // 1)
    sort!(boundaries)

    seq  = Rational{Int}[]
    K    = Int[]
    t    = num // den
    while count(==(t), seq) < 1
        push!(seq, t)
        placed = false
        for qq in 0:degree
            if t == boundaries[qq + 2]                # exact boundary hit
                push!(K, mod(2qq, 2degree))
                placed = true
                break
            elseif boundaries[qq + 2] < t < boundaries[qq + 3]
                push!(K, mod(2qq + 1, 2degree))
                placed = true
                break
            end
        end
        placed || push!(K, 0)
        t = (t * degree) % 1
    end
    return K
end

# ── Color palette for symbols ────────────────────────────────────────
# Matches the Python original: 1000 random RGB colors generated once at
# module load, indexed by symbol value. Different across runs.
const RANDOM_PALETTE = [RGBA{N0f8}(rand(), rand(), rand(), 1.0) for _ in 1:1000]

symbol_palette(degree) = RANDOM_PALETTE

# ── CairoMakie render ────────────────────────────────────────────────
# Builds a PolarAxis with one wedge per (numerator, layer). Returns a
# Matrix{RGBA{N0f8}} sized roughly (px_h, px_w).

function render_kneading(den::Int, degree::Int; px::Int = 720,
                         max_layers::Int = 60)
    palette = symbol_palette(degree)
    fig = Figure(size = (px, px), backgroundcolor = :black)
    ax  = PolarAxis(fig[1, 1];
                    backgroundcolor = :black,
                    rticklabelsvisible = false,
                    thetaticklabelsvisible = false,
                    rgridvisible = false,
                    thetagridvisible = false,
                    spinevisible = false)
    hidedecorations!(ax)

    rmax = 0.0
    nseg = 24  # arc resolution per wedge edge
    for num in 0:(den - 1)
        seq = kneading_seq(num, den, degree)
        nL  = min(length(seq), max_layers)
        θ0  = 2π * (num - 0.5) / den
        θ1  = 2π * (num + 0.5) / den
        θs  = range(θ0, θ1; length = nseg)
        for layer in 1:nL
            r0 = float(layer - 1)
            r1 = float(layer)
            rmax = max(rmax, r1)
            ring = Vector{Point2f}(undef, 2nseg)
            @inbounds for i in 1:nseg
                ring[i]          = Point2f(θs[i], r1)
                ring[2nseg-i+1]  = Point2f(θs[i], r0)
            end
            poly!(ax, ring;
                  color = palette[seq[layer] + 1],
                  strokecolor = :transparent, strokewidth = 0)
        end
    end
    rlims!(ax, 0, rmax > 0 ? rmax : 1)

    # Rasterize. `colorbuffer` returns RGBA{N0f8} matrix.
    img = CairoMakie.Makie.colorbuffer(fig; px_per_unit = 1.0)
    return img
end

# ── Cache + conversion to Tachikoma.ColorRGBA ────────────────────────

_u8(x) = round(UInt8, clamp(float(x), 0, 1) * 255)

function to_tachikoma_rgba(img::AbstractMatrix)
    h, w = size(img)
    out = Matrix{Tachikoma.ColorRGBA}(undef, h, w)
    @inbounds for j in 1:w, i in 1:h
        c = img[i, j]
        out[i, j] = Tachikoma.ColorRGBA(
            _u8(Colors.red(c)),
            _u8(Colors.green(c)),
            _u8(Colors.blue(c)),
            _u8(Colors.alpha(c)),
        )
    end
    return out
end

# ── Model ─────────────────────────────────────────────────────────────
@kwdef mutable struct KneadingModel <: Model
    denominator::Int = 5
    degree::Int      = 2
    max_layers::Int  = 60
    pixels::Union{Nothing, Matrix{Tachikoma.ColorRGBA}} = nothing
    pixel_img::Union{Nothing, PixelImage} = nothing
    pending_gen::Int = 0
    last_rendered_gen::Int = -1
    tq::TaskQueue = TaskQueue()
    quit::Bool = false
    tick::Int = 0
    last_error::Union{Nothing, String} = nothing
end

Tachikoma.task_queue(m::KneadingModel) = m.tq
Tachikoma.should_quit(m::KneadingModel) = m.quit

# Async render — Cairo can take a beat at large denominators, so do it
# off the event loop and feed pixels back via the TaskQueue.
function request_render!(m::KneadingModel)
    m.pending_gen += 1
    g = m.pending_gen
    den, deg, maxL = m.denominator, m.degree, m.max_layers
    spawn_task!(m.tq, :render) do
        img = render_kneading(den, deg; max_layers = maxL)
        (g, to_tachikoma_rgba(img))
    end
end

# ── Input ────────────────────────────────────────────────────────────
function Tachikoma.update!(m::KneadingModel, e::KeyEvent)
    changed = false
    if e.key == :char
        if e.char == 'q'
            m.quit = true; return
        end
    elseif e.key == :escape
        m.quit = true; return
    elseif e.key == :left
        if m.denominator > 1
            m.denominator -= 1; changed = true
        end
    elseif e.key == :right
        if m.denominator < 255
            m.denominator += 1; changed = true
        end
    elseif e.key == :down
        if m.degree > 2
            m.degree -= 1; changed = true
        end
    elseif e.key == :up
        if m.degree < 7
            m.degree += 1; changed = true
        end
    end
    changed && request_render!(m)
end

function Tachikoma.update!(m::KneadingModel, e::TaskEvent)
    e.id == :render || return
    if e.value isa Exception
        io = IOBuffer()
        showerror(io, e.value)
        m.last_error = String(take!(io))
        return
    end
    g, pix = e.value
    if g == m.pending_gen
        m.pixels = pix
        m.last_rendered_gen = g
        m.last_error = nothing
    end
end

# ── View ─────────────────────────────────────────────────────────────
function Tachikoma.view(m::KneadingModel, f::Frame)
    m.tick += 1
    buf  = f.buffer
    rows = split_layout(Tachikoma.Layout(Tachikoma.Vertical,
        [Tachikoma.Fixed(3), Tachikoma.Fill(), Tachikoma.Fixed(1)]), f.area)
    length(rows) < 3 && return
    header, body, statusrow = rows

    hb = Block(title = "Kneading wedges",
               border_style = tstyle(:border),
               title_style  = tstyle(:accent, bold = true))
    inner_h = render(hb, header, buf)
    line = "denominator = $(m.denominator)   degree = $(m.degree)   layers ≤ $(m.max_layers)"
    set_string!(buf, inner_h.x + 1, inner_h.y, line,
                tstyle(:text, bold = true); max_x = right(inner_h))

    pb = Block(title = "Polar disk",
               border_style = tstyle(:border),
               title_style  = tstyle(:title, bold = true))
    inner_p = render(pb, body, buf)

    if m.pixels !== nothing && inner_p.width > 1 && inner_p.height > 1
        if m.pixel_img === nothing ||
           m.pixel_img.cells_w != inner_p.width ||
           m.pixel_img.cells_h != inner_p.height
            m.pixel_img = PixelImage(inner_p.width, inner_p.height)
        end
        load_pixels!(m.pixel_img, m.pixels)
        render(m.pixel_img, inner_p, f; tick = m.tick)
    elseif m.last_error !== nothing
        set_string!(buf, inner_p.x + 1, inner_p.y + 1,
                    "render error: " * m.last_error,
                    tstyle(:warning); max_x = right(inner_p))
    else
        spinner = SPINNER_BRAILLE[mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))]
        set_string!(buf, inner_p.x + 1, inner_p.y + 1,
                    "$spinner rendering…",
                    tstyle(:text_dim); max_x = right(inner_p))
    end

    right_text = m.tq.active[] > 0 ?
        "$(SPINNER_BRAILLE[mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))]) rendering " :
        "ready "
    render(StatusBar(
        left  = [Span(" [←/→] denominator  [↑/↓] degree  [q] quit ",
                      tstyle(:text_dim))],
        right = [Span(right_text, tstyle(:text_dim))],
    ), statusrow, buf)
end

# ── Entry point ──────────────────────────────────────────────────────
function kneading_tui()
    m = KneadingModel()
    request_render!(m)
    app(m; fps = 5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    kneading_tui()
end
