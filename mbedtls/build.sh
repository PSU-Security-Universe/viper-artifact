#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

git clone --recursive https://github.com/Mbed-TLS/mbedtls.git
cd mbedtls
git checkout 10ada35
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
pip3 install -r scripts/basic.requirements.txt
perl scripts/config.pl set MBEDTLS_PLATFORM_TIME_ALT
mkdir build; cd build
cmake -DENABLE_TESTING=OFF ..
make -j$(nproc) all

# -------------------- build flip and rate binaries ----------------------------

cd ..; mkdir ../work; cp build/programs/fuzz/fuzz_dtlsclient ../work; cd ../work 
extract-bc fuzz_dtlsclient
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so fuzz_dtlsclient.bc -emit-llvm -c -o fuzz_dtlsclient.bc 
$VIPER/BranchForcer/afl-clang-fast-flip++ fuzz_dtlsclient.bc -o fuzz_dtlsclient_flip
$VIPER/BranchForcer/afl-clang-fast-rate++ fuzz_dtlsclient.bc -o fuzz_dtlsclient_rate

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./fuzz_dtlsclient_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./fuzz_dtlsclient_flip @@

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./fuzz_dtlsclient.bc ./dot/temp.dot br -- ./fuzz_dtlsclient_rate
# assess arguments of triggered syscalls
python3 auto_rator.py ./fuzz_dtlsclient.bc ./dot/temp.dot arg -- ./fuzz_dtlsclient_rate

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=2512 SYSCALL=execve TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./fuzz_dtlsclient_rate $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator fuzz_dtlsclient.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg fuzz_dtlsclient.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot