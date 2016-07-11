Copyright (c) 2015, Intel Corporation

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Intel Corporation nor the names of its contributors
      may be used to endorse or promote products derived from this software
      without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Sparso
*Sparso* is a Julia package for speeding up iterative sparse matrix Julia programs.  
Sparso is part of the High Performance Scripting (HPS) project at Intel Labs.

Sparso detects sparse matrix operations and redirects where possible to an optimized 
implementation provided by the MKL or SpMP library.  Sparso does matrix property discovery in order to select the most performant version of a function on a matrix having certain properties.  It detects constancy of value
and/or structure of matrices, allowing different library calls to share an inspector
in the inspector/executor paradigm.  Finally, Sparso does analyses in order to 
 to reorder matrices for higher locality.

## Installation

### Hardware
There is no hard requirement, but a modern many-core machine with >=14 cores and >= 64G memory is preferred for performance testing. If you download all the data during performance testing, the hard disk needs >=30G free space.

### OS

Download and install Ubuntu 16.04 x86_64 desktop/server from http://www.ubuntu.com/download/desktop. 

### Julia 

Download Julia 0.4.6 (julia-2e358ce975) from http://julialang.org/downloads/. Choose Generic Linux Binary 64-bit.

	cd
    	tar xvzf julia-0.4.6-linux-x86_64.tar.gz
    	export PATH=~/julia-2e358ce975/bin:$PATH

### Parallel Studio

Download Linux Composer version for C++ from https://software.intel.com/en-us/intel-parallel-studio-xe. Choose "Linux" and "Professional 
Edition for Fortran and C++". Click "Download Free Trial". After submit the request, you will receive an email. Follow the download link there. Clik "+ Additional downloads, latest updates and prior versions". Choose 2016 Update 1 Eng/Jpn. Scroll down the screen to the bottom and click "Download Now" (NOT the "Download Now" button at the top of the page).

	cd
	tar xvzf parallel_studio_xe_2016_update1.tgz
 	cd parallel_studio_xe_2016_update1/
	./install_GUI.sh

Follow the instructions step by step to install everything.

	source /opt/intel/parallel_studio_xe_2016.1.056/psxevars.sh intel64

Depending on the path you have installed Parallel Studio, you may need change the above path to psxevars.sh.
	
### Install pcregrep

	sudo apt-get install pcregrep

### Install Sparso

	cd
	git clone https://github.com/IntelLabs/Sparso.git
	cd Sparso
	./scripts/setup.sh
	cp -fs ~/julia-2e358ce975/bin/julia deps/julia
	
## Experiment

### Correctness testing
	
	cd ~/Sparso/test/correctness/
	julia regression.jl all

A set of regression tests is run. All should pass. 

You can look at some simple tests there to see how Sparso works. Basically,
to accelerate your own iterative sparse matrix applications with Sparso,
add "using Sparso" to your Julia program and add "@acc" in front of calls to functions
that contain the iterative sparse matrix code you'd like to accelerate.


### Performance testing
	
	cd ~/Sparso/test/perf/
	./download_matrices.sh 300M # download matrices smaller than 300M
	export OMP_NUM_THREADS=*the number of physical cores of your machine*
	./run_all.sh

Note:

(1) Some matrices are huge, up to 5G. You can change the size option of 
download_matrices.sh to control which matrices to download. 

(2) For better performance, set OMP_NUM_THREADS as the number of physical cores, instead of virtual cores. 

(3) Execution can take many hours, depending on the matrices and the machine you choose.

(4) Ensure enough memory are available to Julia for large problem sizes.

(5) You can also test each benchmark separately by replacing the above ./run_all.sh with the following:

	cd cosp2;     ./cosp2.sh;     cd -
	cd ipm;       ./ipm.sh;       cd -
	cd lbfgs;     ./lbfgs.sh;     cd -
	cd pagerank;  ./pagerank.sh;  cd -
	cd pcg;       ./pcg.sh;       cd -
	cd adiabatic; ./adiabatic.sh; cd - 

(6) For each benchmark and input, the output contains testing result for the following configurations:

    julia-as-is: The benchmarks are run in the original Julia.

    baseline (call-repl): Auto replace all time-consuming linear algebra operations in Julia with calls to Intel MKL and SpMP library routines.

    +Matrix-properties: In addition to Call-repl, enable all the context-driven optimizations except collective reordering.

    +Reordering: In addition to +Matrix-properties, enable collective reordering as well. This is enabled in PCG, L-BFGS and PageRank.

For each output, there is a warm-up run and an evaluation run. Ignore the results of warm-up. Look for the evaluation results under "RUN:", which should be taken as the final results.

Enjoy!

## Resources

- **GitHub Issues:** <https://github.com/IntelLabs/Sparso/issues>
