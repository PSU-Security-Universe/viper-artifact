#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

git clone https://github.com/jasper-software/jasper.git
cd jasper
git checkout version-4.0.0
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
mkdir static_build && cd static_build
cmake -DJAS_ENABLE_SHARED=false -DJAS_ENABLE_DOC=false ..
make

# -------------------- build flip and rate binaries ----------------------------

cd ..; mkdir ../work; cp static_build/src/app/jasper ../work; cd ../work 
extract-bc jasper
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so jasper.bc -emit-llvm -c -o jasper.bc 
$VIPER/BranchForcer/afl-clang-fast-flip jasper.bc -o jasper_flip -lz -lm -lpthread -ljpeg
$VIPER/BranchForcer/afl-clang-fast-rate jasper.bc -o jasper_rate -lz -lm -lpthread -ljpeg

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./jasper_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./jasper_flip -f @@ -F test.jp2 -T jp2

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./jasper.bc ./dot/temp.dot br -- ./jasper_rate -f @@ -F test.jp2 -T jp2
# assess arguments of triggered syscalls
python3 auto_rator.py ./jasper.bc ./dot/temp.dot arg -- ./jasper_rate -f @@ -F test.jp2 -T jp2

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=1277 SYSCALL=unlink TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./jasper_rate -f $TESTCASE -F test.jp2 -T jp2 
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator jasper.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg jasper.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot