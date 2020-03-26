#!/bin/bash

# Copyright 2018 Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Init script downloads or updates envoy and the go dependencies. Called from Makefile, which sets
# the needed environment variables.

set -o errexit
set -o nounset
set -o pipefail

export GO_TOP=${GO_TOP:-$(echo "${GOPATH}" | cut -d ':' -f1)}
export OUT_DIR=${OUT_DIR:-${GO_TOP}/out}

export GOPATH=${GOPATH:-$GO_TOP}
# Normally set by Makefile
export ISTIO_BIN=${ISTIO_BIN:-${GOPATH}/bin}

# Set the architecture. Matches logic in the Makefile.
export GOARCH=${GOARCH:-'amd64'}

# test scripts seem to like to run this script directly rather than use make
export ISTIO_OUT=${ISTIO_OUT:-${ISTIO_BIN}}
export ISTIO_OUT_LINUX=${ISTIO_OUT_LINUX:-${ISTIO_BIN}}

# Download Envoy debug and release binaries for Linux x86_64. They will be included in the
# docker images created by Dockerfile.proxyv2 and Dockerfile.proxytproxy.

# Gets the download command supported by the system (currently either curl or wget)
DOWNLOAD_COMMAND=""
function set_download_command () {
  # Try curl.
  if command -v curl > /dev/null; then
    if curl --version | grep Protocols  | grep https > /dev/null; then
      DOWNLOAD_COMMAND='curl -fLSs'
      return
    fi
    echo curl does not support https, will try wget for downloading files.
  else
    echo curl is not installed, will try wget for downloading files.
  fi

  # Try wget.
  if command -v wget > /dev/null; then
    DOWNLOAD_COMMAND='wget -qO -'
    return
  fi
  echo wget is not installed.

  echo Error: curl is not installed or does not support https, wget is not installed. \
       Cannot download envoy. Please install wget or add support of https to curl.
  exit 1
}

# Downloads and extract an Envoy binary if the artifact doesn't already exist.
# Params:
#   $1: The URL of the Envoy tar.gz to be downloaded.
#   $2: The full path of the output binary.
function download_envoy_if_necessary () {
  if [[ ! -f "$2" ]] ; then
    # Enter the output directory.
    mkdir -p "$(dirname "$2")"
    pushd "$(dirname "$2")"

    if [ $SIDECAR = "Envoy" ] ; then
      # Download and extract the binary to the output directory.
      echo "Downloading Envoy: ${DOWNLOAD_COMMAND} $1 to $2"
      time ${DOWNLOAD_COMMAND} --header "${AUTH_HEADER:-}" "$1" | tar xz

      # Copy the extracted binary to the output location
      cp usr/local/bin/envoy "$2"

      # Remove the extracted binary.
      rm -rf usr

      # Make a copy named just "envoy" in the same directory (overwrite if necessary).
      echo "Copying $2 to $(dirname "$2")/envoy"
      cp -f "$2" "$(dirname "$2")/envoy"
    fi
        
    if [ $SIDECAR = "MOSN" ] ; then
      # Download and extract the binary to the output directory.
      echo "Downloading MOSN: ${DOWNLOAD_COMMAND} $1 to $2"
      time ${DOWNLOAD_COMMAND} --header "${AUTH_HEADER:-}" "$1" > mosn

      # Copy the extracted binary to the output location
      cp mosn "$2"

      # Remove the extracted binary.
      rm -rf mosn

      # Make a copy named just "mosn" in the same directory (overwrite if necessary).
      echo "Copying $2 to $(dirname "$2")/mosn"
    fi
                
    popd
  fi
}



# Downloads WebAssembly based plugin if it doesn't already exist.
# Params:
#   $1: The URL of the WebAssembly file to be downloaded.
#   $2: The full path of the output file.
function download_wasm_if_necessary () {
  download_file_dir="$(dirname "$2")"
  download_file_name="$(basename "$1")"
  download_file_path="${download_file_dir}/${download_file_name}"
  if [[ ! -f "${download_file_path}" ]] ; then
    # Enter the output directory.
    mkdir -p "${download_file_dir}"
    pushd "${download_file_dir}"

    # Download the WebAssembly plugin files to the output directory.
    echo "Downloading WebAssembly file: ${DOWNLOAD_COMMAND} $1 to ${download_file_path}"
    if [[ ${DOWNLOAD_COMMAND} == curl* ]]; then
      time ${DOWNLOAD_COMMAND} --header "${AUTH_HEADER:-}" "$1" -o "${download_file_name}"
    elif [[ ${DOWNLOAD_COMMAND} == wget* ]]; then
      time ${DOWNLOAD_COMMAND} --header "${AUTH_HEADER:-}" "$1" -O "${download_file_name}"
    fi

    # Copy the webassembly file to the output location
    cp "${download_file_path}" "$2"
    popd
  fi
}

# Included for support on macOS.
function realpath () {
  python -c "import os; print(os.path.realpath('$1'))"
}

if [[ -z "${PROXY_REPO_SHA:-}" ]] ; then
  PROXY_REPO_SHA=$(grep PROXY_REPO_SHA istio.deps  -A 4 | grep lastStableSHA | cut -f 4 -d '"')
  export PROXY_REPO_SHA
fi


if [ $SIDECAR = "Envoy" ] ; then
  # Defines the base URL to download envoy from
  ISTIO_ENVOY_BASE_URL=${ISTIO_ENVOY_BASE_URL:-https://storage.googleapis.com/istio-build/proxy}

  # These variables are normally set by the Makefile.
  # OS-neutral vars. These currently only work for linux.
  ISTIO_ENVOY_VERSION=${ISTIO_ENVOY_VERSION:-${PROXY_REPO_SHA}}
  ISTIO_ENVOY_DEBUG_URL=${ISTIO_ENVOY_DEBUG_URL:-${ISTIO_ENVOY_BASE_URL}/envoy-debug-${ISTIO_ENVOY_LINUX_VERSION}.tar.gz}
  ISTIO_ENVOY_RELEASE_URL=${ISTIO_ENVOY_RELEASE_URL:-${ISTIO_ENVOY_BASE_URL}/envoy-alpha-${ISTIO_ENVOY_LINUX_VERSION}.tar.gz}

  # Envoy Linux vars. Normally set by the Makefile.
  ISTIO_ENVOY_LINUX_VERSION=${ISTIO_ENVOY_LINUX_VERSION:-${ISTIO_ENVOY_VERSION}}
  ISTIO_ENVOY_LINUX_DEBUG_URL=${ISTIO_ENVOY_LINUX_DEBUG_URL:-${ISTIO_ENVOY_DEBUG_URL}}
  ISTIO_ENVOY_LINUX_RELEASE_URL=${ISTIO_ENVOY_LINUX_RELEASE_URL:-${ISTIO_ENVOY_RELEASE_URL}}
  # Variables for the extracted debug/release Envoy artifacts.
  ISTIO_ENVOY_LINUX_DEBUG_DIR=${ISTIO_ENVOY_LINUX_DEBUG_DIR:-"${OUT_DIR}/linux_amd64/debug"}
  ISTIO_ENVOY_LINUX_DEBUG_NAME=${ISTIO_ENVOY_LINUX_DEBUG_NAME:-"envoy-debug-${ISTIO_ENVOY_LINUX_VERSION}"}
  ISTIO_ENVOY_LINUX_DEBUG_PATH=${ISTIO_ENVOY_LINUX_DEBUG_PATH:-"${ISTIO_ENVOY_LINUX_DEBUG_DIR}/${ISTIO_ENVOY_LINUX_DEBUG_NAME}"}
  ISTIO_ENVOY_LINUX_RELEASE_DIR=${ISTIO_ENVOY_LINUX_RELEASE_DIR:-"${OUT_DIR}/linux_amd64/release"}
  ISTIO_ENVOY_LINUX_RELEASE_NAME=${ISTIO_ENVOY_LINUX_RELEASE_NAME:-"envoy-${ISTIO_ENVOY_LINUX_VERSION}"}
  ISTIO_ENVOY_LINUX_RELEASE_PATH=${ISTIO_ENVOY_LINUX_RELEASE_PATH:-"${ISTIO_ENVOY_LINUX_RELEASE_DIR}/${ISTIO_ENVOY_LINUX_RELEASE_NAME}"}

  # Envoy macOS vars. Normally set by the makefile.
  # TODO Change url when official envoy release for macOS is available
  ISTIO_ENVOY_MACOS_VERSION=${ISTIO_ENVOY_MACOS_VERSION:-1.0.2}
  ISTIO_ENVOY_MACOS_RELEASE_URL=${ISTIO_ENVOY_MACOS_RELEASE_URL:-https://github.com/istio/proxy/releases/download/${ISTIO_ENVOY_MACOS_VERSION}/istio-proxy-${ISTIO_ENVOY_MACOS_VERSION}-macos.tar.gz}
  # Variables for the extracted debug/release Envoy artifacts.
  ISTIO_ENVOY_MACOS_RELEASE_DIR=${ISTIO_ENVOY_MACOS_RELEASE_DIR:-"${OUT_DIR}/darwin_amd64/release"}
  ISTIO_ENVOY_MACOS_RELEASE_NAME=${ISTIO_ENVOY_MACOS_RELEASE_NAME:-"envoy-${ISTIO_ENVOY_MACOS_VERSION}"}
  ISTIO_ENVOY_MACOS_RELEASE_PATH=${ISTIO_ENVOY_MACOS_RELEASE_PATH:-"${ISTIO_ENVOY_MACOS_RELEASE_DIR}/${ISTIO_ENVOY_MACOS_RELEASE_NAME}"}

  # Allow override with a local build of Envoy
  USE_LOCAL_PROXY=${USE_LOCAL_PROXY:-0}
  if [[ ${USE_LOCAL_PROXY} == 1 ]] ; then
    ISTIO_ENVOY_LOCAL_PATH=${ISTIO_ENVOY_LOCAL_PATH:-$(realpath "${ISTIO_GO}/../proxy/bazel-bin/src/envoy/envoy")}
    echo "Using istio-proxy image from local workspace: ${ISTIO_ENVOY_LOCAL_PATH}"
    if [[ ! -f "${ISTIO_ENVOY_LOCAL_PATH}" ]]; then
      echo "Error: missing istio-proxy from local workspace: ${ISTIO_ENVOY_LOCAL_PATH}. Check your build path."
      exit 1
    fi

    # Point the native paths to the local envoy build.
    if [[ "$LOCAL_OS" == "Darwin" ]]; then
      ISTIO_ENVOY_MACOS_RELEASE_PATH=${ISTIO_ENVOY_LOCAL_PATH}

      ISTIO_ENVOY_LINUX_LOCAL_PATH=${ISTIO_ENVOY_LINUX_LOCAL_PATH:-}
      if [[ -f "${ISTIO_ENVOY_LINUX_LOCAL_PATH}" ]] ; then
        ISTIO_ENVOY_LINUX_DEBUG_PATH=${ISTIO_ENVOY_LINUX_LOCAL_PATH}
        ISTIO_ENVOY_LINUX_RELEASE_PATH=${ISTIO_ENVOY_LINUX_LOCAL_PATH}
      else
        echo "Warning: The specified local macOS Envoy will not be included by Docker images. Set ISTIO_ENVOY_LINUX_LOCAL_PATH to specify a custom Linux build."
      fi
    else
      ISTIO_ENVOY_LINUX_DEBUG_PATH=${ISTIO_ENVOY_LOCAL_PATH}
      ISTIO_ENVOY_LINUX_RELEASE_PATH=${ISTIO_ENVOY_LOCAL_PATH}
    fi
  fi
fi

if [ $SIDECAR = "MOSN" ] ; then 
  # Defines the base URL to download mosn from
  ISTIO_MOSN_BASE_URL=${ISTIO_MOSN_BASE_URL:-https://github.com/mosn/mosn/releases/download/}
  
  # These variables are normally set by the Makefile.
  # OS-neutral vars. These currently only work for linux.
  ISTIO_MOSN_VERSION=${ISTIO_MOSN_VERSION:-${PROXY_REPO_SHA}}
  ISTIO_MOSN_DEBUG_URL=${ISTIO_MOSN_DEBUG_URL:-${ISTIO_MOSN_BASE_URL}/${ISTIO_MOSN_VERSION}/mosn}
  ISTIO_MOSN_RELEASE_URL=${ISTIO_MOSN_RELEASE_URL:-${ISTIO_MOSN_BASE_URL}/${ISTIO_MOSN_VERSION}/mosn}
  
  # MOSN Linux vars. Normally set by the Makefile.
  ISTIO_MOSN_LINUX_VERSION=${ISTIO_MOSN_LINUX_VERSION:-${ISTIO_MOSN_VERSION}}
  ISTIO_MOSN_LINUX_DEBUG_URL=${ISTIO_MOSN_LINUX_DEBUG_URL:-${ISTIO_MOSN_DEBUG_URL}}
  ISTIO_MOSN_LINUX_RELEASE_URL=${ISTIO_MOSN_LINUX_RELEASE_URL:-${ISTIO_MOSN_RELEASE_URL}}
  # Variables for the extracted debug/release MOSN artifacts.
  ISTIO_MOSN_LINUX_DEBUG_DIR=${ISTIO_MOSN_LINUX_DEBUG_DIR:-"${OUT_DIR}/linux_amd64/debug"}
  ISTIO_MOSN_LINUX_DEBUG_NAME=${ISTIO_MOSN_LINUX_DEBUG_NAME:-"mosn-debug-${ISTIO_MOSN_LINUX_VERSION}"}
  ISTIO_MOSN_LINUX_DEBUG_PATH=${ISTIO_MOSN_LINUX_DEBUG_PATH:-"${ISTIO_MOSN_LINUX_DEBUG_DIR}/${ISTIO_MOSN_LINUX_DEBUG_NAME}"}
  ISTIO_MOSN_LINUX_RELEASE_DIR=${ISTIO_MOSN_LINUX_RELEASE_DIR:-"${OUT_DIR}/linux_amd64/release"}
  ISTIO_MOSN_LINUX_RELEASE_NAME=${ISTIO_MOSN_LINUX_RELEASE_NAME:-"mosn-${ISTIO_MOSN_LINUX_VERSION}"}
  ISTIO_MOSN_LINUX_RELEASE_PATH=${ISTIO_MOSN_LINUX_RELEASE_PATH:-"${ISTIO_MOSN_LINUX_RELEASE_DIR}/${ISTIO_MOSN_LINUX_RELEASE_NAME}"}
  
  # MOSN macOS vars. Normally set by the makefile.
  # TODO Change url when official MOSN release for macOS is available
  ISTIO_MOSN_MACOS_VERSION=${ISTIO_MOSN_MACOS_VERSION:-"${ISTIO_MOSN_VERSION}"}
  ISTIO_MOSN_MACOS_RELEASE_URL=${ISTIO_MOSN_MACOS_RELEASE_URL:-https://github.com/mosn/mosn/releases/download/${ISTIO_MOSN_MACOS_VERSION}/mosn}
  # Variables for the extracted debug/release MOSN artifacts.
  ISTIO_MOSN_MACOS_RELEASE_DIR=${ISTIO_MOSN_MACOS_RELEASE_DIR:-"${OUT_DIR}//release"}
  ISTIO_MOSN_MACOS_RELEASE_NAME=${ISTIO_MOSN_MACOS_RELEASE_NAME:-"mosn-${ISTIO_MOSN_MACOS_VERSION}"}
  ISTIO_MOSN_MACOS_RELEASE_PATH=${ISTIO_MOSN_MACOS_RELEASE_PATH:-"${ISTIO_MOSN_MACOS_RELEASE_DIR}/${ISTIO_MOSN_MACOS_RELEASE_NAME}"}

fi 

mkdir -p "${ISTIO_OUT}"

# Set the value of DOWNLOAD_COMMAND (either curl or wget)
set_download_command

# FIX ME
download_envoy_if_necessary `eval echo '$ISTIO_'"${SIDECAR}"'_LINUX_DEBUG_URL'` `eval echo '$ISTIO_'"${SIDECAR}"'_LINUX_DEBUG_PATH'`

if [[ -n "${DEBUG_IMAGE:-}" ]]; then
  # Download and extract the Envoy linux debug binary.
  download_envoy_if_necessary `eval echo '$ISTIO_'"${SIDECAR}"'_LINUX_DEBUG_URL'` `eval echo '$ISTIO_'"${SIDECAR}"'_LINUX_DEBUG_PATH'`
else
  echo "Skipping envoy debug. Set DEBUG_IMAGE to download."
fi

# Download and extract the Envoy linux release binary.
download_envoy_if_necessary `eval echo '$ISTIO_'"${SIDECAR}"'_LINUX_RELEASE_URL'` `eval echo '$ISTIO_'"${SIDECAR}"'_LINUX_RELEASE_PATH'`

if [[ "$GOOS_LOCAL" == "darwin" ]]; then
  # Download and extract the Envoy macOS release binary
  download_envoy_if_necessary `eval echo '$ISTIO_'"${SIDECAR}"'_MACOS_RELEASE_URL'` `eval echo '$ISTIO_'"${SIDECAR}"'_MACOS_RELEASE_PATH'`
  ISTIO_SIDECAR_NATIVE_PATH=`eval echo '$ISTIO_'"${SIDECAR}"'_MACOS_RELEASE_PATH'`
else
  ISTIO_SIDECAR_NATIVE_PATH=`eval echo '$ISTIO_'"${SIDECAR}"'_LINUX_DEBUG_PATH'`
fi

# TODO Support Wasm for MOSN
if [ $SIDECAR = "Envoy" ] ; then
  # Donwload WebAssembly plugin files
  WASM_RELEASE_DIR=${ISTIO_ENVOY_LINUX_RELEASE_DIR}
  for plugin in stats metadata_exchange
  do
    FILTER_WASM_URL="${ISTIO_ENVOY_BASE_URL}/${plugin}-${ISTIO_ENVOY_VERSION}.wasm"
    download_wasm_if_necessary "${FILTER_WASM_URL}" "${WASM_RELEASE_DIR}"/"${plugin//_/-}"-filter.wasm
  done

  # Copy the envoy binary to ISTIO_OUT_LINUX if the local OS is not Linux
  if [[ "$GOOS_LOCAL" != "linux" ]]; then
     echo "Copying ${ISTIO_ENVOY_LINUX_RELEASE_PATH} to ${ISTIO_OUT_LINUX}/envoy"
     cp -f "${ISTIO_ENVOY_LINUX_RELEASE_PATH}" "${ISTIO_OUT_LINUX}/envoy"
  fi

  # Copy native envoy binary to ISTIO_OUT
  echo "Copying ${ISTIO_SIDECAR_NATIVE_PATH} to ${ISTIO_OUT}/envoy"
  cp -f "${ISTIO_SIDECAR_NATIVE_PATH}" "${ISTIO_OUT}/envoy"
fi

if [ $SIDECAR = "MOSN" ] ; then
  # Copy the envoy binary to ISTIO_OUT_LINUX if the local OS is not Linux
  if [[ "$GOOS_LOCAL" != "linux" ]]; then
     echo "Copying ${ISTIO_MOSN_LINUX_RELEASE_PATH} to ${ISTIO_OUT_LINUX}/mosn"
     cp -f "${ISTIO_MOSN_LINUX_RELEASE_PATH}" "${ISTIO_OUT_LINUX}/mosn"
  fi
  
  # Copy native mosn binary to ISTIO_OUT
  echo "Copying ${ISTIO_SIDECAR_NATIVE_PATH} to ${ISTIO_OUT}/mosn"
  cp -f "${ISTIO_SIDECAR_NATIVE_PATH}" "${ISTIO_OUT}/mosn"
fi

