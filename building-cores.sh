#!/bin/bash

# sing-box - building-cores
# https://sxlmnwb.nodex.one/sing-box/stable

TARGET="stable" # stable / unstable
WORKDIR="${HOME}/sxlmnwb/prebuilts"
OUTDIR="/var/www/sxlmnwb/sing-box/${TARGET}"
NDK_VERSION="r27c" # https://github.com/android/ndk/releases
LLVM_VERSION="19.1.7" # https://github.com/llvm/llvm-project/releases
NDK="${WORKDIR}/android-ndk-${NDK_VERSION}/toolchains/llvm/prebuilt/linux-x86_64/bin"
LLVM="${WORKDIR}/LLVM-${LLVM_VERSION}-Linux-X64/bin"
# LLVM="${WORKDIR}/sxlzptprjkt-clang"
CAF="${WORKDIR}/snapdragon-llvm/bin" # https://www.qualcomm.com/developer/software/snapdragon-llvm-compiler
TAGS="with_gvisor,with_dhcp,with_wireguard,with_reality_server,with_clash_api,with_quic,with_utls,with_ech"

# Create output dir
sudo mkdir -p "${OUTDIR}"

# Function to build.log
exec > >(sudo tee -i "${OUTDIR}/build.log")
exec 2>&1

# Function to check if Go is installed and meets minimum version requirements
check_go_version() {
  if ! command -v go &> /dev/null; then
    echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] Go is not found, please install Go at least version 1.2x.x / latest"
    exit 1
  fi

  GO_VERSION=$(go version | grep -oP "go[0-9]+\.[0-9]+")
  MIN_VERSION="go1.2"
  if [[ "$GO_VERSION" < "$MIN_VERSION" ]]; then
    echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] minimum version of Go is 1.2x.x, your current version: ${GO_VERSION}"
    exit 1
  fi
}

