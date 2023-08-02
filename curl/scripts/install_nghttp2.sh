#!/bin/bash

# If any commands fail, fail the script immediately.
set -ex

SRCDIR=$1
INSTALLDIR=$2

export CFLAGS="-g -O0" CXXFLAGS="-g -O0"
if [[ ! -d ${INSTALLDIR} ]]
then
  # Make an install target directory.
  mkdir ${INSTALLDIR}
fi

pushd ${SRCDIR}

# Build the library.
libtoolize
autoreconf -i -I /usr/share/aclocal/
./configure --prefix=${INSTALLDIR} \
            --disable-shared \
            --enable-static \
            --disable-threads --enable-lib-only

make V=1
make install

popd
