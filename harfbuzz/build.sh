#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

git clone https://github.com/harfbuzz/harfbuzz.git
cd harfbuzz
git checkout f73a87d9a
sudo apt-get install ragel libtool libtool-bin libfreetype6-dev libglib2.0-dev libcairo2-dev meson pkg-config gtk-doc-tools
libtoolize
./autogen.sh
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
./configure --enable-static --disable-shared --with-glib=no --with-cairo=no
cd ./src/hb-ucdn
CCLD="wllvm++ -g" make
cd ../../
make -C src fuzzing
cp ../hb-fuzzer.cc test/fuzzing/hb-fuzzer.cc
wllvm++ -g -std=c++11 -I src/ test/fuzzing/hb-fuzzer.cc  src/.libs/libharfbuzz-fuzzing.a -o ./hb-shape-fuzzer

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp hb-shape-fuzzer ../work; cd ../work 
extract-bc hb-shape-fuzzer
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so hb-shape-fuzzer.bc -emit-llvm -c -o hb-shape-fuzzer.bc 
$VIPER/BranchForcer/afl-clang-fast-flip hb-shape-fuzzer.bc -o hb-shape-fuzzer_flip -lm -lc -lstdc++
$VIPER/BranchForcer/afl-clang-fast-rate hb-shape-fuzzer.bc -o hb-shape-fuzzer_rate -lm -lc -lstdc++

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./hb-shape-fuzzer_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./hb-shape-fuzzer_flip @@

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./hb-shape-fuzzer.bc ./dot/temp.dot br -- ./hb-shape-fuzzer_rate @@
# assess arguments of triggered syscalls
python3 auto_rator.py ./hb-shape-fuzzer.bc ./dot/temp.dot arg -- ./hb-shape-fuzzer_rate @@

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=18 SYSCALL=mprotect TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./hb-shape-fuzzer_rate $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator hb-shape-fuzzer.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg hb-shape-fuzzer.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot
