# This file contains all the print parameters and routines for warnings,
# errors, and debugging.

module Base
    # Re-define the function. Otherwise, the show of an expression may be 
    # too verbose
    function show_expr_type(io::IO, ty)
        return
    end
end

# Buffer the messages so that indentation can be inserted before sending
# to STDOUT
io_buffer = IOBuffer()

function statement_of_ast_node(
    node :: Any,
    cfg  :: CFG
)
    for (bb_idx, bb) in cfg.basic_blocks
        for stmt in bb.statements
            if node == stmt.expr
                return stmt
            end
        end
    end
    return nothing
end

function show_set(
    s :: Set
)
    for x in s
        print(io_buffer, " ", x)
    end
end

function DFS_reorder_graph!(
    sorted :: Vector{ReorderGraphVertex}, 
    vertex :: ReorderGraphVertex
)
    if in(vertex, sorted)
        return
    end

    push!(sorted, vertex)
    for s in vertex.succs
        DFS_reorder_graph!(sorted, s)
    end
    for p in vertex.preds
        DFS_reorder_graph!(sorted, p)
    end
end

function show_reorder_graph(
    liveness :: Liveness,
    graph    :: ReorderGraph
)
    graph_entry = nothing
    for graph_entry in graph.vertices_in_region
        if graph_entry.kind == RG_NODE_ENTRY
            break
        end
    end
    assert(graph_entry != nothing)

    sorted_vertices = Vector{ReorderGraphVertex}()
    DFS_reorder_graph!(sorted_vertices, graph_entry)

    vertex2index = Dict{ReorderGraphVertex, Int}()
    i = 1
    for vertex in sorted_vertices
        vertex2index[vertex] = i
        i = i + 1
    end
    for vertex in sorted_vertices
        print(io_buffer, "Vertex ", vertex2index[vertex])
        print(io_buffer, ": (BB ", 
                (vertex.bb_idx == PSEUDO_BLOCK_INDEX) ? "PSEUDO" : vertex.bb_idx,
                ", Stmt ",
                (vertex.stmt_idx == PSEUDO_STATEMENT_INDEX) ? "PSEUDO" : vertex.stmt_idx,
                ")")
        print(io_buffer, vertex.kind == RG_NODE_ENTRY ? " ENTRY" :
                         vertex.kind == RG_NODE_EMPTY ? " EMPTY" :
                         vertex.kind == RG_NODE_NORMAL ? " NORMAL" :
                         vertex.kind == RG_NODE_OUTSIDE ? " OUTSIDE" : 
                         "IllegalKind!")
        print(io_buffer, " Preds(")
        for p in vertex.preds
            print(io_buffer, " ", vertex2index[p])
        end
        print(io_buffer, " )")
        print(io_buffer, " Succs(")
        for s in vertex.succs
            print(io_buffer, " ", vertex2index[s])
        end
        print(io_buffer, " )")
        print(io_buffer, " In(")
        show_set(vertex.In)
        print(io_buffer, " )")
        print(io_buffer, " Out(")
        show_set(vertex.Out)
        print(io_buffer, " )")
        if vertex.kind == RG_NODE_NORMAL
            bb   = liveness.cfg.basic_blocks[vertex.bb_idx]
            stmt = bb.statements[vertex.stmt_idx]
            for cluster in graph.stmt_clusters[stmt]
                print(io_buffer, " Cluster(LHS:");
                show_set(cluster.LHS)
                print(io_buffer, "; RHS:");
                show_set(cluster.RHS)
                print(io_buffer, " )")
            end
            print(io_buffer, "    ", stmt.expr)
        end
        println(io_buffer, "")
    end
end

function show_liveness(
    space    :: String,
    liveness :: Liveness
)
    println(io_buffer, space, "")
    println(io_buffer, space, "Liveness of basic blocks:")
    space = string(space, "    ")
    cfg = liveness.cfg
    for (bb_idx, bb) in cfg.basic_blocks
        print(io_buffer, space, "BB ", bb_idx)
        print(io_buffer, " Preds(")
        for pred in bb.preds
            print(io_buffer, " ", pred.label)
        end
        print(io_buffer, " ) Succs(")
        for succ in bb.succs
            print(io_buffer, " ", succ.label)
        end
        def      = LivenessAnalysis.def(bb, liveness)
        use      = LivenessAnalysis.use(bb, liveness)
        live_in  = LivenessAnalysis.live_in(bb, liveness)
        live_out = LivenessAnalysis.live_out(bb, liveness)
        print(io_buffer, " ) Def(")
        show_set(def)
        print(io_buffer, " ) Use(")
        show_set(use)
        print(io_buffer, " ) LiveIn(")
        show_set(live_in)
        print(io_buffer, " ) LiveOut(")
        show_set(live_out)
        println(io_buffer, " )")
        for stmt in bb.statements
            expr = stmt.expr
            if typeof(expr) != Expr && typeof(expr) != LabelNode
                continue
            end
            # Unfortunately, we cannot print out LabelNode's from CFG: not exist.
            # in CFG. Only AST has them.
            # TODO: ask CFG package to add LabelNode's. 
            println(io_buffer, space, "    ", expr)
        end
        println(io_buffer, space, "")
    end
end

