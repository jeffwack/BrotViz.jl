using Tachikoma
using Mandelbrot
using BrotViz: TreeLayout, generation_layout, reingold_tilford_layout

# ── Cell + grid layout ────────────────────────────────────────────────
# Each row corresponds to a candidate `next_int` past the current AIA's
# final period. Each column corresponds to the j-th coprime numerator
# for that row's denominator k (so row widths vary by totient(k)).

struct CellKey
    next_int::Int
    num::Int
    k::Int
end

struct GridCell
    key::CellKey
    aia::AngledInternalAddress
end

cell_label(c::GridCell) = "$(c.key.num)/$(c.key.k)"

# ── Async populator ──────────────────────────────────────────────────
# Walks the (row, coprime-numerator) candidate space and pushes confirmed
# admissible cells into the task queue one at a time. Tagged by a
# generation counter so stale results from a previous AIA are ignored.

function spawn_populator!(tq::TaskQueue, aia::AngledInternalAddress,
                          gen::Int, n_rows::Int)
    token = CancelToken()
    Threads.atomic_add!(tq.active, 1)
    Threads.@spawn begin
        try
            last_int = aia.addr[end]
            for ri in 1:n_rows
                is_cancelled(token) && break
                next_int = last_int + ri
                k = Mandelbrot.newdenominator(aia, next_int)
                for num in 1:(k - 1)
                    is_cancelled(token) && break
                    gcd(num, k) == 1 || continue
                    cand_addr   = vcat(aia.addr,   [next_int])
                    cand_angles = vcat(aia.angles, [num // k])
                    Mandelbrot.admissible(InternalAddress(cand_addr)) || continue
                    cell = GridCell(CellKey(next_int, num, k),
                                    AngledInternalAddress(cand_addr, cand_angles))
                    put!(tq.channel, TaskEvent(:cell, (gen, ri, cell)))
                    tq.on_ready !== nothing && tq.on_ready()
                end
            end
            put!(tq.channel, TaskEvent(:populator_done, gen))
            tq.on_ready !== nothing && tq.on_ready()
        catch e
            put!(tq.channel, TaskEvent(:cell, e))
        finally
            Threads.atomic_sub!(tq.active, 1)
        end
    end
    token
end

# Layouts are provided by BrotViz. The TUI renderer below is one of two
# planned renderers — it consumes any TreeLayout{<:Real} and draws into a
# Tachikoma BlockCanvas. A future ASCII renderer will dispatch on
# TreeLayout{<:Integer} and draw char-by-char with |, /, \ glyphs.

# ── Node labels by orbit ──────────────────────────────────────────────
# Critical orbit gets bare integers (0 = critical, then forward iterates).
# Non-critical periodic orbits are named by `characteristicset` (each orbit
# has a unique "characteristic" representative). Sigils tag the orbits in
# the order returned, and node indices within each orbit are 1-based.

const SIGILS = collect("#%\$@!~&^?+")

"""
    compute_label_set(H::HubbardTree) -> (labels::Vector{String}, char_pts::Vector)

`labels[i]` is the label for `Mandelbrot.adjlist(H.adj)[2][i]`. `char_pts`
is the characteristic-point list (one representative per non-critical
periodic orbit) in the order assigned to the sigils `SIGILS[1]`,
`SIGILS[2]`, … .
"""
function compute_label_set(H::HubbardTree)
    (_, nodes) = Mandelbrot.adjlist(H.adj)
    crit_orbit = Mandelbrot.orbit(H.criticalpoint)
    char_pts   = characteristicset(H)
    char_orbits = [Mandelbrot.orbit(c).items for c in char_pts]

    labels = String[]
    for node in nodes
        ic = findfirst(==(node), crit_orbit.items)
        if ic !== nothing
            push!(labels, string(ic - crit_orbit.preperiod - 1))
            continue
        end
        matched = false
        for (k, orb) in enumerate(char_orbits)
            j = findfirst(==(node), orb)
            j === nothing && continue
            sigil = k <= length(SIGILS) ? SIGILS[k] : '?'
            push!(labels, string(sigil) * string(j))
            matched = true
            break
        end
        matched || push!(labels, repr("text/plain", node))
    end
    return labels, char_pts
end

# BlockCanvas renderer. Accepts any TreeLayout{<:Real} — scales the
# layout's bbox into the area's dot-space and draws thin lines. `labels`
# is precomputed via `compute_label_set`.
function draw_hubbard_tree!(buf::Buffer, area::Rect, H::HubbardTree,
                            layout::TreeLayout{<:Real},
                            labels::Vector{String}, show_labels::Bool)
    (area.width < 2 || area.height < 2) && return
    n = length(layout.positions)
    n == 0 && return

    xs = [p[1] for p in layout.positions]
    ys = [p[2] for p in layout.positions]
    minx, maxx = extrema(xs); miny, maxy = extrema(ys)
    spanx = max(maxx - minx, eps())
    spany = max(maxy - miny, eps())

    # Map to BlockCanvas dot-space, leaving a 1-dot margin all around
    DW = max(2, area.width * 2 - 2)
    DH = max(2, area.height * 2 - 2)
    dot_pos = [(1 + round(Int, (xs[i] - minx) / spanx * (DW - 1)),
                1 + round(Int, (ys[i] - miny) / spany * (DH - 1)))
               for i in 1:n]

    bc = BlockCanvas(area.width, area.height; style=tstyle(:primary, bold=true))
    for (i, j) in layout.edges
        (x0, y0) = dot_pos[i]
        (x1, y1) = dot_pos[j]
        line!(bc, x0, y0, x1, y1)
    end
    render(bc, area, buf)

    # Labels first so nodes win on conflict
    if show_labels && length(labels) == n
        for i in 1:n
            cx = area.x + (dot_pos[i][1] - 1) ÷ 2
            cy = area.y + (dot_pos[i][2] - 1) ÷ 2
            lx = cx + 1
            (lx > right(area) || cy < area.y || cy > bottom(area)) && continue
            set_string!(buf, lx, cy, labels[i],
                        tstyle(:text_dim); max_x=right(area))
        end
    end

    # Nodes
    for i in 1:n
        cx = area.x + (dot_pos[i][1] - 1) ÷ 2
        cy = area.y + (dot_pos[i][2] - 1) ÷ 2
        (cx < area.x || cx > right(area) || cy < area.y || cy > bottom(area)) && continue
        ch = i == layout.rootindex ? '★' : '●'
        nstyle = i == layout.rootindex ? tstyle(:warning, bold=true) :
                                          tstyle(:accent,  bold=true)
        set_char!(buf, cx, cy, ch, nstyle)
    end
end

# ── Model ─────────────────────────────────────────────────────────────
@kwdef mutable struct PhonebookModel <: Model
    aia::AngledInternalAddress = AngledInternalAddress([1], Rational{Int}[])
    history::Vector{AngledInternalAddress} = AngledInternalAddress[]
    rows::Vector{Vector{GridCell}} = [GridCell[] for _ in 1:16]
    n_rows::Int = 16
    cursor_row::Int = 1
    cursor_col::Int = 1
    row_offset::Int = 0
    gen::Int = 0
    populator_token::Union{Nothing, CancelToken} = nothing
    populator_done::Bool = false
    tree::Union{Nothing, HubbardTree} = nothing
    tree_addr::Union{Nothing, AngledInternalAddress} = nothing
    layout::Union{Nothing, TreeLayout} = nothing
    layout_kind::Symbol = :rt        # :rt | :generation — toggle with 'g'
    labels::Vector{String} = String[]
    char_pts::Vector{Any} = Any[]    # characteristic representatives, sigils
    show_labels::Bool = false
    tq::TaskQueue = TaskQueue()
    quit::Bool = false
    tick::Int = 0
end

Tachikoma.task_queue(m::PhonebookModel) = m.tq
Tachikoma.should_quit(m::PhonebookModel) = m.quit

aia_line(a::AngledInternalAddress) =
    replace(repr(a), "Angled Internal Address\n" => "")

current_cell(m::PhonebookModel) =
    (1 <= m.cursor_row <= length(m.rows) &&
     1 <= m.cursor_col <= length(m.rows[m.cursor_row])) ?
    m.rows[m.cursor_row][m.cursor_col] : nothing

function teleport!(m::PhonebookModel, aia::AngledInternalAddress)
    m.populator_token !== nothing && cancel!(m.populator_token)
    m.aia = aia
    m.gen += 1
    m.rows = [GridCell[] for _ in 1:m.n_rows]
    m.cursor_row = 1
    m.cursor_col = 1
    m.row_offset = 0
    m.populator_done = false
    m.populator_token = spawn_populator!(m.tq, aia, m.gen, m.n_rows)
    request_tree!(m, aia)
end

function compute_layout(H::HubbardTree, kind::Symbol)::TreeLayout
    kind == :rt         ? reingold_tilford_layout(H) :
    kind == :generation ? generation_layout(H) :
    throw(ArgumentError("unknown layout :$kind"))
end

function request_tree!(m::PhonebookModel, aia::AngledInternalAddress)
    m.tree = nothing
    m.tree_addr = nothing
    m.layout = nothing
    m.labels = String[]
    m.char_pts = Any[]
    g = m.gen
    spawn_task!(m.tq, :tree) do
        t = HubbardTree(InternalAddress(aia.addr))
        labels, char_pts = compute_label_set(t)
        (g, aia, t, labels, char_pts)
    end
end

# ── Input ─────────────────────────────────────────────────────────────
function Tachikoma.update!(m::PhonebookModel, e::KeyEvent)
    if e.key == :char
        if e.char == 'q'
            m.quit = true
        elseif e.char == 'l'
            m.show_labels = !m.show_labels
        elseif e.char == 'g'
            m.layout_kind = m.layout_kind == :rt ? :generation : :rt
            if m.tree !== nothing
                m.layout = compute_layout(m.tree, m.layout_kind)
            end
        elseif e.char == ' '
            sel = current_cell(m)
            if sel !== nothing
                push!(m.history, m.aia)
                teleport!(m, sel.aia)
            end
        end
        return
    elseif e.key == :escape
        m.quit = true; return
    elseif e.key == :space
        sel = current_cell(m)
        if sel !== nothing
            push!(m.history, m.aia)
            teleport!(m, sel.aia)
        end
        return
    elseif e.key == :backspace
        if !isempty(m.history)
            teleport!(m, pop!(m.history))
        end
        return
    end

    if e.key == :up
        if m.cursor_row > 1
            m.cursor_row -= 1
            m.cursor_col = clamp(m.cursor_col, 1,
                                 max(1, length(m.rows[m.cursor_row])))
        end
    elseif e.key == :down
        if m.cursor_row < length(m.rows)
            m.cursor_row += 1
            m.cursor_col = clamp(m.cursor_col, 1,
                                 max(1, length(m.rows[m.cursor_row])))
        end
    elseif e.key == :left
        m.cursor_col = max(1, m.cursor_col - 1)
    elseif e.key == :right
        rlen = length(m.rows[m.cursor_row])
        if rlen > 0
            m.cursor_col = min(rlen, m.cursor_col + 1)
        end
    elseif e.key == :home
        m.cursor_col = 1
    elseif e.key == :end_key
        rlen = length(m.rows[m.cursor_row])
        m.cursor_col = max(1, rlen)
    end
end

function Tachikoma.update!(m::PhonebookModel, e::TaskEvent)
    if e.id == :cell
        if e.value isa Tuple{Int, Int, GridCell}
            g, ri, cell = e.value
            g == m.gen || return
            1 <= ri <= length(m.rows) || return
            push!(m.rows[ri], cell)
            sort!(m.rows[ri], by = c -> c.key.num)
        end
    elseif e.id == :populator_done
        if e.value isa Int && e.value == m.gen
            m.populator_done = true
        end
    elseif e.id == :tree
        if e.value isa Tuple && length(e.value) == 5
            g, aia, t, labels, char_pts = e.value
            if g == m.gen
                m.tree = t
                m.tree_addr = aia
                m.layout = compute_layout(t, m.layout_kind)
                m.labels = labels
                m.char_pts = collect(char_pts)
            end
        end
    end
end

# ── View ──────────────────────────────────────────────────────────────
function render_grid!(m::PhonebookModel, buf::Buffer, area::Rect)
    rx = right(area)
    by = bottom(area)
    y = area.y

    # Adjust row_offset so cursor row is visible
    visible_h = area.height
    if m.cursor_row - 1 < m.row_offset
        m.row_offset = m.cursor_row - 1
    elseif m.cursor_row > m.row_offset + visible_h
        m.row_offset = m.cursor_row - visible_h
    end

    last_int = m.aia.addr[end]
    for i in 1:visible_h
        ri = m.row_offset + i
        ri > length(m.rows) && break
        cy = area.y + i - 1
        cy > by && break

        row = m.rows[ri]
        next_int = last_int + ri
        prefix = "p=$(lpad(next_int, 2)): "
        set_string!(buf, area.x, cy, prefix, tstyle(:text_dim); max_x=rx)
        cx = area.x + length(prefix)

        if isempty(row)
            placeholder = m.populator_done ? "—" : "…"
            set_string!(buf, cx, cy, placeholder, tstyle(:text_dim); max_x=rx)
            continue
        end

        for (ci, cell) in enumerate(row)
            label = cell_label(cell)
            is_cursor = (ri == m.cursor_row && ci == m.cursor_col)
            style = is_cursor ? tstyle(:accent, bold=true) : tstyle(:text)
            left_br  = is_cursor ? '[' : ' '
            right_br = is_cursor ? ']' : ' '
            cx > rx && break
            set_char!(buf, cx, cy, left_br, style)
            cx += 1
            set_string!(buf, cx, cy, label, style; max_x=rx)
            cx += length(label)
            cx > rx && break
            set_char!(buf, cx, cy, right_br, style)
            cx += 2  # bracket + space
        end
    end

    # Scroll indicators
    if m.row_offset > 0
        set_char!(buf, rx, area.y, '▲', tstyle(:text_dim))
    end
    if m.row_offset + visible_h < length(m.rows)
        set_char!(buf, rx, by, '▼', tstyle(:text_dim))
    end
end

function Tachikoma.view(m::PhonebookModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    # Kneading box grows with the number of characteristic orbits:
    # 1 line for the critical kneading + 1 line per characteristic orbit,
    # plus 2 lines for borders.
    n_char = length(m.char_pts)
    kneading_h = 3 + n_char
    rows = split_layout(Layout(Vertical,
        [Fixed(3), Fixed(kneading_h), Fill(), Fixed(1)]), f.area)
    length(rows) < 4 && return
    header, kneading_row, body, statusrow = rows

    hb = Block(title="Angled Internal Address",
               border_style=tstyle(:border),
               title_style=tstyle(:accent, bold=true))
    inner_h = render(hb, header, buf)
    set_string!(buf, inner_h.x + 1, inner_h.y,
                aia_line(m.aia), tstyle(:text, bold=true);
                max_x=right(inner_h))

    kb = Block(title="Kneading sequence",
               border_style=tstyle(:border),
               title_style=tstyle(:accent, bold=true))
    inner_k = render(kb, kneading_row, buf)
    K = KneadingSequence(InternalAddress(m.aia.addr))
    set_string!(buf, inner_k.x + 1, inner_k.y,
                repr("text/plain", K), tstyle(:text, bold=true);
                max_x=right(inner_k))
    for (k, c) in enumerate(m.char_pts)
        k <= length(SIGILS) || break
        cy = inner_k.y + k
        cy > bottom(inner_k) && break
        line = "$(SIGILS[k]) = $(repr("text/plain", c))"
        set_string!(buf, inner_k.x + 1, cy, line,
                    tstyle(:text_dim); max_x=right(inner_k))
    end

    cols = split_layout(Layout(Horizontal, [Percent(45), Fill()]), body)
    length(cols) < 2 && return
    grid_area, tree_area = cols

    n_admiss = sum(length, m.rows; init=0)
    gb = Block(title="Next entries ($(n_admiss)$(m.populator_done ? "" : "+"))",
               border_style=tstyle(:border),
               title_style=tstyle(:title, bold=true))
    inner_g = render(gb, grid_area, buf)
    render_grid!(m, buf, inner_g)

    layout_tag = m.layout_kind == :rt ? "RT" : "generations"
    labels_tag = m.show_labels ? "labels on" : "labels off"
    tb = Block(title="Hubbard tree — $layout_tag, $labels_tag",
               border_style=tstyle(:border),
               title_style=tstyle(:title, bold=true))
    inner_t = render(tb, tree_area, buf)
    if m.tree !== nothing && m.layout !== nothing
        draw_hubbard_tree!(buf, inner_t, m.tree, m.layout,
                           m.labels, m.show_labels)
    elseif m.tq.active[] > 0
        spinner = SPINNER_BRAILLE[mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))]
        set_string!(buf, inner_t.x + 1, inner_t.y + 1,
                    "$spinner computing tree…",
                    tstyle(:text_dim); max_x=right(inner_t))
    end

    right_text = m.tq.active[] > 0 ?
        "$(SPINNER_BRAILLE[mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))]) busy " :
        "ready "
    render(StatusBar(
        left=[Span(" [arrows] move  [space] descend  [bksp] back  [l] labels  [g] layout  [q] quit ",
                   tstyle(:text_dim))],
        right=[Span(right_text, tstyle(:text_dim))],
    ), statusrow, buf)
end

# ── Entry point ───────────────────────────────────────────────────────
function phonebook_tui()
    m = PhonebookModel()
    m.populator_token = spawn_populator!(m.tq, m.aia, m.gen, m.n_rows)
    request_tree!(m, m.aia)
    app(m; fps=30)
end

if abspath(PROGRAM_FILE) == @__FILE__
    phonebook_tui()
end
