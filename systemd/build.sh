#!/bin/bash

# -------------------- build project with wllvm --------------------------------

git clone --depth 1 --branch v252 https://github.com/systemd/systemd
cd systemd
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
sudo apt-get install -y meson ninja-build gperf libcap-dev libmount-dev libp11-kit-dev libgcrypt20-dev
pip3 install jinja2
mkdir build
meson build -Dstatic-libsystemd=true -Dstatic-libudev=true -Dstandalone-binaries=true -Db_lundef=false
ninja -v -C build fuzzers
cd build
wllvm -o fuzz-link-parser fuzz-link-parser.p/src_udev_net_fuzz-link-parser.c.o fuzz-link-parser.p/src_fuzz_fuzz-main.c.o -Wl,--as-needed -Wl,--allow-shlib-undefined -Wl,--fatal-warnings -Wl,-z,now -Wl,-z,relro -fstack-protector -Wl,--warn-common -g -Wl,--start-group src/udev/libudev-core.a src/shared/libsystemd-shared-252.a src/basic/libbasic.a src/basic/libbasic-gcrypt.a src/libsystemd/libsystemd_static.a -Wl,--fatal-warnings -Wl,-z,now -Wl,-z,relro -fstack-protector -Wl,--warn-common -g src/basic/libbasic-compress.a  -pthread -lblkid -lcap -ldl -lmount -lssl -lcrypto -lp11-kit -lrt  -llzma -lselinux -lcrypt -lgcrypt -lm -lgcrypt  -pthread -lblkid -Wl,--end-group

# -------------------- build flip and rate binaries ----------------------------

cd ..; mkdir ../work; cp build/fuzz-link-parser ../work; cd ../work 
extract-bc fuzz-link-parser
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so fuzz-link-parser.bc -emit-llvm -c -o fuzz-link-parser.bc 
$VIPER/BranchForcer/afl-clang-fast-flip ./fuzz-link-parser.bc -o fuzz-link-parser_flip -pthread -lblkid -lcap -ldl -lmount -lssl -lcrypto -lp11-kit -lrt  -llzma -lselinux -lcrypt -lgcrypt -lm -lgcrypt  -pthread -lblkid 
$VIPER/BranchForcer/afl-clang-fast-rate ./fuzz-link-parser.bc -o fuzz-link-parser_rate -pthread -lblkid -lcap -ldl -lmount -lssl -lcrypto -lp11-kit -lrt  -llzma -lselinux -lcrypt -lgcrypt -lm -lgcrypt  -pthread -lblkid 

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./fuzz-link-parser_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./fuzz-link-parser_flip @@

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./fuzz-link-parser.bc ./dot/temp.dot br -- ./fuzz-link-parser_rate
# assess arguments of triggered syscalls
python3 auto_rator.py ./fuzz-link-parser.bc ./dot/temp.dot arg -- ./fuzz-link-parser_rate

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=9024 SYSCALL=mremap TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./fuzz-link-parser_rate $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator fuzz-link-parser.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg fuzz-link-parser.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot