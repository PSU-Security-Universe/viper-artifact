#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

unzip orzhttpd.zip 
patch --directory=orzhttpd --strip=1 < orzhttpd.patch
cd orzhttpd/trunk
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
make linux

# -------------------- build flip and rate binaries ----------------------------

cd ..; mkdir ../work; cp trunk/orzhttpd ../work; cd ../work 
extract-bc orzhttpd
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so orzhttpd.bc -emit-llvm -c -o orzhttpd.bc 
$VIPER/BranchForcer/afl-clang-fast-flip orzhttpd.bc -o orzhttpd_flip -levent -lexpat -lssl -lc -lpthread -lcrypto -ldl
$VIPER/BranchForcer/afl-clang-fast-rate orzhttpd.bc -o orzhttpd_rate -levent -lexpat -lssl -lc -lpthread -lcrypto -ldl

# -------------------- prepare tools and environments --------------------------

cp ../httpreq.py ../config.xml.sample .
bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./orzhttpd_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

mkdir corpus; 
echo " " > corpus/testcase

# -------------------- do branch flipping --------------------------------------

python3 httpreq.py &
sudo $VIPER/BranchForcer/afl-fuzz -t 3000+ -a 10 -m none -i corpus -o output -- ./orzhttpd_flip -D -f config.xml.sample
rm wget-log*
sudo chown -R $USER output 

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./orzhttpd.bc ./dot/temp.dot br -- ./orzhttpd_rate
# assess arguments of triggered syscalls
python3 auto_rator.py ./orzhttpd.bc ./dot/temp.dot arg -- ./orzhttpd_rate

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=190 SYSCALL=mprotect TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
python3 httpreq.py &
./orzhttpd_rate -D -f config.xml.sample
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator orzhttpd.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg orzhttpd.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot