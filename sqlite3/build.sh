#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

git clone https://github.com/sqlite/sqlite.git
cd sqlite
git checkout version-3.40.1
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
./configure 
make

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp sqlite3 ../work; cd ../work 
extract-bc sqlite3
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so sqlite3.bc -emit-llvm -c -o sqlite3.bc 
$VIPER/BranchForcer/afl-clang-fast-flip sqlite3.bc -o sqlite3_flip -lpthread -lz -lm -ldl -lreadline
$VIPER/BranchForcer/afl-clang-fast-rate sqlite3.bc -o sqlite3_rate -lpthread -lz -lm -ldl -lreadline

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./sqlite3_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

python3 rec_ori_files.py
$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./sqlite3_flip
python3 rm_gen_files.py

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./sqlite3.bc ./dot/temp.dot br -- ./sqlite3_rate
# assess arguments of triggered syscalls
python3 auto_rator.py ./sqlite3.bc ./dot/temp.dot arg -- ./sqlite3_rate

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=2512 SYSCALL=execve TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./sqlite3_rate < $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator sqlite3.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg sqlite3.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot