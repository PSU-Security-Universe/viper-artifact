#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

sudo apt install -y build-essential libtool libpcre3 libpcre3-dev zlib1g-dev openssl
mkdir work
wget http://nginx.org/download/nginx-1.20.2.tar.gz
tar zxf nginx-1.20.2.tar.gz
patch --directory=nginx-1.20.2 --strip=1 < nginx.patch
cd nginx-1.20.2
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
./configure --prefix=../work
make 
make install

# -------------------- build flip and rate binaries ----------------------------

cd ../work/sbin
extract-bc nginx
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so nginx.bc -emit-llvm -c -o nginx.bc 
$VIPER/BranchForcer/afl-clang-fast-flip nginx.bc -o nginx_flip -ldl -lpthread -lcrypt -lpcre -lz
$VIPER/BranchForcer/afl-clang-fast-rate nginx.bc -o nginx_rate -ldl -lpthread -lcrypt -lpcre -lz

# -------------------- prepare tools and environments --------------------------

cp ../../nginx.conf ../../httpreq.py .
bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./nginx_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

mkdir corpus; 
echo " " > corpus/testcase

# -------------------- do branch flipping --------------------------------------

python3 httpreq.py &
$VIPER/BranchForcer/afl-fuzz -t 5000+ -m none -i corpus -o output -- ./nginx_flip -c ./nginx.conf

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./nginx.bc ./dot/temp.dot br -- ./nginx_rate -c ./nginx.conf
# assess arguments of triggered syscalls
python3 auto_rator.py ./nginx.bc ./dot/temp.dot arg -- ./nginx_rate -c ./nginx.conf

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=2512 SYSCALL=execve TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
python3 httpreq.py &
./nginx_rate -c ./nginx.conf
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator nginx.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg nginx.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot