#!/bin/bash

. /opt/intel/compiler/latest/bin/compilervars.sh # make sure you also did this before compiling libcsr.so 
# Use 1 socket, 1 HW thread per core
export OMP_NUM_THREADS=14
export KMP_AFFINITY=granularity=fine,compact,1

for i in `cat pagerank.lst`; do
  echo !!!!$i
  echo %%%%auto-without-reordering
  julia pagerank-without-reordering.jl ~/matrices/$i.mtx
  echo
  echo %%%%auto
  julia pagerank.jl ~/matrices/$i.mtx
  echo
  echo
done