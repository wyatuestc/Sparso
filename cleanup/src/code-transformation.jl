function code_transformation(
    actions     :: Vector{Action},
    func_ast    :: Expr, 
    symbol_info :: Dict{Union(Symbol,Integer), Type}, 
    liveness    :: Liveness, 
    cfg         :: CFG, 
    loop_info   :: DomLoops)

    func_ast
end