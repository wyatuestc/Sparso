include("../../src/SparseAccelerator.jl")
using SparseAccelerator

set_options(SA_ENABLE, SA_VERBOSE, SA_USE_SPMP, SA_CONTEXT, SA_REORDER, SA_REPLACE_CALLS)

function pagerank2(A, p, r, d_inv, maxiter) # p: initial rank, r: damping factor
  set_matrix_property(Dict(
    :A => SA_SYMM_STRUCTURED | SA_SYMM_VALUED | SA_STRUCTURE_ONLY))

  bytes = maxiter*(nnz(A)*12 + size(A, 1)*3*8)

  p = copy(p)
  d_inv = copy(d_inv)
  Ap = zeros(size(A, 1))

  t = time()

  for i = 1:maxiter
    p = p.*d_inv
    Ap = (1-r)*A*p + r

    if i == maxiter
      p = p./d_inv
      err = norm(Ap - p)/norm(p)
      println("error = $err")
    end

    temp = Ap
    Ap = p
    p = temp
  end

  t = time() - t
  println("pagerank takes $t sec ($(bytes/t/1e9) gbps)")

  p
end

function pagerank2_call_replacement(A, p, r, d_inv, maxiter, do_print) # p: initial rank, r: damping factor
  bytes = maxiter*(nnz(A)*12 + size(A, 1)*3*8)
  A = copy(A)
  p = copy(p)
  d_inv = copy(d_inv)
  Ap = copy(p)

  t = time()
  reorder_time = 0.

  __mknobA = (SparseAccelerator.new_matrix_knob)(A, true, true, true, true, true, false)

  fknob_spmv = (SparseAccelerator.new_function_knob)()
  (SparseAccelerator.add_mknob_to_fknob)(__mknobA, fknob_spmv)

  for i = 1:maxiter
    #Ap = (1-r) *A * p + r
    SparseAccelerator.element_wise_multiply!(p, p, d_inv)
    SparseAccelerator.SpMV!(Ap, 1 - r, A, p, 0, p, r, fknob_spmv)
    if do_print && i == maxiter
      SparseAccelerator.element_wise_divide!(p, p, d_inv)
      err = norm(Ap - p)/norm(p)
      println("error = $err")
    end

    temp = Ap
    Ap = p
    p = temp
  end

  (SparseAccelerator.delete_matrix_knob)(__mknobA)
  (SparseAccelerator.delete_function_knob)(fknob_spmv)

  t = time() - t
  if do_print
    println("pagerank takes $t sec ($(bytes/t/1e9) gbps)")
  end

  p
end

function pagerank2_call_replacement_and_context_opt(A, p, r, d_inv, maxiter, do_print) # p: initial rank, r: damping factor
  bytes = maxiter*(nnz(A)*12 + size(A, 1)*3*8)
  A = copy(A)
  p = copy(p)
  d_inv = copy(d_inv)
  Ap = copy(p)

  t = time()
  reorder_time = 0.

  __mknobA = (SparseAccelerator.new_matrix_knob)(A, true, true, true, true, true, false)

  fknob_spmv = (SparseAccelerator.new_function_knob)()
  (SparseAccelerator.add_mknob_to_fknob)(__mknobA, fknob_spmv)

  (SparseAccelerator.set_reordering_decision_maker)(fknob_spmv)
  reordering_status = [false, C_NULL, C_NULL, C_NULL, C_NULL, reorder_time]

  for i = 1:maxiter
    #Ap = (1-r) *A * p + r
    SparseAccelerator.element_wise_multiply!(p, p, d_inv)
    SparseAccelerator.SpMV!(Ap, 1 - r, A, p, 0, p, r, fknob_spmv)
    SparseAccelerator.reordering(fknob_spmv, reordering_status, :__delimitor__, d_inv, SparseAccelerator.COL_PERM)
    if do_print && i == maxiter
      SparseAccelerator.element_wise_divide!(p, p, d_inv)
      err = norm(Ap - p)/norm(p)
      println("error = $err")
    end

    temp = Ap
    Ap = p
    p = temp
  end

  (SparseAccelerator.delete_matrix_knob)(__mknobA)
  (SparseAccelerator.delete_function_knob)(fknob_spmv)
  (SparseAccelerator.reverse_reordering)(reordering_status, :__delimitor__, p, SparseAccelerator.ROW_PERM)

  t = time() - t
  if do_print
    println("pagerank takes $t sec ($(bytes/t/1e9) gbps)")
  end

  p
end

A0 = matrix_market_read(ARGS[1], true, true)
A0 = spones(A0)

m = size(A0, 1)
p = repmat([1/m], m)
r = 0.15

d = max(convert(Array{eltype(A0),1}, vec(sum(A0, 2))), 1) # num of neighbors
A = scale(A0,1./d)

maxiter = 100
bytes = maxiter*(nnz(A)*4 + m*3*8)

d_inv = 1./d
x = pagerank2(A0, p, r, d_inv, maxiter)
println("\nOriginal2: ")
x = pagerank2(A0, p, r, d_inv, maxiter)
println("End original2.")

println("\nManual_call_replacement2:")
x = pagerank2_call_replacement(A0, p, r, d_inv, maxiter, false)

SparseAccelerator.reset_spmp_spmv_time()
SparseAccelerator.reset_knob_spmv_time()
x = pagerank2_call_replacement(A0, p, r, d_inv, maxiter, true)
t = SparseAccelerator.get_spmp_spmv_time()
println("time spent on spmp spmv $t sec ($(bytes/t/1e9) gbps)")
t = SparseAccelerator.get_knob_spmv_time()
println("time spent on knob spmv $t sec ($(bytes/t/1e9) gbps)")
println("End Manual_call_replacement2.")

println("\nManual_call_replacement_and_context_opt2:")
x = pagerank2_call_replacement_and_context_opt(A, p, r, d_inv, maxiter, false)

SparseAccelerator.reset_spmp_spmv_time()
SparseAccelerator.reset_knob_spmv_time()
#SparseAccelerator.set_knob_log_level(1)
x = pagerank2_call_replacement_and_context_opt(A0, p, r, d_inv, maxiter, true)
t = SparseAccelerator.get_spmp_spmv_time()
println("time spent on spmp spmv $t sec ($(bytes/t/1e9) gbps)")
t = SparseAccelerator.get_knob_spmv_time()
println("time spent on knob spmv $t sec ($(bytes/t/1e9) gbps)")

println("End Manual_call_replacement_and_context_opt2.")

# copy A since we change A in-place
#SparseAccelerator.set_knob_log_level(0)
A2 = copy(A0)
@acc x= pagerank2(A2, p, r, d_inv, maxiter)

println("\nAccelerated2: ")
SparseAccelerator.reset_spmp_spmv_time()
SparseAccelerator.reset_knob_spmv_time()
#SparseAccelerator.set_knob_log_level(1)
@acc x = pagerank2(A0, p, r, d_inv, maxiter)
t = SparseAccelerator.get_spmp_spmv_time()
println("time spent on spmp spmv $t sec ($(bytes/t/1e9) gbps)")
t = SparseAccelerator.get_knob_spmv_time()
println("time spent on knob spmv $t sec ($(bytes/t/1e9) gbps)")
println("End accelerated2.")
