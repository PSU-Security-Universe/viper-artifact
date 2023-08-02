#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

git clone https://github.com/kermitt2/pdfalto.git
cd pdfalto
git checkout 0.4
git submodule update --init --recursive
mkdir build
cd build
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
cmake ..
make -j$(nproc)

# -------------------- build flip and rate binaries ----------------------------

cd ..; mkdir ../work; cp build/pdfalto ../work; cd ../work 
extract-bc pdfalto
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so pdfalto.bc -emit-llvm -c -o pdfalto.bc 
$VIPER/BranchForcer/afl-clang-fast-flip++ pdfalto.bc -o pdfalto_flip  -ldl -lfontconfig -lm -lfreetype -lexpat -luuid -lpthread -lpng -lz -lxml2 ../pdfalto/libs/icu/linux/64/libicuuc.a ../pdfalto/libs/icu/linux/64/libicudata.a
$VIPER/BranchForcer/afl-clang-fast-rate++ pdfalto.bc -o pdfalto_rate  -ldl -lfontconfig -lm -lfreetype -lexpat -luuid -lpthread -lpng -lz -lxml2 ../pdfalto/libs/icu/linux/64/libicuuc.a ../pdfalto/libs/icu/linux/64/libicudata.a

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./pdfalto_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./pdfalto_flip @@

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py pdfalto.bc ./dot/temp.dot br -- ./pdfalto_rate @@
# assess arguments of triggered syscalls
python3 auto_rator.py pdfalto.bc ./dot/temp.dot arg -- ./pdfalto_rate @@

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=3655 SYSCALL=unlink TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./pdfalto_rate $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator pdfalto.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg pdfalto.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot