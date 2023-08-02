#!/bin/bash 

# ---------------------- #
# USE VIRTUAL MACHINE    #
# USE CLANG 10 / LLVM 10 #
# USE V8 BRANCH OF VIPER #
# WILL RELEASE SOON      #
# ---------------------- #

# -------------------- build project with wllvm --------------------------------

sudo apt install bison cdbs curl flex g++ git python vim pkg-config
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH=$(pwd)/depot_tools:${PATH}
fetch v8
cd v8
git reset --hard 8.5.188
gclient sync -D
patch --directory=v8 --strip=1 < v8.patch
export CC="wllvm" CXX="wllvm++" BUILD_CC="wllvm" BUILD_CXX="wllvm++" LLVM_COMPILER=clang AR=llvm-ar NM=llvm-nm BUILD_AR=llvm-ar BUILD_NM=llvm-nm
gn gen x64.debug
cp ../args.gn x64.debug
ninja -C x64.debug "v8_monolith" "d8"

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp x64.debug/d8 x64.debug/obj/libv8_monolith.a ../work; cd ../work 
extract-bc d8
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so d8.bc -emit-llvm -c -o d8.bc 
$VIPER/BranchForcer/afl-clang-fast-flip++ d8.bc -o d8_flip -lpthread -lm -latomic libv8_monolith.a
$VIPER/BranchForcer/afl-clang-fast-rate++ d8.bc -o d8_rate -lpthread -lm -latomic libv8_monolith.a

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./d8_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

mkdir corpus; 
echo 'print(os.system("date"))' > corpus/testcase

# -------------------- do branch flipping --------------------------------------

$VIPER/BranchForcer/afl-fuzz -t 1000+ -m none -i corpus -o output -- ./d8_flip --predictable @@ 

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./d8.bc ./dot/temp.dot br -- ./d8_rate --predictable @@
# assess arguments of triggered syscalls
python3 auto_rator.py ./d8.bc ./dot/temp.dot arg -- ./d8_rate --predictable @@

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=1159 SYSCALL=execve TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./d8_rate --predictable $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator d8.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg d8.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot