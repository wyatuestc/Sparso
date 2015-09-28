# Reordering analysis: Feasibility, and where and what to reorder.

# ISSUE: We assume that there are NO aliases between any two arrays. We should
# use both static alias analysis and dynamic alias check to get rid of the 
# assumption.

@doc """
A map from a permutation vector to its inverse.
"""
const inverse_color_map = Dict{Int, Int}(
    ROW_PERM     => ROW_INV_PERM,
    ROW_INV_PERM => ROW_PERM,
    COL_PERM     => COL_INV_PERM,
    COL_INV_PERM => COL_PERM
)

@doc """
A vertex in the inter-dependence graph. Each vertex represents an array's
row or column permutation vector. Color indicates the vector.
"""
type InterDependenceGraphVertex
    array      :: Symexpr
    row_perm   :: Bool
    color      :: Int
    neighbours :: Set{Tuple{InterDependenceGraphVertex, Bool}}
    
    InterDependenceGraphVertex(_array, _row_perm) = new(_array, _row_perm, NO_PERM,
                               Set{Tuple{InterDependenceGraphVertex, Bool}}())
end

@doc """
Inter-dependence graph. It separately represents rows and columns of arrays. It
will be colored starting from the seed.
"""
type InterDependenceGraph
    rows    :: Dict{Symexpr, InterDependenceGraphVertex}
    columns :: Dict{Symexpr, InterDependenceGraphVertex}
    seed    :: Sym
    
    InterDependenceGraph(_seed) = new(
        Dict{Symexpr, InterDependenceGraphVertex}(),
        Dict{Symexpr, InterDependenceGraphVertex}(),
        _seed)
end
 
@doc """
The CallSites' extra field for reordering.
"""
type ReorderingExtra
    seed                   :: Sym
    decider_ast            :: Expr
    decider_bb             :: Any # BasicBlock
    decider_stmt_idx       :: Int
    bb                     :: Any # BasicBlock
    stmt_idx               :: StatementIndex
    inter_dependence_graph :: InterDependenceGraph

    ReorderingExtra(_seed, _decider_ast) = new(_seed, _decider_ast,
             nothing, 0, nothing, 0, InterDependenceGraph(_seed))
end

@doc """"
Build an edge between the two vertices for the inter-dependence graph.
Inverse indicates if their permutation vectors are inverse to each other.
"""
function build_edge(
    vertex1 :: InterDependenceGraphVertex,
    vertex2 :: InterDependenceGraphVertex,
    inverse :: Bool
)
    push!(vertex1.neighbours, (vertex2, inverse))
    push!(vertex2.neighbours, (vertex1, inverse))
end

@doc """
Build a vertex for the array's row or column permutation vector in the
inter-dependence graph.
"""
function build_vertex(
    array    :: Symexpr,
    row_perm :: Bool,
    graph    :: InterDependenceGraph
)
    if row_perm
        if !haskey(graph.rows, array)
            vertex = InterDependenceGraphVertex(array, row_perm)
            graph.rows[array] = vertex
            return vertex
        end
        return graph.rows[array]
    else
        if !haskey(graph.columns, array)
            vertex = InterDependenceGraphVertex(array, row_perm)
            graph.columns[array] = vertex
            return vertex
        end
        return graph.columns[array]
    end
end

@doc """
Build two vertices and and an edge between them in the inter-dependence graph.
"""
function build_vertices_and_edge(
    array_index1 :: Int,
    array_index2 :: Int,
    relation     :: Int,
    ast          :: Expr,
    args         :: Vector,
    graph        :: InterDependenceGraph
)
    array1 = (array_index1 == 0) ? ast : 
             (typeof(args[array_index1]) == SymbolNode ?
              args[array_index1].name : args[array_index1])
    array2 = (array_index2 == 0) ? ast : 
             (typeof(args[array_index2]) == SymbolNode ?
              args[array_index2].name : args[array_index2])

    if relation == ROW_ROW
        vertex1 = build_vertex(array1, true, graph)
        vertex2 = build_vertex(array2, true, graph)
        build_edge(vertex1, vertex2, false)
    elseif relation == COLUMN_COLUMN
        vertex1 = build_vertex(array1, false, graph)
        vertex2 = build_vertex(array2, false, graph)
        build_edge(vertex1, vertex2, false)
    else
        assert(relation == COLUMN_ROW_INVERSE)
        vertex1 = build_vertex(array1, false, graph)
        vertex2 = build_vertex(array2, true, graph)
        build_edge(vertex1, vertex2, true)
    end
end

@doc """
Build inter-dependence graph with the inter-dependence information drawn from
the AST of a function call.
"""
function build_inter_dependence_graph_for_call(
    ast           :: Any,
    module_name   :: String,
    function_name :: String,
    arg_types     :: Tuple,
    args          :: Vector,
    call_sites    :: CallSites
)
    # Recursively handle each argument 
    for arg in args
        build_inter_dependence_graph(arg, call_sites)
    end
    
    # Now handle the call itself
    all_numbers, some_arrays = numbers_or_arrays(ast.typ, arg_types)
    if all_numbers || !some_arrays
        # The function call's result and arguments are all numbers, or 
        # some are non-numbers (like Range{UInt64}) but not regular arrays. 
        # No arrays to care about.
        return nothing
    end

    if function_name == ""
        throw(UnresolvedFunction(head, args[1]))
    end
    fd = look_for_function_description(module_name, function_name, arg_types)
    if fd == nothing
        throw(UndescribedFunction(module_name, function_name, arg_types, ast))
    end
    if !fd.distributive
        throw(NonDistributiveFunction(module_name, function_name, arg_types))
    end
    graph = call_sites.extra.inter_dependence_graph
    for (array_index1, array_index2, relation) in fd.IA
        build_vertices_and_edge(array_index1, array_index2, relation, ast, args, graph)
    end
    return nothing
end
    
@doc """
Build inter-dependence graph with the inter-dependence information drawn from
the AST (of a statement or part of a statement).
"""
function build_inter_dependence_graph(
    ast        :: Any,
    call_sites :: CallSites
)
    if ast == call_sites.extra.decider_ast
        assert(call_sites.extra.decider_bb == nothing)
        assert(call_sites.extra.decider_stmt_idx == 0)
        call_sites.extra.decider_bb       = call_sites.extra.bb
        call_sites.extra.decider_stmt_idx = call_sites.extra.stmt_idx
    end

    local asttyp = typeof(ast)
    if asttyp <: Tuple
        for i = 1:length(ast)
            build_inter_dependence_graph(ast[i], call_sites)
        end
        return nothing
    elseif asttyp == Expr
        symbol_info = call_sites.symbol_info
        head        = ast.head
        args        = ast.args
        if head == :return
            return build_inter_dependence_graph(args, call_sites)
        elseif head == :gotoifnot
            if_clause = args[1]
            return build_inter_dependence_graph(if_clause, call_sites)
        elseif head == :line
            return nothing
        elseif head == :call || head == :call1
            if type_of_ast_node(args[end], symbol_info) == FunctionKnob
                # Ignore the fknob added to the call.
                num_args = length(args) - 2
            else
                num_args = length(args) - 1
            end
            module_name, function_name = resolve_call_names(args)
            arg_types                  = ntuple(i-> type_of_ast_node(args[i+1],
                                                symbol_info), num_args)
            arguments                  = args[2 : num_args + 1]
            return build_inter_dependence_graph_for_call(ast, module_name,
                                function_name, arg_types, arguments, call_sites)
        elseif head == :(=)
            rhs_type = type_of_ast_node(args[2], symbol_info)
            if !(rhs_type <: Vector) && !(rhs_type <: AbstractMatrix)
                # This statement has nothing to do with matrices
                return nothing
            end
            lhs_type = type_of_ast_node(args[1], symbol_info)
            module_name   = ""
            function_name = ":="
            arg_types     = (lhs_type, rhs_type)
            arguments     = args
            return build_inter_dependence_graph_for_call(ast, module_name,
                                function_name, arg_types, arguments, call_sites)
        else
            throw(UnhandledExpr(head, args))
        end
    elseif asttyp == SymbolNode  || asttyp == Symbol   || asttyp == GenSym ||
           asttyp == LabelNode   || asttyp == GotoNode || asttyp == LineNumberNode ||
           asttyp == ASCIIString || asttyp == LambdaStaticData ||
           asttyp <: Number      || asttyp == NewvarNode
        return nothing
    else
        throw(UnknownASTDistributivity(ast))
    end
    return nothing
end

@doc """ A handler to visit_expressions(). """
build_inter_dependence_graph(ast, call_sites :: CallSites, top_level_number, is_top_level, read) =
    build_inter_dependence_graph(ast, call_sites)

@doc """
Color the inter-dependence graph, starting with given vertex, which has been
colored itself.
"""
function color_inter_dependence_graph(
    graph   :: InterDependenceGraph,
    from    :: InterDependenceGraphVertex,
    visited :: Set{InterDependenceGraphVertex}
)
    if in(from, visited)
        return
    end    
    push!(visited, from)
    for (vertex, inverse) in from.neighbours
        color = inverse ? inverse_color_map[from.color] : from.color       
        if vertex.color != NO_PERM
            if vertex.color != color
                # Already colored, but in a different color. A conflict exists
                # But this can indicate that some colors are equal. For example,
                # from p = A * p, we know p.rowPermutation = A.rowPermutation=
                # A.colInversePermutation. Thus p's rowPermutation can have two
                # results (A.rowPermutation and A.colInversePermutation) but that
                # just means that A's rows and columns must be permuted in an
                # inverse relationship: P1 * A * P2, where P1 must equal P2'.
                # This is a nice constraint that compiler should tell libraries
                # so that rows and columns of A won't be reordered independently. 
                # throw(ConflictPermutation(from, vertex, color))
                dprintln(1, 0, "\nPermutation constraints found: ",
                         permutation_color_to_str(vertex.color),
                         " must equal ", 
                         permutation_color_to_str(color))
            end
        else
            vertex.color = color
        end
        color_inter_dependence_graph(graph, vertex, visited)
    end
end

@doc """
Color the inter-dependence graph, starting with the seed in it.
"""
function color_inter_dependence_graph(
    graph :: InterDependenceGraph
)
    seed                      = graph.seed
    seed_rows_vertex          = graph.rows[seed]
    seed_columns_vertex       = graph.columns[seed]
    seed_rows_vertex.color    = ROW_PERM
    seed_columns_vertex.color = COL_PERM
    visited                   = Set{InterDependenceGraphVertex}()
    color_inter_dependence_graph(graph, seed_rows_vertex, visited)
    color_inter_dependence_graph(graph, seed_columns_vertex, visited)
end

@doc """
Add to the new expression a constant that indicates which permutation
vector to use for reordering
"""
function add_permutation_vector(
    new_expr :: Expr,
    perm     :: Int
)
    assert(perm == NO_PERM || perm == ROW_PERM || perm == ROW_INV_PERM || 
           perm == COL_PERM || perm == COL_INV_PERM)
    push!(new_expr.args, 
          perm == NO_PERM ? GlobalRef(SparseAccelerator, :NO_PERM) : 
          perm == ROW_PERM ? GlobalRef(SparseAccelerator, :ROW_PERM) :
          perm == ROW_INV_PERM ? GlobalRef(SparseAccelerator, :ROW_INV_PERM) :
          perm == COL_PERM ? GlobalRef(SparseAccelerator, :COL_PERM) :
          GlobalRef(SparseAccelerator, :COL_INV_PERM))
end

@doc """
Add to the new expression an array for reordering or reverse reordering.
"""
function add_array(
    new_expr      :: Expr,
    A             :: Sym,
    symbol_info   :: Sym2TypeMap, 
    graph         :: InterDependenceGraph,
    matrices_done :: Bool
)
    if !matrices_done && type_of_ast_node(A, symbol_info) <: AbstractSparseMatrix
        Pr = graph.rows[A].color
        Pc = graph.columns[A].color
        if Pr != NO_PERM || Pc != NO_PERM
            push!(new_expr.args, A)
            add_permutation_vector(new_expr, Pr)
            add_permutation_vector(new_expr, Pc)
        end
    elseif  matrices_done && type_of_ast_node(A, symbol_info) <: Vector
        Pr = graph.rows[A].color
        if Pr != NO_PERM
            push!(new_expr.args, A)
            add_permutation_vector(new_expr, Pr)
        end
    end
end

@doc """
Add to the new expression for reordering all the arrays live out of the 
statement that contains the reordering decider. 
This function should be called twice. The first time matrices_done = false, and 
the second time matrices_done = true. They will add matrices and vectors,
respectively.
"""
function add_arrays_to_reorder(
    new_expr      :: Expr,
    decider_stmt  :: Statement,
    symbol_info   :: Sym2TypeMap, 
    liveness      :: Liveness, 
    graph         :: InterDependenceGraph,
    FAR           :: Vector, # Vector{Symbol},
    matrices_done :: Bool
)
    live_out = LivenessAnalysis.live_out(decider_stmt, liveness)
    def      = LivenessAnalysis.def(decider_stmt, liveness)
    use      = LivenessAnalysis.use(decider_stmt, liveness)
    
    # FAR (the symbols defined and used in the decider statements) have already been
    # reordered during the execution of that statement. Reorder all the live-out
    # symbols except them.         
    for A in setdiff(live_out, FAR)
        add_array(new_expr, A, symbol_info, graph, matrices_done)
    end
end

@doc """
Add to the new expression for reverse reodering all the arrays live out of 
from_bb and live into to_bb. 
This function should be called twice. The first time matrices_done = false, and 
the second time matrices_done = true. They will add matrices and vectors,
respectively.
"""
function add_arrays_to_reversely_reorder(
    new_expr      :: Expr,
    from_bb       :: BasicBlock,
    to_bb         :: BasicBlock,
    symbol_info   :: Sym2TypeMap, 
    liveness      :: Liveness, 
    graph         :: InterDependenceGraph,
    matrices_done :: Bool
)
    live_out = LivenessAnalysis.live_out(from_bb, liveness)
    live_in  = LivenessAnalysis.live_in(to_bb, liveness)
    for A in intersect(live_out, live_in)
        add_array(new_expr, A, symbol_info, graph, matrices_done)
    end
end

@doc """
Create reorder actions for the loop region.
"""
function create_reorder_actions(
    actions          :: Vector{Action},
    region           :: LoopRegion,
    symbol_info      :: Sym2TypeMap, 
    liveness         :: Liveness, 
    graph            :: InterDependenceGraph,
    cfg              :: CFG, 
    FAR              :: Vector, # Vector{Symbol},
    fknob            :: Symbol,
    decider_bb       :: Any,   # BasicBlock,
    decider_stmt_idx :: StatementIndex
)
    # Create an action that would insert new statements before the region
    # loop's head block. There are two new statements: one is to set
    # the reordering decision maker; the other is to initialize reordering_status.
    before_loop_action = InsertBeforeLoopHead(Vector{Statement}(), region.loop, true)
    push!(actions, before_loop_action)

    stmt = Expr(:call, GlobalRef(SparseAccelerator, :set_reordering_decision_maker), fknob)
    push!(before_loop_action.new_stmts,  Statement(0, stmt))

    reordering_status = gensym("reordering_status")
    stmt              = Expr(:(=), reordering_status,
                              Expr(:call, TopNode(:vect), false, 
                                    GlobalRef(Main, :C_NULL), 
                                    GlobalRef(Main, :C_NULL),
                                    GlobalRef(Main, :C_NULL),
                                    GlobalRef(Main, :C_NULL),
                                    0.0))
    push!(before_loop_action.new_stmts,  Statement(0, stmt))

    # In the loop, after the statement that contains the reordering decision maker,
    # insert a statement to reorder other arrays. 
    inside_loop_action = InsertBeforeOrAfterStatement(Vector{Statement}(),
                            false, decider_bb, decider_stmt_idx)
    push!(actions, inside_loop_action)
    
    stmt = Expr(:call, GlobalRef(SparseAccelerator, :reordering),
                 fknob, reordering_status)
    push!(inside_loop_action.new_stmts,  Statement(0, stmt))

    decider_stmt = decider_bb.statements[decider_stmt_idx]
    add_arrays_to_reorder(stmt, decider_stmt, symbol_info, liveness, graph, FAR, false)
    push!(stmt.args, QuoteNode(:__delimitor__))
    add_arrays_to_reorder(stmt, decider_stmt, symbol_info, liveness, graph, FAR, true)
    
    # At each loop exit, insert reverse reordering of array.
    # Create statements that will delete the function knob at region exits
    for exit in region.exits
        action = InsertOnEdge(Vector{Statement}(), exit.from_bb, exit.to_bb)
        push!(actions, action)

        stmt = Expr(:call, GlobalRef(SparseAccelerator, :reverse_reordering),
                     reordering_status)
        push!(action.new_stmts,  Statement(0, stmt))
    
        add_arrays_to_reversely_reorder(stmt, exit.from_bb, exit.to_bb, symbol_info, liveness, graph, false)
        push!(stmt.args, QuoteNode(:__delimitor__))
        add_arrays_to_reversely_reorder(stmt, exit.from_bb, exit.to_bb, symbol_info, liveness, graph, true)
    end
end

@doc """ 
Perform analyses for reordering. Write the intended transformation into actions.
"""
function reordering(
    actions     :: Vector{Action},
    region      :: LoopRegion,
    symbol_info :: Sym2TypeMap, 
    liveness    :: Liveness, 
    cfg         :: CFG,
    call_sites  :: CallSites
)
    old_actions = copy(actions)
    old_extra   = call_sites.extra
    try
        decider = call_sites.extra.reordering_decider
        if decider == nothing
            return actions
        end

        FAR              = call_sites.extra.reordering_FAR
        seed             = FAR[1]
        fknob            = call_sites.extra.expr2fknob[decider]
        call_sites.extra = ReorderingExtra(seed, decider)
        
        # An empty inter-dependence graph has been built. Build a row and a 
        # column vertex for the seed.
        graph = call_sites.extra.inter_dependence_graph
        build_vertex(seed, true, graph)
        build_vertex(seed, false, graph)
        
        recursive  = false
        vist_expressions(region, cfg, call_sites, recursive, build_inter_dependence_graph)

        dprintln(1, 0, "\nInter-dependence graph:")
        dprintln(1, 1, liveness, graph)

        color_inter_dependence_graph(graph)

        dprintln(1, 0, "\nColored inter-dependence graph:")
        dprintln(1, 1, liveness, graph)

        create_reorder_actions(actions, region, symbol_info, liveness, graph, 
                               cfg, FAR, fknob, 
                               call_sites.extra.decider_bb,
                               call_sites.extra.decider_stmt_idx)

        dprintln(1, 0, "\nReordering actions to take:", actions)
    catch ex
        # In case any exception happen in the printing, try
        try
            Libc.flush_cstdio()
            flush(STDOUT)
            dprintln(1, 0, "Exception! Sparse Accelerator skips reordering the loop.")
            dprintln(1, 1, ex)
            dprintln(1, 0, "********************************************************************************")
            Libc.flush_cstdio()
            flush(STDOUT)
        catch
            # Do nothing
        end

        actions = old_actions
    finally
        call_sites.extra = old_extra
        return actions
    end
end
