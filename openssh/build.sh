#!/bin/bash 

# ----------------------- #
# USE VIRTUAL MACHINE     #
# USE SSH BRANCH OF VIPER #
# WILL RELEASE SOON       #
# ----------------------- #

# -------------------- build project with wllvm --------------------------------

git clone git://anongit.mindrot.org/openssh.git
cd openssh
git checkout 36b00d3
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
autoreconf -fiv
./configure
make
sudo make install

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp sshd ../work; cd ../work 
extract-bc sshd
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so sshd.bc -emit-llvm -c -o sshd.bc 
$VIPER/BranchForcer/afl-clang-fast-flip sshd.bc -o sshd_flip -lcrypt -ldl -lutil -lresolv -lcrypto -lz -lpthread
$VIPER/BranchForcer/afl-clang-fast-rate sshd.bc -o sshd_rate -lcrypt -ldl -lutil -lresolv -lcrypto -lz -lpthread

# -------------------- prepare tools and environments --------------------------

cp ../sshd_config ../login.py .
pip3 install pexpect timeout_decorator
bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./sshd_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

mkdir corpus; 
echo " " > corpus/testcase

# -------------------- do branch flipping --------------------------------------

# open a new terminal to execute login script
python3 login.py
# open another terminal to do branch flipping
sudo $VIPER/BranchForcer/afl-fuzz -t 10000+ -m none -i corpus -o output -- ./sshd_flip -d -e -r -f ./sshd_config

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./sshd.bc ./dot/temp.dot br -- ./sshd_rate
# assess arguments of triggered syscalls
python3 auto_rator.py ./sshd.bc ./dot/temp.dot arg -- ./sshd_rate

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=438 SYSCALL=execve TESTCASE=corpus/testcase

# open a new terminal to execute login script
python3 login.py
# open another terminal to execute openssh server
./sshd_rate -d -e -r -f ./sshd_config
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator sshd.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg sshd.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot