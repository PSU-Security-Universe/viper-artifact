#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

wget https://www.sentex.ca/\~mwandel/jhead/jhead-3.04.tar.gz
tar zxf jhead-3.04.tar.gz; rm jhead-3.04.tar.gz;
cd jhead-3.04
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
make

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp jhead ../work; cd ../work 
extract-bc jhead
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so jhead.bc -emit-llvm -c -o jhead.bc 
$VIPER/BranchForcer/afl-clang-fast-flip jhead.bc -o jhead_flip -lm
$VIPER/BranchForcer/afl-clang-fast-rate jhead.bc -o jhead_rate -lm

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./jhead_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

python3 rec_ori_files.py
$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./jhead_flip @@
python3 rm_gen_files.py

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./jhead.bc ./dot/temp.dot br -- ./jhead_rate @@
# assess arguments of triggered syscalls
python3 auto_rator.py ./jhead.bc ./dot/temp.dot arg -- ./jhead_rate @@

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=123 SYSCALL=unlink TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./jhead_rate $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator jhead.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg jhead.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot
