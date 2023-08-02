#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

git clone https://github.com/dellelce/wuftpd.git
patch --directory=wuftpd --strip=1 < wuftpd.patch
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
cd wuftpd
./build lnx

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp bin/ftpd ../work; cd ../work 
extract-bc ftpd
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so ftpd.bc -emit-llvm -c -o ftpd.bc
$VIPER/BranchForcer/afl-clang-fast-flip ftpd.bc -o ftpd_flip -lresolv -lcrypt -lc
$VIPER/BranchForcer/afl-clang-fast-rate ftpd.bc -o ftpd_rate -lresolv -lcrypt -lc

# -------------------- prepare tools and environments --------------------------

cp ../ftpreq.py .
mkdir test download 
echo "1" > test/1 
echo "1" > download/1 
bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./ftpd_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

mkdir corpus; 
echo " " > corpus/testcase

# -------------------- do branch flipping --------------------------------------

# you need to provide the correct password in ftpreq.py:36
#     right_pass = "<right_password>"
python3 ftpreq.py &
sudo $VIPER/BranchForcer/afl-fuzz -t 5000 -m none -i corpus -o output -- ./ftpd_flip -s 
sudo chown -R $USER output 

# -------------------- corruptibility assessment (auto) ------------------------

python3 ftpreq.py &
# assess syscall-guard variables
python3 auto_rator.py ./ftpd.bc ./dot/temp.dot br -- ./ftpd_rate -s
# assess arguments of triggered syscalls
python3 auto_rator.py ./ftpd.bc ./dot/temp.dot arg -- ./ftpd_rate -s

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=190 SYSCALL=mprotect TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
python3 ftpreq.py &
./ftpd_rate ftpreq.py
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator ftpd.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg ftpd.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot