function generate_symmetric_sparse_matrix(m)
    A = SparseMatrixCSC{Cdouble, Cint}(sprand(m, m, 0.1))
    
    # Make it symmetric
    for i = 1:m 
        for j = 1:m 
            if A[i, j] != 0.0
                A[j, i] = A[i, j]
            else
                A[i, j] = A[j, i] 
            end
        end 
    end
    
    return A
end

function check_symmetry(A)
    println("**** Checking symmetry")
    m = size(A, 1)
    for i = 1:m 
        for j = 1:m 
            if A[i, j] != A[j, i]
                println("Matrix is asymmetric!")
                println("A[", i, ",", j, "] != A[", j, ",", i, "]")
            end
        end
    end
    println("Done checking")
    flush(STDOUT::IO)
end