function show_structure(
    node        :: Any,
    space       :: String,
    symbol_info :: Sym2TypeMap, 
    liveness    :: Liveness
)
    typ = typeof(node)
    if typ == Expr
        args                = node.args
        args_are_statements = false
        if node.head == :lambda
            # args[3] is the body Expr.
            # TODO: LambdaHandling package should identify the body
            args                = node.args[3].args
            args_are_statements = true
            
            show_liveness(space, liveness)
            println(io_buffer, space, "")
            println(io_buffer, space, "Expression trees:")
            space = string(space, "    ")
        end
        println(io_buffer, space, "Expr ", node.head, " [", node.typ, "]")
        for i in 1 : length(args)
            arg = args[i]
            type_of_arg = typeof(arg)
            if (type_of_arg == Expr && arg.head == :line) 
                println(io_buffer, space, "    ", arg)
            else 
                arg_is_insignificant = (type_of_arg == LabelNode) || 
                    (type_of_arg == LineNumberNode) || (type_of_arg == NewvarNode)
                if args_are_statements && !arg_is_insignificant
                    println(io_buffer, space, "    ", "// ", arg)
                    if liveness != empty_liveness
                        stmt = statement_of_ast_node(arg, liveness.cfg)
                        assert(stmt != nothing)
                        def  = LivenessAnalysis.def(stmt, liveness)
                        use  = LivenessAnalysis.use(stmt, liveness)
                        print(io_buffer, space, "    ", "// Def(")
                        show_set(def)
                        print(io_buffer, " ) Use(")
                        show_set(use)
                        println(io_buffer, " )")
                    end
                end
                show_structure(arg, string(space, "    "), symbol_info, liveness)
                if args_are_statements
                    println(io_buffer, "")
                end
            end
        end
    else
        print(io_buffer, space, node, " [", typ, "]")
        typ1 = type_of_ast_node(node, symbol_info)
        if typ != typ1
            println(io_buffer, " [", typ1, "]")
        else
            println(io_buffer, "")
        end
    end
end

import Base.show_backtrace

function show(
    structure   :: Bool, 
    symbol_info :: Sym2TypeMap, 
    liveness    :: Liveness,
    msg
)
    if structure
        show_structure(msg, "", symbol_info, liveness)
    else
        if typeof(msg) <: Exception
            print(io_buffer, msg)
            show_backtrace(io_buffer, catch_backtrace())
            println(io_buffer, "")
        elseif typeof(msg) <: Pattern
            flds = fieldnames(msg)
            for i = 1 : length(flds)
                fld = getfield(msg, flds[i])
                if i < length(flds)
                    println(io_buffer, fld)
                else
                    print(io_buffer, fld)
                end
            end
        elseif typeof(msg) <: Vector{Action}
            for action in msg
                println(io_buffer, "Insert action:")
                for stmt in action.new_stmts
                    println(io_buffer, "    ", stmt.expr)
                end
                if typeof(action) <: InsertBeforeOrAfterStatement
                    println(io_buffer, action.before ? "before" : "after", " BB ", action.bb.label, " statement")
                    println(io_buffer, "    ", action.bb.statements[action.stmt_idx].expr)
                elseif typeof(action) <: InsertBeforeLoopHead
                    print(io_buffer, action.outside_loop ? "outisde" : "inside", " loop of BBs [")
                    total = 0
                    for i in action.loop.members
                        total = total + 1
                        print(io_buffer, i, 
                            total == length(action.loop.members) ? "" : ", ")
                    end
                    println(io_buffer, "] before loop head BB ", action.loop.head)
                else
                    assert(typeof(action) == InsertOnEdge)
                    println(io_buffer, "on the edge BB ", action.from_bb.label, " --> BB ", action.to_bb.label)
                end
                println(io_buffer, "")
            end
        elseif typeof(msg) <: Dict{Any, StructureProxy}
            for (ast, structure) in msg
                println(io_buffer, "Matrix ", ast)
                println(io_buffer, "     ==> ", structure)
            end
        elseif typeof(msg) <: ReorderGraph
            show_reorder_graph(liveness, msg)
        else
            print(io_buffer, msg)
        end
    end
end

function show(
    level         :: Int, 
    indent        :: Int, 
    new_line      :: Bool, 
    structure     :: Bool,
    symbol_info   :: Sym2TypeMap,
    liveness      :: Liveness,
    msgs...
)
    if(level >= verbosity)
        message_tuple = msgs[1]
        for msg in message_tuple
            show(structure, symbol_info, liveness, msg)
        end
        
        seekstart(io_buffer)
        while !eof(io_buffer)
            [print(" ") for i = 1 : indent * 4]
            s = readline(io_buffer)
            print_unescaped(STDOUT, s)
        end
        if new_line 
            println(STDOUT, "") 
        end

        # Resize the buffer to be empty
        truncate(io_buffer, 0) 
    end
end

# ISSUE: Here I break into the internal data structures of Liveness and CFG
# in order to construct an empty liveness, since there is no default constructor
# from the liveness package to do this. This is a temporary workaround.
const empty_liveness = Liveness(Dict(), CFG(Dict(), Set()))

# Debug printing
dprint(level, indent, msgs...)   = show(level, indent, false, false, Sym2TypeMap(), empty_liveness, msgs)
dprintln(level, indent, msgs...) = show(level, indent, true, false, Sym2TypeMap(), empty_liveness, msgs)
dprint(level, indent, liveness :: Liveness, msgs...)   = show(level, indent, false, false, Sym2TypeMap(), liveness, msgs)
dprintln(level, indent, liveness :: Liveness, msgs...) = show(level, indent, true, false, Sym2TypeMap(), liveness, msgs)
dsprint(level, indent, symbol_info, ast :: Expr...)   = show(level, indent, false, true, symbol_info, empty_liveness, ast)
dsprintln(level, indent, symbol_info, ast :: Expr...) = show(level, indent, true, true, symbol_info, empty_liveness, ast)
dsprint(level, indent, symbol_info, liveness :: Liveness, msgs...)   = show(level, indent, false, true, symbol_info, liveness, msgs)
dsprintln(level, indent, symbol_info, liveness :: Liveness, msgs...) = show(level, indent, true, true, symbol_info, liveness, msgs)
