#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

tar -zxf ghttpd-1.4-4.tar.gz
patch --directory=ghttpd-1.4-4 --strip=1 < ghttpd.patch
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
cd ghttpd-1.4-4
make 

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp ghttpd ghttpd.conf ../work; cd ../work 
extract-bc ghttpd
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so ghttpd.bc -emit-llvm -c -o ghttpd.bc 
$VIPER/BranchForcer/afl-clang-fast-flip ghttpd.bc -o ghttpd_flip -lc
$VIPER/BranchForcer/afl-clang-fast-rate ghttpd.bc -o ghttpd_rate -lc

# -------------------- prepare tools and environments --------------------------

cp ../httpreq.py .
mkdir cgi-bin && echo " " > cgi-bin/hello
bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./ghttpd_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

mkdir corpus; 
echo " " > corpus/testcase

# -------------------- do branch flipping --------------------------------------

python3 httpreq.py &
sudo $VIPER/BranchForcer/afl-fuzz -t 3000+ -m none -i corpus -o output -- ./ghttpd_flip
rm wget-log*
sudo chown -R $USER output 

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./ghttpd.bc ./dot/temp.dot br -- ./ghttpd_rate
# assess arguments of triggered syscalls
python3 auto_rator.py ./ghttpd.bc ./dot/temp.dot arg -- ./ghttpd_rate

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=190 SYSCALL=mprotect TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
python3 httpreq.py &
./ghttpd_rate
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator ghttpd.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg ghttpd.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot