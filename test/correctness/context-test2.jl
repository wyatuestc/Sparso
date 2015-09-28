include("../../src/SparseAccelerator.jl")
include("./utils.jl")
using SparseAccelerator

# The original pcg_symgs
#include("./pcg-symgs.jl")
function pcg_symgs(x, A, b, tol, maxiter)
    total_time = time()
  
    trsv_time = 0.
    spmv_time = 0.
    blas1_time = 0.

    L = tril(A)
    U  = SparseMatrixCSC{Cdouble, Cint}(spdiagm(1./diag(A)))*triu(A)

    spmv_time -= time()
    #r = b - A * x
    r = b - SparseAccelerator.SpMV(A,x)
    spmv_time += time()

    blas1_time -= time()
    #normr0 = norm(r)
    normr0 = SparseAccelerator.norm(r)
    z = copy(r)
    blas1_time += time()

    rel_err = 1

    trsv_time -= time()
    Base.SparseMatrix.fwdTriSolve!(L, z)
    Base.SparseMatrix.bwdTriSolve!(U, z)
    trsv_time += time()

    blas1_time -= time()
    p = copy(z) #NOTE: do not write "p=z"! That would make p and z aliased (the same variable)
    #rz = dot(r, z)
    rz = SparseAccelerator.dot(r,z)
    blas1_time += time()

    k = 1
    while k <= maxiter
        old_rz = rz

        spmv_time -= time()
        #Ap = A*p
        Ap = SparseAccelerator.SpMV(A,p)
        spmv_time += time()

        blas1_time -= time()
        #alpha = old_rz / dot(p, Ap)
        alpha = old_rz / SparseAccelerator.dot(p, Ap)
        #x += alpha * p
        SparseAccelerator.WAXPBY!(x,1,x,alpha,p)
        #r -= alpha * Ap
        SparseAccelerator.WAXPBY!(r,1,r,-alpha,Ap)
        #rel_err = norm(r)/normr0
        rel_err = SparseAccelerator.norm(r)/normr0
        blas1_time += time()

        if rel_err < tol 
            break
        end

        blas1_time -= time()
        #z = copy(r)
        SparseAccelerator.copy!(z, r)
        blas1_time += time()

        trsv_time -= time()
        Base.SparseMatrix.fwdTriSolve!(L, z)
        Base.SparseMatrix.bwdTriSolve!(U, z)
        trsv_time += time()

        blas1_time -= time()
        #rz = dot(r, z)
        rz = SparseAccelerator.dot(r,z)
        beta = rz/old_rz
        #p = z + beta * p
        SparseAccelerator.WAXPBY!(p,1,z,beta,p)
        blas1_time += time()

        k += 1
    end
    total_time = time() - total_time
    println("total = $(total_time)s trsv_time = $(trsv_time)s ($((12.*(nnz(L) + nnz(U)) + 2.*8*(size(L, 1) + size(L, 2)))*k/trsv_time/1e9) gbps) spmv_time = $(spmv_time)s ($((12.*nnz(A) + 8.*(size(A, 1) + size(A, 2)))*(k + 1)/spmv_time/1e9) gbps) blas1_time = $blas1_time")

    return x, k, rel_err
end

# This code is what we expect to generate by context-sensitive optimizations except for reordering.
# It is used for debugging purpose only
function pcg_symgs_with_context_opt_without_reordering(x, A, b, tol, maxiter)
    total_time = time()
  
    trsv_time = 0.
    spmv_time = 0.
    blas1_time = 0.

    L = tril(A)
    U = SparseMatrixCSC{Cdouble, Cint}(spdiagm(1./diag(A)))*triu(A)

    spmv_time -= time()
    #r = b - A * x
    r = b - SparseAccelerator.SpMV(A,x)
    spmv_time += time()

    blas1_time -= time()
    #normr0 = norm(r)
    normr0 = SparseAccelerator.norm(r)
    z = copy(r)
    blas1_time += time()

    rel_err = 1

    trsv_time -= time()
    Base.SparseMatrix.fwdTriSolve!(L, z)
    Base.SparseMatrix.bwdTriSolve!(U, z)
    trsv_time += time()

    blas1_time -= time()
    p = copy(z) #NOTE: do not write "p=z"! That would make p and z aliased (the same variable)
    #rz = dot(r, z)
    rz = SparseAccelerator.dot(r,z)
    blas1_time += time()

    k = 1

    __mknobA = (SparseAccelerator.new_matrix_knob)(A, true, true, true, true, false, false)
    __mknobL = (SparseAccelerator.new_matrix_knob)(L, true, true, false, false, false, false) # matrix knob for L
    __mknobU = (SparseAccelerator.new_matrix_knob)(U, true, true, false, false, false, false) # matrix knob for L

    (SparseAccelerator.set_derivative)(__mknobL, SparseAccelerator.DERIVATIVE_TYPE_SYMMETRIC, __mknobA)
    (SparseAccelerator.set_derivative)(__mknobU, SparseAccelerator.DERIVATIVE_TYPE_SYMMETRIC, __mknobA)

    fknob_spmv = (SparseAccelerator.new_function_knob)()
    (SparseAccelerator.add_mknob_to_fknob)(__mknobA,fknob_spmv)
    __fknob_8201 = (SparseAccelerator.new_function_knob)()
    (SparseAccelerator.add_mknob_to_fknob)(__mknobL,__fknob_8201)
    __fknob_8221 = (SparseAccelerator.new_function_knob)()
    (SparseAccelerator.add_mknob_to_fknob)(__mknobU,__fknob_8221)

    while k <= maxiter
        old_rz = rz

        spmv_time -= time()
        #Ap = A*p
        Ap = SparseAccelerator.SpMV(A,p,fknob_spmv)
        spmv_time += time()

        blas1_time -= time()
        #alpha = old_rz / dot(p, Ap)
        alpha = old_rz / SparseAccelerator.dot(p, Ap)
        #x += alpha * p
        SparseAccelerator.WAXPBY!(x,1,x,alpha,p)
        #r -= alpha * Ap
        SparseAccelerator.WAXPBY!(r,1,r,-alpha,Ap)
        #rel_err = norm(r)/normr0
        rel_err = SparseAccelerator.norm(r)/normr0
        blas1_time += time()

        if rel_err < tol 
            break
        end

        blas1_time -= time()
        #z = copy(r)
        SparseAccelerator.copy!(z, r)
        blas1_time += time()

        trsv_time -= time()
        #Base.SparseMatrix.fwdTriSolve!(L, z)
        SparseAccelerator.fwdTriSolve!(L, z, __fknob_8201)
        #Base.SparseMatrix.bwdTriSolve!(U, z)
        SparseAccelerator.bwdTriSolve!(U, z, __fknob_8221)
        trsv_time += time()

        blas1_time -= time()
        #rz = dot(r, z)
        rz = SparseAccelerator.dot(r,z)
        beta = rz/old_rz
        #p = z + beta * p
        SparseAccelerator.WAXPBY!(p,1,z,beta,p)
        blas1_time += time()

        k += 1
    end

    (SparseAccelerator.delete_function_knob)(__fknob_8221)
    (SparseAccelerator.delete_function_knob)(__fknob_8201)
    (SparseAccelerator.delete_matrix_knob)(__mknobL)
    
    total_time = time() - total_time
    println("total = $(total_time)s trsv_time = $(trsv_time)s ($((12.*(nnz(L) + nnz(U)) + 2.*8*(size(L, 1) + size(L, 2)))*k/trsv_time/1e9) gbps) spmv_time = $(spmv_time)s ($((12.*nnz(A) + 8.*(size(A, 1) + size(A, 2)))*(k + 1)/spmv_time/1e9) gbps) blas1_time = $blas1_time")

    return x, k, rel_err
end


# This code is what we expect to generate by context-sensitive optimizations.
# It is used for debugging purpose only
function pcg_symgs_with_context_opt(x, A, b, tol, maxiter)
    total_time = time()
  
    trsv_time = 0.
    spmv_time = 0.
    blas1_time = 0.
    reorder_time = 0.

    L = tril(A)
    U  = SparseMatrixCSC{Cdouble, Cint}(spdiagm(1./diag(A)))*triu(A)

    spmv_time -= time()
    #r = b - A * x
    r = b - SparseAccelerator.SpMV(A,x)
    spmv_time += time()

    blas1_time -= time()
    #normr0 = norm(r)
    normr0 = SparseAccelerator.norm(r)
    z = copy(r)
    blas1_time += time()

    rel_err = 1

    trsv_time -= time()
    Base.SparseMatrix.fwdTriSolve!(L, z)
    Base.SparseMatrix.bwdTriSolve!(U, z)
    trsv_time += time()

    blas1_time -= time()
    p = copy(z) #NOTE: do not write "p=z"! That would make p and z aliased (the same variable)
    #rz = dot(r, z)
    rz = SparseAccelerator.dot(r,z)
    blas1_time += time()

    k = 1

    __mknobA = (SparseAccelerator.new_matrix_knob)(A, true, true, true, true, false, false)
    __mknobL = (SparseAccelerator.new_matrix_knob)(L, true, true, false, false, false, false) # matrix knob for L
    __mknobU = (SparseAccelerator.new_matrix_knob)(U, true, true, false, false, false, false) # matrix knob for L

    (SparseAccelerator.set_derivative)(__mknobL, SparseAccelerator.DERIVATIVE_TYPE_SYMMETRIC, __mknobA)
    (SparseAccelerator.set_derivative)(__mknobU, SparseAccelerator.DERIVATIVE_TYPE_SYMMETRIC, __mknobA)

    fknob_spmv = (SparseAccelerator.new_function_knob)()
    (SparseAccelerator.add_mknob_to_fknob)(__mknobA,fknob_spmv)
    __fknob_8201 = (SparseAccelerator.new_function_knob)()
    (SparseAccelerator.add_mknob_to_fknob)(__mknobL,__fknob_8201)
    __fknob_8221 = (SparseAccelerator.new_function_knob)()
    (SparseAccelerator.add_mknob_to_fknob)(__mknobU,__fknob_8221)

    # Set up reordering:
    # Let SparseAccelerator.fwdTriSolve! decides what permutation/inverse
    # permutation vector should be, and reorders its inputs andoutputs accordingly.
    # Other functions just respect the decision, makes no decision, nor does any
    # reordering.
    (SparseAccelerator.set_reordering_decision_maker)(__fknob_8201)

    # Reordering_status is a vector. See the comments in lib-interface.jl:
    # reordering() for the meaning of the elements
    reordering_status = [false, C_NULL, C_NULL, C_NULL, C_NULL, reorder_time]
    while k <= maxiter
        old_rz = rz

        spmv_time -= time()
        #Ap = A*p
        Ap = SparseAccelerator.SpMV(A,p,fknob_spmv)
        spmv_time += time()

        blas1_time -= time()
        #alpha = old_rz / dot(p, Ap)
        alpha = old_rz / SparseAccelerator.dot(p, Ap)
        #x += alpha * p
        SparseAccelerator.WAXPBY!(x,1,x,alpha,p)
        #r -= alpha * Ap
        SparseAccelerator.WAXPBY!(r,1,r,-alpha,Ap)
        #rel_err = norm(r)/normr0
        rel_err = SparseAccelerator.norm(r)/normr0
        blas1_time += time()

        if rel_err < tol 
            break
        end

        blas1_time -= time()
        #z = copy(r)
        SparseAccelerator.copy!(z, r)
        blas1_time += time()

        trsv_time -= time()
        #Base.SparseMatrix.fwdTriSolve!(L, z)
        SparseAccelerator.fwdTriSolve!(L, z, __fknob_8201)
        trsv_time += time()

        SparseAccelerator.reordering(
            __fknob_8201, 
            reordering_status, 
            A, SparseAccelerator.COL_PERM, SparseAccelerator.ROW_INV_PERM,
            U, SparseAccelerator.COL_PERM, SparseAccelerator.ROW_INV_PERM, 
            :__delimitor__,
            r, SparseAccelerator.ROW_PERM,
            x, SparseAccelerator.COL_PERM,
            p, SparseAccelerator.COL_PERM
        )

        trsv_time -= time()
        #Base.SparseMatrix.bwdTriSolve!(U, z)
        SparseAccelerator.bwdTriSolve!(U, z, __fknob_8221)
        trsv_time += time()

        blas1_time -= time()
        #rz = dot(r, z)
        rz = SparseAccelerator.dot(r,z)
        beta = rz/old_rz
        #p = z + beta * p
        SparseAccelerator.WAXPBY!(p,1,z,beta,p)
        blas1_time += time()

        k += 1
    end

    SparseAccelerator.reverse_reordering(
        reordering_status, 
        :__delimitor__, 
        x, SparseAccelerator.COL_PERM
    )

    (SparseAccelerator.delete_function_knob)(__fknob_8221)
    (SparseAccelerator.delete_function_knob)(__fknob_8201)
    (SparseAccelerator.delete_matrix_knob)(__mknobL)

    total_time = time() - total_time
    println("total = $(total_time)s trsv_time = $(trsv_time)s ($((12.*(nnz(L) + nnz(U)) + 2.*8*(size(L, 1) + size(L, 2)))*k/trsv_time/1e9) gbps) spmv_time = $(spmv_time)s ($((12.*nnz(A) + 8.*(size(A, 1) + size(A, 2)))*(k + 1)/spmv_time/1e9) gbps) blas1_time = $blas1_time reorder_time = $reorder_time")

    return x, k, rel_err
end

print_sum = false
if length(ARGS) == 0
    m = 1000
    A = generate_symmetric_nonzerodiagonal_sparse_matrix(m)
elseif length(ARGS) == 1
    # This is for performance testing's purpose
    A = matrix_market_read(ARGS[1], true, true)
else
    # This is to for regression tests' purpose, which needs sum to be printed.
    print_sum = true
    A         = matrix_market_read(ARGS[2], true, true)
end
m       = size(A, 1)
x       = zeros(Float64, m)
b       = ones(Float64, m)
tol     = 1e-7
maxiter = 20000

x, k, rel_err = pcg_symgs(x, A, b, tol, maxiter)
x       = zeros(Float64, m)
println("Original: ")
x, k, rel_err = pcg_symgs(x, A, b, tol, maxiter)
if print_sum
    println("\tOriginal sum of x=", sum(x))
end
println("\tOriginal k=", k)
println("\tOriginal rel_err=", rel_err)

x, k, rel_err = pcg_symgs_with_context_opt_without_reordering(x, A, b, tol, maxiter)
println("\nWith manual context-sensitive optimization without reordering: ")
x       = zeros(Float64, m)
x, k, rel_err = pcg_symgs_with_context_opt_without_reordering(x, A, b, tol, maxiter)
if print_sum
    println("\tManual_context_no_reorder sum of x=", sum(x))
end
println("\tManual_context_no_reorder k=", k)
println("\tManual_context_no_reorder rel_err=", rel_err)

A2 = copy(A) # workaround that we change A in-place
x, k, rel_err = pcg_symgs_with_context_opt(x, A2, b, tol, maxiter)
println("\nWith manual context-sensitive optimization: ")
x       = zeros(Float64, m)
x, k, rel_err = pcg_symgs_with_context_opt(x, A, b, tol, maxiter)
if print_sum
    println("\tManual_context sum of x=", sum(x))
end
println("\tManual_context k=", k)
println("\tManual_context rel_err=", rel_err)
