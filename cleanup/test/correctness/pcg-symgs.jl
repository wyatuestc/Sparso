include("utils.jl")

#Check that matrix is square
function chksquare(A::AbstractMatrix)
    m,n = size(A)
    m == n || throw(DimensionMismatch("matrix is not square"))
    m
end

function fwdTriSolve!(A::SparseMatrixCSC, B::AbstractVecOrMat)
# forward substitution for CSC matrices
    n = length(B)
    if isa(B, Vector)
        nrowB = n
        ncolB = 1
    else
        nrowB, ncolB = size(B)
    end
    ncol = chksquare(A)
    if nrowB != ncol
        throw(DimensionMismatch("A is $(ncol)X$(ncol) and B has length $(n)"))
    end

    aa = A.nzval
    ja = A.rowval
    ia = A.colptr

    joff = 0
    for k = 1:ncolB
        for j = 1:(nrowB-1)
            jb = joff + j
            i1 = ia[j]
            i2 = ia[j+1]-1
            B[jb] /= aa[i1]
            bj = B[jb]
            for i = i1+1:i2
                B[joff+ja[i]] -= bj*aa[i]
            end
        end
        joff += nrowB
        B[joff] /= aa[end]
    end
    return B
end

function bwdTriSolve!(A::SparseMatrixCSC, B::AbstractVecOrMat)
# backward substitution for CSC matrices
    n = length(B)
    if isa(B, Vector)
        nrowB = n
        ncolB = 1
    else
        nrowB, ncolB = size(B)
    end
    ncol = chksquare(A)
    if nrowB != ncol throw(DimensionMismatch("A is $(ncol)X$(ncol) and B has length $(n)")) end

    aa = A.nzval
    ja = A.rowval
    ia = A.colptr

    joff = 0
    for k = 1:ncolB
        for j = nrowB:-1:2
            jb = joff + j
            i1 = ia[j]
            i2 = ia[j+1]-1
            B[jb] /= aa[i2]
            bj = B[jb]
            for i = i2-1:-1:i1
                B[joff+ja[i]] -= bj*aa[i]
            end
        end
        B[joff+1] /= aa[1]
        joff += nrowB
    end
   return B
end

function pcg_symgs(x, A, b, tol, maxiter)
    L = tril(A)
    U = spdiagm(1./diag(A))*triu(A)
    M = L*U
    r = b - A * x
    normr0 = norm(r)
    rel_err = 1

    z = copy(r)
    fwdTriSolve!(L, z)
    bwdTriSolve!(U, z)

    p = copy(z) #NOTE: do not write "p=z"! That would make p and z aliased (the same variable)
    rz = dot(r, z)
    k = 1
    time1 = time()
    while k <= maxiter
        old_rz = rz
        Ap = A*p # Ap = SparseAccelerator.SpMV(A, p) # This takes most time. Compiler can reorder A to make faster
        alpha = old_rz / dot(p, Ap)
        x += alpha * p
        r -= alpha * Ap
        rel_err = norm(r)/normr0
        if rel_err < tol 
            break
        end

        z = copy(r)
        fwdTriSolve!(L, z)
          # Could have written as z=L\z if \ is specialized for triangular
        bwdTriSolve!(U, z)
          # Could have wrriten as z=U\z if \ is specialized for triangular

        rz = dot(r, z)
        beta = rz/old_rz
        p = z + beta * p
        k += 1
    end
    return x, k, rel_err
end


m = 10
A = generate_symmetric_sparse_matrix(m)
x = repmat([1/m], m)
b   = ones(Float64, m)
tol = 1e-10
maxiter = 1000