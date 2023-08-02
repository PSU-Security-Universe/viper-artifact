#!/bin/bash 

# -------------------- build project with wllvm --------------------------------

git clone https://github.com/curl/curl-fuzzer curl_fuzzer
git -C curl_fuzzer checkout dd486c1e5910e722e43c451d4de928ac80f5967d
git clone https://github.com/curl/curl.git
git -C curl checkout 97f7f66
sudo bash curl_fuzzer/scripts/ossfuzzdeps.sh
sudo apt install -y libidn2-dev
cd curl_fuzzer
export SRC=$PWD
export CC=wllvm CXX=wllvm++ LLVM_COMPILER=clang CFLAGS="-g -O0" CXXFLAGS="-g -O0"
export BUILD_ROOT=$PWD
SCRIPTDIR=${BUILD_ROOT}/scripts
. ${SCRIPTDIR}/fuzz_targets

ZLIBDIR=$SRC/zlib
OPENSSLDIR=$SRC/openssl
NGHTTPDIR=$SRC/nghttp2
export MAKEFLAGS=" V=1 -j$(nproc)"
export INSTALLDIR=$SRC/curl_install

cp ../scripts/* ./scripts/

# Install zlib
${SCRIPTDIR}/handle_x.sh zlib ${ZLIBDIR} ${INSTALLDIR} || exit 1
# Install openssl
export OPENSSLFLAGS="-fno-sanitize=alignment"
${SCRIPTDIR}/handle_x.sh openssl ${OPENSSLDIR} ${INSTALLDIR} || exit 1
# Install nghttp2
${SCRIPTDIR}/handle_x.sh nghttp2 ${NGHTTPDIR} ${INSTALLDIR} || exit 1
# Compile curl
${SCRIPTDIR}/install_curl.sh $SRC/../curl ${INSTALLDIR}
# Build the fuzzers.
${BUILD_ROOT}/buildconf
CFLAGS="-g -O0" CXXFLAGS="-g -O0" CPPFLAGS=" -g -O0 -DNGHTTP2_STATICLIB" ${BUILD_ROOT}/configure --enable-static
make || true
make libstandaloneengine.a
make 
make check
wllvm -g -O0 -I ./curl_install/include -I ./curl_install/utfuzzer -DFUZZ_PROTOCOLS_HTTP -o curl_fuzzer_http  curl_fuzzer.cc ./curl_install/lib/libcurl.a ./curl_install/lib/libnghttp2.a ./curl_install/lib/libssl.a  ./curl_install/lib/libcrypto.a standalone_fuzz_target_runner.cc  curl_fuzzer_callback.cc  curl_fuzzer_tlv.cc  -lm -ldl -lpthread -lldap -llber -lidn2 -lz -lbrotlidec

# -------------------- build flip and rate binaries ----------------------------

mkdir ../work; cp curl_fuzzer_http ../work; cd ../work 
extract-bc curl_fuzzer_http
clang -Xclang -load -Xclang $VIPER/tools/splitAfterCall/splitAfterCall.so curl_fuzzer_http.bc -emit-llvm -c -o curl_fuzzer_http.bc 
$VIPER/BranchForcer/afl-clang-fast-flip curl_fuzzer_http.bc -o curl_fuzzer_http_flip -lm -ldl -lpthread -lldap -llber -lidn2 -lz -lbrotlidec -lm -ldl -lpthread -lldap -llber -lidn2 -lz ../curl_fuzzer/curl_install/lib/libssl.a ../curl_fuzzer/curl_install/lib/libcrypto.a
$VIPER/BranchForcer/afl-clang-fast-rate curl_fuzzer_http.bc -o curl_fuzzer_http_rate -lm -ldl -lpthread -lldap -llber -lidn2 -lz -lbrotlidec -lm -ldl -lpthread -lldap -llber -lidn2 -lz ../curl_fuzzer/curl_install/lib/libssl.a ../curl_fuzzer/curl_install/lib/libcrypto.a

# -------------------- prepare tools and environments --------------------------

bash $VIPER/tools/copy_tools.sh $VIPER .
objdump -d ./curl_fuzzer_http_rate | grep ">:" > ./log/func_map

# -------------------- put your corpus here ------------------------------------

# NOTE: put your corpus for next step!
mkdir corpus; 
# cp <your testcases> corpus/

# -------------------- do branch flipping --------------------------------------

$VIPER/BranchForcer/afl-fuzz -t 1000+ -a 10 -m none -i corpus -o output -- ./curl_fuzzer_http_flip @@

# -------------------- corruptibility assessment (auto) ------------------------

# assess syscall-guard variables
python3 auto_rator.py ./curl_fuzzer_http.bc ./dot/temp.dot br -- ./curl_fuzzer_http_rate @@
# assess arguments of triggered syscalls
python3 auto_rator.py ./curl_fuzzer_http.bc ./dot/temp.dot arg -- ./curl_fuzzer_http_rate @@

# -------------------- corruptibility assessment (manual) ----------------------

# set FLIP_BRANCH_ID, SYSCALL and TESTCASE according to `log/flip_result`
export FLIP_MODE=1 FLIP_BRANCH_ID=3378 SYSCALL=mprotect TESTCASE=corpus/testcase

# feed the program with testcase trigger this branch
./curl_fuzzer_http_rate $TESTCASE
python3 lib_func_map_gen.py

# analyze the corruptibility of syscall-guard branch
# 0 represents the number of printed BasicBlocks, normally set to 0
./rator curl_fuzzer_http.bc $FLIP_BRANCH_ID 0 ./dot/temp.dot

# analyze the corruptibility of syscall arguments
./rator_arg curl_fuzzer_http.bc $FLIP_BRANCH_ID $SYSCALL 0 ./dot/temp.dot