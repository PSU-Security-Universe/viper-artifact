#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

git clone https://github.com/marado/netkit-telnet
cd netkit-telnet/netkit-telnet-0.17
git checkout 3f35287
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
./configure 
make

# -------------------- build flip and rate binaries ----------------------------

cd ..; mkdir ../work; cp netkit-telnet-0.17/telnet/telnet ../work; cd ../work 
extract-bc telnet
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so telnet.bc -emit-llvm -c -o telnet.bc 
$VIPER/BranchForcer/afl-clang-fast-flip telnet.bc -o telnet_flip -lutil -lncurses -ltinfo -lstdc++ -lm -lgcc_s -lc -ldl
$VIPER/BranchForcer/afl-clang-fast-rate telnet.bc -o telnet_rate -lutil -lncurses -ltinfo -lstdc++ -lm -lgcc_s -lc -ldl

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./telnet_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

sudo apt-get install -y libini-config-dev libseccomp-dev
git clone https://github.com/zardus/preeny
cd preeny
cmake -B build .
cmake --build build
cd ..

# start a local telnetd server
sudo apt-get install -y openbsd-inetd telnetd
netstat -a | grep telnet

LD_PRELOAD=./preeny/build/lib/libdesock.so $VIPER/BranchForcer/afl-fuzz -i corpus -o output ./telnet_flip 127.0.0.1

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./telnet.bc ./dot/temp.dot br -- ./telnet_rate 127.0.0.1
# assess arguments of triggered syscalls
python3 auto_rator.py ./telnet.bc ./dot/temp.dot arg -- ./telnet_rate 127.0.0.1

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=2512 SYSCALL=execve TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./telnet_rate 127.0.0.1 < $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator telnet.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg telnet.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot