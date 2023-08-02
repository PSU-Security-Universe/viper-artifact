#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

wget https://github.com/libarchive/libarchive/releases/download/v3.4.3/libarchive-3.4.3.tar.xz
git clone https://git.savannah.nongnu.org/git/freetype/freeftfuzzertype2.git
cd freetype2
git checkout cd02d35
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
mkdir build && cd build
cmake .. -DWITH_HarfBuzz=OFF -DWITH_ZLIB=OFF -DWITH_BZip2=OFF -DWITH_PNG=OFF
make 

cd ..
cp ../ftfuzzer.cc src/tools/ftfuzzer/ftfuzzer.cc
$CXX $CXXFLAGS -std=c++11 -I include -I . src/tools/ftfuzzer/ftfuzzer.cc \
    build/libfreetype.a $FUZZER_LIB -L /usr/local/lib -larchive -o ftfuzzer

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp ftfuzzer ../work; cd ../work 
extract-bc ftfuzzer
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so ftfuzzer.bc -emit-llvm -c -o ftfuzzer.bc 
$VIPER/BranchForcer/afl-clang-fast-flip++ ftfuzzer.bc -o ftfuzzer_flip -larchive
$VIPER/BranchForcer/afl-clang-fast-rate++ ftfuzzer.bc -o ftfuzzer_rate -larchive

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./ftfuzzer_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./ftfuzzer_flip @@

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./ftfuzzer.bc ./dot/temp.dot br -- ./ftfuzzer_rate
# assess arguments of triggered syscalls
python3 auto_rator.py ./ftfuzzer.bc ./dot/temp.dot arg -- ./ftfuzzer_rate

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=2512 SYSCALL=execve TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./ftfuzzer_rate $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator ftfuzzer.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg ftfuzzer.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot