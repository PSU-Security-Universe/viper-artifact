#!/bin/bash

# If any commands fail, fail the script immediately.
set -ex

SRCDIR=$1
INSTALLDIR=$2

if [[ ! -d ${INSTALLDIR} ]]
then
  # Make an install target directory.
  mkdir ${INSTALLDIR}
fi

pushd ${SRCDIR}

export CFLAGS="-g -O0" CXXFLAGS="-g -O0"
./configure --prefix=${INSTALLDIR} \
            --static

make V=1
make install

popd
