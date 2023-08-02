#!/bin/bash 

# ------------------- #
# USE VIRTUAL MACHINE #
# ------------------- #

# -------------------- build project with wllvm --------------------------------

wget https://www.sudo.ws/dist/sudo-1.9.9.tar.gz
tar -xf sudo-1.9.9.tar.gz
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
patch --directory=sudo-1.9.9 --strip=1 < sudo.patch
cd sudo-1.9.9
cp ../argv-fuzz-inl.h src
sudo visudo #add new line
#    Defaults        secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
#   +Defaults        closefrom_override 

./configure --disable-shared
make

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp src/sudo ../work; cd ../work 
extract-bc sudo 
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so sudo.bc -emit-llvm -c -o sudo.bc 
$VIPER/BranchForcer/afl-clang-fast-flip sudo.bc -o sudo_flip -lutil -lcrypt -lssl -lcrypto -lpthread -lz -lc -ldl
$VIPER/BranchForcer/afl-clang-fast-rate sudo.bc -o sudo_rate -lutil -lcrypt -lssl -lcrypto -lpthread -lz -lc -ldl

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./sudo_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

sudo $VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./sudo_flip
sudo chown -R $USER output 

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./sudo.bc ./dot/temp.dot br -- ./sudo_rate
# assess arguments of triggered syscalls
python3 auto_rator.py ./sudo.bc ./dot/temp.dot arg -- ./sudo_rate

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=2512 SYSCALL=execve TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
sudo -E ./sudo_rate < $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator sudo.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg sudo.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot