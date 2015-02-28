module OptFramework

include("ast_walk.jl")

export @acc 

# This controls the debug print level.  0 prints nothing.  At the moment, 2 prints everything.
DEBUG_LVL=3

function set_debug_level(x)
    global DEBUG_LVL = x
end
 
# A debug print routine.
function dprint(level,msgs...)
    if(DEBUG_LVL >= level)
        print(msgs...)
    end
end

# A debug print routine.
function dprintln(level,msgs...)
    if(DEBUG_LVL >= level)
        println(msgs...)
    end
end

type optPass
    func :: Function
    lowered :: Bool   # uses code_lowered form

    function optPass(f, l)
      new (f, l)
    end
end

optPasses = optPass[]

function setOptPasses(passes :: Array{optPass,1} )
    lowered_first = true

    for i = 1:length(passes)
      if passes[i].lowered == true
        if lowered_first == false
          throw(string("Optimization passes cannot handle a lowered AST pass after a typed AST pass."))
        end
      else
        lowered_first = false
      end
    end

    global optPasses = passes
end

function typeOfOpr(x)
#  dprintln(3,"typeOfOpr ", x, " type = ", typeof(x))
  if isa(x, Expr) x.typ
  elseif isa(x, SymbolNode) x.typ
  else typeof(x) 
  end
end   

type memoizeState
  mapNameFuncInfo :: Dict{Any, Any}   # tracks the mapping from unoptimized function name to optimized function name
  trampolineSet   :: Set{Any}         # tracks whether we've previously created a trampoline for a given function name and signature

  function memoizeState()
    new (Dict{Any,Any}(), Set{Any}())
  end
end

function processFuncCall(func_expr, call_sig_arg_tuple)
  fetyp = typeof(func_expr)

  dprintln(3,"processFuncCall ", func_expr, " ", call_sig_arg_tuple, " ", fetyp)
  func = eval(func_expr)
  dprintln(3,"func = ", func, " type = ", typeof(func))

  ftyp = typeof(func)
  dprintln(4,"After name resolution: func = ", func, " type = ", ftyp)
  if ftyp == DataType
    return nothing
  end
  assert(ftyp == Function || ftyp == IntrinsicFunction || ftyp == LambdaStaticData)

  if ftyp == Function
    #fs = (func, call_sig_arg_tuple)

    if length(optPasses) == 0
      throw(string("There are no registered optimization passes."))
    end

    new_func = deepcopy(func)

    method = Base._methods(new_func, call_sig_arg_tuple, -1)
    assert(length(method) == 1)
    method = method[1]
    # typeof(method) now ((DataType,DataType,DataType),(),Method)

    last_lowered = optPasses[1].lowered

    # typeof(method[3].func.code) = LambdaStaticData
    if last_lowered == true
      cur_ast = Base.uncompressed_ast(method[3].func.code)
    else
      (cur_ast, ty) = Base.typeinf(method[3].func.code, method[1], method[2])
      # typeof(cur_ast) = Array{Uint8,1}
      if !isa(tree,Expr)
         cur_ast = ccall(:jl_uncompress_ast, Any, (Any,Any), method[3].func.code, cur_ast)
      end
    end
    assert(typeof(cur_ast) == Expr)
    assert(cur_ast.head == :lambda)

    dprintln(3,"Initial code to optimize = ", cur_ast)

    for i = 1:length(optPasses)
      if optPasses[i].lowered != last_lowered
        method[3].func.code.ast = ccall(:jl_compress_ast, Any, (Any,Any), method[3].func.code, cur_ast)
        # Must be going from lowered AST to type AST.
        (cur_ast, ty) = typeinf(cur_ast, method[1], method[2])
        if !isa(tree,Expr)
           cur_ast = ccall(:jl_uncompress_ast, Any, (Any,Any), linfo, tree)
        end
      end
      last_lowered = optPasses[i].lowered

      cur_ast = optPasses[i].func(cur_ast, call_sig_arg_tuple)
      dprintln(3,"AST after optimization pass ", i, " = ", cur_ast)
    end

    if last_lowered == true
       method[3].func.code.ast = ccall(:jl_compress_ast, Any, (Any,Any), method[3].func.code, cur_ast)
       # Must be going from lowered AST to type AST.
       (cur_ast, ty) = typeinf(cur_ast, method[1], method[2])
       if !isa(tree,Expr)
          cur_ast = ccall(:jl_uncompress_ast, Any, (Any,Any), linfo, tree)
       end
    end

    # Write the modifed code back to the function.
    methods[3].func.code.tfunc[2] = ccall(:jl_compress_ast, Any, (Any,Any), methods[3].func.code, cur_ast)

    return new_func
  end
  return nothing
end

gOptFrameworkState = memoizeState()

function opt_calls_insert_trampoline(x, state :: memoizeState, top_level_number, is_top_level, read)
  if typeof(x) == Expr
    if x.head == :call
      # We found a call expression within the larger expression.
      call_expr = x.args[1]
      call_sig_args = x.args[2:end]
      dprintln(2, "Start opt_calls = ", call_expr, " signature = ", call_sig_args, " typeof(call_expr) = ", typeof(call_expr))

      # The name of the new trampoline function.
      new_func_name = string("opt_calls_trampoline_", string(call_expr))
      new_func_sym  = symbol(new_func_name)

      # Recursively process the arguments to this function possibly finding other calls to replace.
      for i = 2:length(x.args)
        new_arg = AstWalker.AstWalk(x.args[i], opt_calls_insert_trampoline, state)
        assert(isa(new_arg,Array))
        assert(length(new_arg) == 1)
        x.args[i] = new_arg[1]
      end

      # Form a tuple of the function name and arguments.
      # FIX?  These are the actual arguments so it is likely this won't memoize anything.
      tmtup = (call_expr, call_sig_args)
      if !in(tmtup, state.trampolineSet)
        # We haven't created a trampoline for this function call yet.
        dprintln(3,"Creating new trampoline for ", call_expr)
        # Remember that we've created a trampoline for this pair.
        push!(state.trampolineSet, tmtup)
        println(new_func_sym)
        for i = 1:length(call_sig_args)
          println("    ", call_sig_args[i])
        end
 
       # Define the trampoline.
       @eval function ($new_func_sym)(orig_func, $(call_sig_args...))
              # Create a tuple of the actual argument types for this invocation.
              call_sig = Expr(:tuple)
              call_sig.args = map(typeOfOpr, Any[ $(call_sig_args...) ]) 
              call_sig_arg_tuple = eval(call_sig)
              println(call_sig_arg_tuple)

              # Create a tuple of function and argument types.
              fs = ($new_func_sym, call_sig_arg_tuple)

              # If we have previously optimized this function and type combination ...
              if haskey(gOptFrameworkState.mapNameFuncInfo, fs)
                # ... then call the function we previously optimized.
                func_to_call = gOptFrameworkState.mapNameFuncInfo[fs]
              else
                # ... else see if we can optimize it.
                process_res = processFuncCall(orig_func, call_sig_arg_tuple)

                if process_res != nothing
                  # We did optimize it in some way we will call the optimized version.
                  dprintln(3,"processFuncCall DID optimize ", orig_func)
                  func_to_call = process_res
                else
                  # We did not optimize it so we will call the original function.
                  dprintln(3,"processFuncCall didn't optimize ", orig_func)
                  func_to_call = orig_func
                end
                # Remember this optimization result for this function/type combination.
                gOptFrameworkState.mapNameFuncInfo[fs] = func_to_call
              end

              println("running ", $new_func_name, " fs = ", fs)
              # Call the function.
              func_to_call($(call_sig_args...))
            end
      end

      # Update the call expression to call our trampoline and pass the original function so that we can
      # call it if nothing can be optimized.
      resolved_name = @eval OptFramework.$new_func_sym
      x.args = [ resolved_name, call_expr, x.args[2:end] ]

      dprintln(2, "Replaced call_expr = ", call_expr, " type = ", typeof(call_expr), " new = ", x.args[1])

      return x
    end    
  end
  nothing
end

# Replacing function calls in the expr passed to the macro with trampoline calls.
function convert_expr(ast)
  dprintln(2, "Mtest ", ast, " ", typeof(ast), " gOptFrameworkState = ", gOptFrameworkState)
  res = AstWalker.AstWalk(ast, opt_calls_insert_trampoline, gOptFrameworkState)
  assert(isa(res,Array))
  assert(length(res) == 1)
  dprintln(2,res[1])
  return esc(res[1])
end


macro acc(ast)
  convert_expr(ast)
end


function foo(x)
  println("foo = ", x, " type = ", typeof(x))
  z1 = zeros(100)
  sum = 0.0
  for i = 1:100
    sum = sum + z1[i] 
  end
#  bt = backtrace()
#  Base.show_backtrace(STDOUT, bt)
#  println("")
  x+1
end

function foo2(x,y)
  println("foo2")
  x+y
end

function foo_new(x)
  println("foo_new = ", x)
  x+10
end

function bar(x)
  println("bar = ", x)

  z1 = zeros(100)
  sum = 0.0
  for i = 1:100
    sum = sum + z1[i] 
  end

  x+2
end

function bar_new(x)
  println("bar_new = ", x)
  x+20
end

function testit()
#y = 1
z = 7
#@acc y = foo(bar(y))
#println(macroexpand(quote @acc y = foo(z) end))
#@acc y = foo(z)
#@acc y = foo(y)
println(y)
#processFuncCall(foo, (Int64,))
#convert_expr(quote y = foo(z) end)
end

#testit()

end   # end of module
