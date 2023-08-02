#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

git clone --depth 1 --branch openssl-3.0.7 https://github.com/openssl/openssl.git
cd openssl
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
./config --debug -DPEDANTIC -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION no-shared enable-tls1_3 enable-rc5 enable-md2 enable-ec_nistp_64_gcc_128 enable-ssl3 enable-ssl3-method enable-nextprotoneg enable-weak-ssl-ciphers $CFLAGS -fno-sanitize=alignment
make -j$(nproc) LDCMD="$CXX $CXXFLAGS"

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp fuzz/asn1-test ../work; cd ../work 
extract-bc asn1-test
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so asn1-test.bc -emit-llvm -c -o asn1-test.bc 
$VIPER/BranchForcer/afl-clang-fast-flip asn1-test.bc -o asn1-test_flip -lpthread -lz -lm -ldl -lreadline ../openssl/libcrypto.a
$VIPER/BranchForcer/afl-clang-fast-rate asn1-test.bc -o asn1-test_rate -lpthread -lz -lm -ldl -lreadline ../openssl/libcrypto.a

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./asn1-test_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./asn1-test_flip @@

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./asn1-test.bc ./dot/temp.dot br -- ./asn1-test_rate
# assess arguments of triggered syscalls
python3 auto_rator.py ./asn1-test.bc ./dot/temp.dot arg -- ./asn1-test_rate

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=2512 SYSCALL=execve TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./asn1-test_rate $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator asn1-test.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg asn1-test.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot