#!/bin/sh
#
# opus project ios build script
#
# usage 
#   ./build-libopus.sh
#
# options
#   -s [full path to openssl source directory]
#   -o [full path to openssl output directory]
#
# license
# The MIT License (MIT)
# 
# Copyright (c) 2016 Beachside Coders LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

# see http://stackoverflow.com/a/3915420/318790
function realpath { echo $(cd $(dirname "$1"); pwd)/$(basename "$1"); }
__FILE__=`realpath "$0"`
__DIR__=`dirname "${__FILE__}"`

# set -x

IOS_SDK_VERSION=`xcrun -sdk iphoneos --show-sdk-version`
DEVELOPER=`xcode-select -print-path`
IOS_DEPLOYMENT_VERSION="9.0"

# default
OPUS_SRC_DIR=${__DIR__}/opus
OPUS_OUTPUT_DIR=${__DIR__}/libopus

while getopts s:o: opt; do
  case $opt in
    s)
      OPUS_SRC_DIR=$OPTARG
      ;;
    o)
      OPUS_OUTPUT_DIR=$OPTARG
      ;;
  esac
done

OPUS_LOG_DIR=${OPUS_OUTPUT_DIR}/log
OPUS_INCLUDE_OUTPUT_DIR=${OPUS_OUTPUT_DIR}/include
OPUS_LIB_OUTPUT_DIR=${OPUS_OUTPUT_DIR}/lib
OPUS_BUILD_DIR=${__DIR__}/build


function prepare_build () {
  echo "Preparing build..."

  # remove old output
  if [ -d ${OPUS_LOG_DIR} ]; then
      rm -rf ${OPUS_LOG_DIR}
  fi

  if [ -d ${OPUS_INCLUDE_OUTPUT_DIR} ]; then
      rm -rf ${OPUS_INCLUDE_OUTPUT_DIR}
  fi

  if [ -d ${OPUS_LIB_OUTPUT_DIR} ]; then
      rm -rf ${OPUS_LIB_OUTPUT_DIR}
  fi

  if [ -d ${OPUS_BUILD_DIR} ]; then
      rm -rf ${OPUS_BUILD_DIR}
  fi

  # create output
  if [ ! -d ${OPUS_OUTPUT_DIR} ]; then
      mkdir ${OPUS_OUTPUT_DIR}
  fi

  # create log directory
  if [ ! -d ${OPUS_LOG_DIR} ]; then
      mkdir ${OPUS_LOG_DIR}
  fi

  # create build directory
  if [ ! -d ${OPUS_BUILD_DIR} ]; then
      mkdir ${OPUS_BUILD_DIR}
  fi
}

function build_arch () {
  ARCH=$1

  # setup and create source working directory
  OPUS_SRC_WORKING_DIR=${OPUS_BUILD_DIR}/opus-src
  rm -rf ${OPUS_SRC_WORKING_DIR}
  rsync -av --exclude=.git ${OPUS_SRC_DIR}/ ${OPUS_SRC_WORKING_DIR} > "${OPUS_LOG_DIR}/${ARCH}.log" 2>&1

  pushd . > /dev/null
  cd ${OPUS_SRC_WORKING_DIR}

  if [ ! -d ${OPUS_BUILD_DIR}/opus-${ARCH} ]; then
      mkdir ${OPUS_BUILD_DIR}/opus-${ARCH}
  fi

  if [ ! -e ./configure ]; then
    echo "Autogen ${ARCH}..."
    ./autogen.sh >> "${OPUS_LOG_DIR}/${ARCH}.log" 2>&1
  fi

  if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
    PLATFORM="iPhoneSimulator"
    EXTRA_CONFIG=""
  else
    PLATFORM="iPhoneOS"
    EXTRA_CONFIG="--host=arm-apple-darwin"
  fi

  EXTRA_CFLAGS="-Ofast -flto -g"
  EXTRA_LDFLAGS="-flto"

  ./configure \
    --prefix="${OPUS_BUILD_DIR}/opus-${ARCH}" \
    --enable-float-approx \
    --disable-shared \
    --enable-static \
    --with-pic \
    --disable-extra-programs \
    --disable-doc \
    ${EXTRA_CONFIG} \
    CFLAGS="$CFLAGS -arch ${ARCH} ${EXTRA_CFLAGS} -fPIE -miphoneos-version-min=${IOS_DEPLOYMENT_VERSION} -isysroot ${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${IOS_SDK_VERSION}.sdk" \
    LDFLAGS="$LDFLAGS ${EXTRA_LDFLAGS} -fPIE -miphoneos-version-min=${IOS_DEPLOYMENT_VERSION} " \
    >> "${OPUS_LOG_DIR}/${ARCH}.log" 2>&1
  
  echo "Building ${ARCH}..."

  make >> "${OPUS_LOG_DIR}/${ARCH}.log" 2>&1
  make install >> "${OPUS_LOG_DIR}/${ARCH}.log" 2>&1
#  make check

  popd > /dev/null

  rm -rf ${OPUS_SRC_WORKING_DIR}
}

function build_opus () {
  build_arch "armv7"
  build_arch "armv7s"
  build_arch "arm64"
  build_arch "i386"
  build_arch "x86_64"
}

function lipo_libs () {
  echo "Lipo libs..."

  if [ ! -d ${OPUS_LIB_OUTPUT_DIR} ]; then
      mkdir ${OPUS_LIB_OUTPUT_DIR}
  fi

  # libopus.a
  xcrun -sdk iphoneos lipo -arch armv7  ${OPUS_BUILD_DIR}/opus-armv7/lib/libopus.a \
                           -arch armv7s ${OPUS_BUILD_DIR}/opus-armv7s/lib/libopus.a \
                           -arch arm64  ${OPUS_BUILD_DIR}/opus-arm64/lib/libopus.a \
                           -arch i386   ${OPUS_BUILD_DIR}/opus-i386/lib/libopus.a \
                           -arch x86_64 ${OPUS_BUILD_DIR}/opus-x86_64/lib/libopus.a \
                           -create -output ${OPUS_LIB_OUTPUT_DIR}/libopus.a
}

function copy_include () {
  if [ ! -d ${OPUS_INCLUDE_OUTPUT_DIR} ]; then
    mkdir ${OPUS_INCLUDE_OUTPUT_DIR}
  fi

  cp -r ${OPUS_BUILD_DIR}/opus-arm64/include/opus ${OPUS_INCLUDE_OUTPUT_DIR}
}

function package_opus () {
  lipo_libs
  copy_include
}

function clean_up_build () {
  echo "Cleaning up..."

  if [ -d ${OPUS_BUILD_DIR} ]; then
      rm -rf ${OPUS_BUILD_DIR}
  fi
}

echo "Build opus..."
prepare_build
build_opus
package_opus
clean_up_build
echo "Done."