# Function to clean up before build
clean1() {
  sudo rm -f ${OUTDIR}/*.zip
}

# Function to set up NDK
setup_ndk() {
  if [ ! -d "${NDK}" ]; then
    echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [DEBUG] downloading android NDK ${NDK_VERSION}..."
    NDK_URL="https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
    echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [DEBUG] NDK URL - ${NDK_URL}"
    curl -L ${NDK_URL} > ${WORKDIR}/android-ndk-${NDK_VERSION}-linux.zip || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
    unzip ${WORKDIR}/android-ndk-${NDK_VERSION}-linux.zip -d ${WORKDIR} > /dev/null 2>&1 || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
    rm ${WORKDIR}/android-ndk-$NDK_VERSION-linux.zip
  fi
  export NDK_PATH="${NDK}"
}

# Function to set up sxlzptprjkt LLVM
# setup_llvm() {
#   if [ ! -d "${LLVM}" ]; then
#     echo -e "[DEBUG] downloading sxlzptprjkt LLVM..."
#     git clone https://github.com/sxlmnwb/sxlzptprjkt-clang ${WORKDIR}/sxlzptprjkt-clang || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
#   fi
#   export LLVM_PATH="${LLVM}"
# }

# Function to set up LLVM
setup_llvm() {
  if [ ! -d "${LLVM}" ]; then
    echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [DEBUG] downloading LLVM toolchains ${LLVM_VERSION}..."
    LLVM_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/LLVM-${LLVM_VERSION}-Linux-X64.tar.xz"
    echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [DEBUG] LLVM URL - ${LLVM_URL}"
    curl -L ${LLVM_URL} > ${WORKDIR}/LLVM-${LLVM_VERSION}-Linux-X64.tar.xz || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
    tar -xf ${WORKDIR}/LLVM-${LLVM_VERSION}-Linux-X64.tar.xz -C ${WORKDIR} > /dev/null 2>&1 || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
    rm ${WORKDIR}/LLVM-${LLVM_VERSION}-Linux-X64.tar.xz
  fi
  export LLVM_PATH="${LLVM}"
}

# Function to clone and prepare the Sing-Box repository
prepare_sing_box() {
  git remote add upstream https://github.com/SagerNet/sing-box.git > /dev/null 2>&1 
  git fetch upstream || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
  VERSION="v$(CGO_ENABLED=0 go run ./cmd/internal/read_tag)" || { echo -e "[ERROR] error code=1"; exit 1; }
  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [DEBUG] building summary"
  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] golang - $(go version | grep -oP "go[0-9.]+ \S+/\S+")"
  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] ndk - $($NDK/clang --version | awk '{print $12}' | head -n 1)"
  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] llvm - $($LLVM/clang --version | awk '{print $3}' | head -n 1)"
  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] caf - $($CAF/clang --version | awk '{print $3}' | head -n 1)"
  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] sing-box - ${VERSION}"
  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] tags - ${TAGS}"
  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] revision - $(git rev-parse HEAD)"
}

# Function to build for Android architectures with NDK
build_android_ndk() {
  local GOARCH=$1
  local API=$2
  local OUTPUT=$3

  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] building for android with NDK - GOARCH=${GOARCH} SUPPORT=${API} OUTPUT=${OUTPUT}"
  export AR="$NDK_PATH/llvm-ar"
  export CC="$NDK_PATH/${API}-clang"
  export CXX="$NDK_PATH/${API}-clang++"
  CCV=$("$CC" --version | head -n 1)
  DATE=$(date +"%a %b %d %I:%M:%S %p %Z %Y")

  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [DEBUG] golangci-lint for android - GOARCH=${GOARCH} SUPPORT=${API} OUTPUT=${OUTPUT}"
  CGO_ENABLED=1 GOOS=android GOARCH=${GOARCH} GOARM=7 golangci-lint run ./... || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
  CGO_ENABLED=1 GOOS=android GOARCH=${GOARCH} GOARM=7 \
  go build -v -trimpath -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${VERSION}' -X 'github.com/sagernet/sing-box/constant.CCVersion=${CCV}' -X 'github.com/sagernet/sing-box/constant.DATEBuild=${DATE}' -s -w -buildid=" -tags "${TAGS}" ./cmd/sing-box || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

  echo $VERSION > "sing-box-${VERSION}-${TARGET}-android-ndk-${OUTPUT}.tag"
  sudo zip -9 "${OUTDIR}/sing-box-${VERSION}-${TARGET}-android-ndk-${OUTPUT}.zip" sing-box "sing-box-${VERSION}-${TARGET}-android-ndk-${OUTPUT}.tag" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
}

# Function to build for Android architectures with LLVM
build_android_llvm() {
  local GOARCH=$1
  local OUTPUT=$2

  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] building for android with LLVM - GOARCH=${GOARCH} OUTPUT=${OUTPUT}"
  export AR="$LLVM_PATH/llvm-ar"
  export CC="$LLVM_PATH/clang"
  export CXX="$LLVM_PATH/clang++"
  CCV=$("$CC" --version | head -n 1)
  DATE=$(date +"%a %b %d %I:%M:%S %p %Z %Y")

  CGO_ENABLED=0 GOOS=android GOARCH=${GOARCH} GOARM=7 \
  go build -v -trimpath -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${VERSION}' -X 'github.com/sagernet/sing-box/constant.CCVersion=${CCV}' -X 'github.com/sagernet/sing-box/constant.DATEBuild=${DATE}' -s -w -buildid=" -tags "${TAGS}" ./cmd/sing-box || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

  echo $VERSION > "sing-box-${VERSION}-${TARGET}-android-llvm-${OUTPUT}.tag"
  sudo zip -9 "${OUTDIR}/sing-box-${VERSION}-${TARGET}-android-llvm-${OUTPUT}.zip" sing-box "sing-box-${VERSION}-${TARGET}-android-llvm-${OUTPUT}.tag" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
}

# Function to build for Android architectures with Snapdragon LLVM
build_android_caf() {
  local GOARCH=$1
  local OUTPUT=$2

  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] Building for android with Snapdragon LLVM - GOARCH=${GOARCH} OUTPUT=${OUTPUT}"
  export AR="$CAF/llvm-ar"
  export CC="$CAF/clang"
  export CXX="$CAF/clang++"
  CCV="Snapdragon LLVM Compiler (clang version "$("$CC" --version | awk '{print $3}' | head -n 1)") for ${GOARCH}"
  DATE=$(date +"%a %b %d %I:%M:%S %p %Z %Y")

  CGO_ENABLED=0 GOOS=android GOARCH=${GOARCH} \
  go build -v -trimpath -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${VERSION}' -X 'github.com/sagernet/sing-box/constant.CCVersion=${CCV}' -X 'github.com/sagernet/sing-box/constant.DATEBuild=${DATE}' -s -w -buildid=" -tags "${TAGS}" ./cmd/sing-box || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

  echo $VERSION > "sing-box-${VERSION}-${TARGET}-android-caf-${OUTPUT}.tag"
  sudo zip -9 "${OUTDIR}/sing-box-${VERSION}-${TARGET}-android-caf-${OUTPUT}.zip" sing-box "sing-box-${VERSION}-${TARGET}-android-caf-${OUTPUT}.tag" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
}


# Function to build for linux amd64 with LLVM
build_linux_amd64() {
  local GOARCH=$1
  local OUTPUT=$2

  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] building for linux with LLVM - GOARCH=${GOARCH} OUTPUT=${OUTPUT}"
  export AR="$LLVM_PATH/llvm-ar"
  export CC="$LLVM_PATH/clang"
  export CXX="$LLVM_PATH/clang++"
  CCV=$("$CC" --version | head -n 1)
  DATE=$(date +"%a %b %d %I:%M:%S %p %Z %Y")

  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [DEBUG] golangci-lint for linux - GOARCH=${GOARCH} OUTPUT=${OUTPUT}"
  CGO_ENABLED=1 GOOS=linux GOARCH=${GOARCH} golangci-lint run ./... || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
  CGO_ENABLED=1 GOOS=linux GOARCH=${GOARCH} \
  go build -v -trimpath -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${VERSION}' -X 'github.com/sagernet/sing-box/constant.CCVersion=${CCV}' -X 'github.com/sagernet/sing-box/constant.DATEBuild=${DATE}' -s -w -buildid=" -tags "${TAGS}" ./cmd/sing-box || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

  echo $VERSION > "sing-box-${VERSION}-${TARGET}-linux-llvm-${OUTPUT}.tag"
  sudo zip -9 "${OUTDIR}/sing-box-${VERSION}-${TARGET}-linux-llvm-${OUTPUT}.zip" sing-box "sing-box-${VERSION}-${TARGET}-linux-llvm-${OUTPUT}.tag" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
}

# Function to build for linux arm/arm64 with LLVM
build_linux_arm() {
  local GOARCH=$1
  local OUTPUT=$2

  echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] building for linux with LLVM - GOARCH=${GOARCH} OUTPUT=${OUTPUT}"
  export AR="$LLVM_PATH/llvm-ar"
  export CC="$LLVM_PATH/clang"
  export CXX="$LLVM_PATH/clang++"
  CCV=$("$CC" --version | head -n 1)
  DATE=$(date +"%a %b %d %I:%M:%S %p %Z %Y")

  CGO_ENABLED=0 GOOS=linux GOARCH=${GOARCH} GOARM=7 \
  go build -v -trimpath -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${VERSION}' -X 'github.com/sagernet/sing-box/constant.CCVersion=${CCV}' -X 'github.com/sagernet/sing-box/constant.DATEBuild=${DATE}' -s -w -buildid=" -tags "${TAGS}" ./cmd/sing-box || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

  echo $VERSION > "sing-box-${VERSION}-${TARGET}-linux-llvm-${OUTPUT}.tag"
  sudo zip -9 "${OUTDIR}/sing-box-${VERSION}-${TARGET}-linux-llvm-${OUTPUT}.zip" sing-box "sing-box-${VERSION}-${TARGET}-linux-llvm-${OUTPUT}.tag" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
}

# Function to clean up after build
clean2() {
  rm -f sing-box
  rm -f sing-box-*
}

# Main Execution Steps
echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [DEBUG] sing-box - building-cores"
make clean > /dev/null 2>&1

# Check Go installation and version
check_go_version || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

# Clean up before build
clean1 || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

# Set up NDK for Android builds
setup_ndk || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

# Set up LLVM for other platforms
setup_llvm || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

# Get building of sing-box
prepare_sing_box || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

# Build for Android architectures with NDK
build_android_ndk "arm" "armv7a-linux-androideabi35" "armeabi-v7a" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
build_android_ndk "arm64" "aarch64-linux-android35" "arm64-v8a" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

# Build for Android architectures with LLVM
build_android_llvm "arm64" "arm64-v8a" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

# Build for Android architectures with Snapdragon LLVM
build_android_caf "arm64" "arm64-v8a" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

# Build for linux amd64 with LLVM
build_linux_amd64 "amd64" "amd64" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

# Build for linux arm/arm64 with LLVM
build_linux_arm "arm" "armv7" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }
build_linux_arm "arm64" "arm64" || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

# Clean up after build
clean2 || { echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [ERROR] error code=1"; exit 1; }

echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [DEBUG] commit build: https://github.com/sxlmnwb/sing-box/commit/$(git rev-parse HEAD)"
echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [DEBUG] build output: ${OUTDIR}"
echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%N") [INFO] ok error code=0"
