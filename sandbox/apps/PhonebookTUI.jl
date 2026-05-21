using Tachikoma
using Mandelbrot

# ── Children generation ───────────────────────────────────────────────
# Enumerate admissible angled internal addresses one step deeper than `aia`.
function generate_children(aia::AngledInternalAddress; lookahead::Int=20)
    out = AngledInternalAddress[]
    last = aia.addr[end]
    for next_int in (last + 1):(last + lookahead)
        k = Mandelbrot.newdenominator(aia, next_int)
        for num in 1:(k - 1)
            gcd(num, k) == 1 || continue
            cand_addr   = vcat(aia.addr,   [next_int])
            cand_angles = vcat(aia.angles, [num // k])
            Mandelbrot.admissible(InternalAddress(cand_addr)) || continue
            push!(out, AngledInternalAddress(cand_addr, cand_angles))
        end
    end
    sort!(out, by = x -> x.addr[end])
    return out
end

# ── Generation (ancestral) layout in dot-space ────────────────────────
# BFS from `root` down through the tree; each generation gets a row,
# nodes within a generation are spread across the available columns.
# Returns Vector{Tuple{Int,Int}} of (dx, dy) for each node index in 1:n.
function generation_grid(E::Vector{<:Vector{<:Integer}}, root::Int,
                         cells_w::Int, cells_h::Int)
    n = length(E)
    gens = Vector{Vector{Int}}()
    push!(gens, [root])
    seen = Set{Int}([root])
    if !isempty(E[root])
        nxt = Int[]
        for u in E[root]
            if !(u in seen)
                push!(nxt, u); push!(seen, u)
            end
        end
        push!(gens, nxt)
    end
    while length(seen) < n
        kids = Int[]
        for parent in gens[end]
            for u in E[parent]
                if !(u in seen)
                    push!(kids, u); push!(seen, u)
                end
            end
        end
        isempty(kids) && break
        push!(gens, kids)
    end

    DW = max(2, cells_w * 2)
    DH = max(4, cells_h * 4)
    Ngens = length(gens)

    pos = Vector{Tuple{Int,Int}}(undef, n)
    for (gen, verts) in enumerate(gens)
        dy = Ngens == 1 ? DH ÷ 2 :
             round(Int, ((gen - 1) / (Ngens - 1)) * (DH - 1))
        k = length(verts)
        for (ii, u) in enumerate(verts)
            dx = round(Int, ii / (k + 1) * (DW - 1))
            pos[u] = (dx, dy)
        end
    end
    return pos
end

function draw_hubbard_tree!(buf::Buffer, area::Rect, H::HubbardTree)
    (area.width < 2 || area.height < 2) && return
    (E, nodes) = Mandelbrot.adjlist(H.adj)
    rootindex = findfirst(==(H.criticalpoint), nodes)
    rootindex === nothing && return

    pos = generation_grid(E, rootindex, area.width, area.height)

    canvas = Canvas(area.width, area.height; style=tstyle(:primary))
    drawn = Set{Tuple{Int,Int}}()
    for (i, nbrs) in enumerate(E)
        for j in nbrs
            key = i < j ? (i, j) : (j, i)
            key in drawn && continue
            push!(drawn, key)
            (x0, y0) = pos[i]
            (x1, y1) = pos[j]
            line!(canvas, x0, y0, x1, y1)
        end
    end
    render(canvas, area, buf)

    # Overlay node markers at cell resolution
    for (i, (dx, dy)) in enumerate(pos)
        cx = area.x + dx ÷ 2
        cy = area.y + dy ÷ 4
        (cx > right(area) || cy > bottom(area)) && continue
        ch = i == rootindex ? '★' : '●'
        style = i == rootindex ? tstyle(:warning, bold=true) : tstyle(:accent, bold=true)
        set_char!(buf, cx, cy, ch, style)
    end
end

# ── Model ─────────────────────────────────────────────────────────────
@kwdef mutable struct PhonebookModel <: Model
    aia::AngledInternalAddress = AngledInternalAddress([1], Rational{Int}[])
    history::Vector{AngledInternalAddress} = AngledInternalAddress[]
    children::Vector{AngledInternalAddress} = AngledInternalAddress[]
    list::SelectableList = SelectableList(String[])
    tree::Union{Nothing, HubbardTree} = nothing
    tree_addr::Union{Nothing, AngledInternalAddress} = nothing
    tq::TaskQueue = TaskQueue()
    quit::Bool = false
    tick::Int = 0
    status::String = ""
end

Tachikoma.task_queue(m::PhonebookModel) = m.tq
Tachikoma.should_quit(m::PhonebookModel) = m.quit

aia_line(a::AngledInternalAddress) = replace(repr(a), "Angled Internal Address\n" => "")

function refresh_children!(m::PhonebookModel)
    m.children = generate_children(m.aia)
    items = [aia_line(c) for c in m.children]
    m.list = SelectableList(items; focused=true)
end

function request_tree!(m::PhonebookModel, aia::AngledInternalAddress)
    (m.tree_addr == aia && m.tree !== nothing) && return
    m.tree = nothing
    m.tree_addr = nothing
    spawn_task!(m.tq, :tree) do
        t = HubbardTree(InternalAddress(aia.addr))
        (aia, t)
    end
end

function Tachikoma.update!(m::PhonebookModel, e::KeyEvent)
    if e.key == :char
        if e.char == 'q'
            m.quit = true; return
        end
    elseif e.key == :escape
        m.quit = true; return
    end

    if e.key in (:up, :down, :home, :end_key, :pageup, :pagedown)
        handle_key!(m.list, e)
    elseif e.key == :enter || e.key == :right
        idx = value(m.list)
        if 1 <= idx <= length(m.children)
            push!(m.history, m.aia)
            m.aia = m.children[idx]
            refresh_children!(m)
            request_tree!(m, m.aia)
        end
    elseif e.key == :left || e.key == :backspace
        if !isempty(m.history)
            m.aia = pop!(m.history)
            refresh_children!(m)
            request_tree!(m, m.aia)
        end
    end
end

function Tachikoma.update!(m::PhonebookModel, e::TaskEvent)
    if e.id == :tree
        if e.value isa Tuple{AngledInternalAddress, HubbardTree}
            aia, t = e.value
            if aia == m.aia
                m.tree = t
                m.tree_addr = aia
            end
            m.status = ""
        elseif e.value isa Exception
            m.status = "tree error: $(e.value)"
        end
    end
end

# ── View ──────────────────────────────────────────────────────────────
function Tachikoma.view(m::PhonebookModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    rows = split_layout(Layout(Vertical, [Fixed(3), Fill(), Fixed(1)]), f.area)
    length(rows) < 3 && return
    header, body, statusrow = rows

    # Header — current AIA
    hb = Block(title="Angled Internal Address",
               border_style=tstyle(:border),
               title_style=tstyle(:accent, bold=true))
    inner_h = render(hb, header, buf)
    set_string!(buf, inner_h.x + 1, inner_h.y,
                aia_line(m.aia), tstyle(:text, bold=true);
                max_x=right(inner_h))

    cols = split_layout(Layout(Horizontal, [Percent(40), Fill()]), body)
    length(cols) < 2 && return
    list_area, tree_area = cols

    # Left — children list
    m.list.block = Block(
        title="Next entries ($(length(m.children)))",
        border_style=tstyle(:border),
        title_style=tstyle(:title, bold=true),
    )
    render(m.list, list_area, buf)

    # Right — Hubbard tree
    tb = Block(title="Hubbard tree (ancestral)",
               border_style=tstyle(:border),
               title_style=tstyle(:title, bold=true))
    inner_t = render(tb, tree_area, buf)
    if m.tree !== nothing
        draw_hubbard_tree!(buf, inner_t, m.tree)
    elseif m.tq.active[] > 0
        spinner = SPINNER_BRAILLE[mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))]
        set_string!(buf, inner_t.x + 1, inner_t.y + 1,
                    "$spinner computing tree…",
                    tstyle(:text_dim); max_x=right(inner_t))
    else
        set_string!(buf, inner_t.x + 1, inner_t.y + 1,
                    "no tree", tstyle(:text_dim); max_x=right(inner_t))
    end

    # Status bar
    right_text = m.tq.active[] > 0 ?
        "$(SPINNER_BRAILLE[mod1(m.tick ÷ 3, length(SPINNER_BRAILLE))]) busy " :
        (isempty(m.status) ? "ready " : "$(m.status) ")
    render(StatusBar(
        left=[Span(" [↑↓] move  [Enter/→] descend  [←] back  [q] quit ",
                   tstyle(:text_dim))],
        right=[Span(right_text, tstyle(:text_dim))],
    ), statusrow, buf)
end

# ── Entry point ───────────────────────────────────────────────────────
function phonebook_tui()
    m = PhonebookModel()
    refresh_children!(m)
    request_tree!(m, m.aia)
    app(m; fps=30)
end

# Run when included directly
if abspath(PROGRAM_FILE) == @__FILE__
    phonebook_tui()
end
