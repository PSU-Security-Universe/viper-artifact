#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

wget http://prdownloads.sourceforge.net/nullhttpd/nullhttpd-0.5.1.tar.gz
tar zxf nullhttpd-0.5.1.tar.gz
patch --directory=nullhttpd-0.5.1 --strip=1 < nullhttpd.patch
cd nullhttpd-0.5.1/src
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
make

# -------------------- build flip and rate binaries ----------------------------

cd ../httpd/bin
extract-bc httpd
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so httpd.bc -emit-llvm -c -o httpd.bc 
$VIPER/BranchForcer/afl-clang-fast-flip httpd.bc -o httpd_flip -lpthread
$VIPER/BranchForcer/afl-clang-fast-rate httpd.bc -o httpd_rate -lpthread

# -------------------- prepare tools and environments --------------------------

cp ../../../httpreq.py .
bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./httpd_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

python3 httpreq.py &
sudo $VIPER/BranchForcer/afl-fuzz -t 2000+ -a 10 -m none -i corpus -o output -- ./httpd_flip
rm wget-log*
sudo chown -R $USER output 

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./httpd.bc ./dot/temp.dot br -- ./httpd_rate
# assess arguments of triggered syscalls
python3 auto_rator.py ./httpd.bc ./dot/temp.dot arg -- ./httpd_rate

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=165 SYSCALL=execve TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
python3 httpreq.py &
./httpd_rate
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator httpd.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg httpd.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot