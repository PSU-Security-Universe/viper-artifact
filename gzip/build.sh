#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

git clone https://git.savannah.gnu.org/git/gzip.git
cd gzip
git checkout v1.12
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
./bootstrap
./configure
make

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp gzip ../work; cd ../work 
extract-bc gzip
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so gzip.bc -emit-llvm -c -o gzip.bc 
$VIPER/BranchForcer/afl-clang-fast-flip gzip.bc -o gzip_flip -lc
$VIPER/BranchForcer/afl-clang-fast-rate gzip.bc -o gzip_rate -lc

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./gzip_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./gzip_flip -c -d

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./gzip.bc ./dot/temp.dot br -- ./gzip_rate -c -d
# assess arguments of triggered syscalls
python3 auto_rator.py ./gzip.bc ./dot/temp.dot arg -- ./gzip_rate -c -d 

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=418 SYSCALL=unlink TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./gzip_rate -c -d < $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator gzip.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg gzip.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot