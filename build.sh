#!/bin/bash
# =============================================================
# OpenSSH RPM 一键 Docker 编译脚本
# 参考: https://github.com/nugent1a/openssh-rpms
#
# 用法:
#   ./build.sh                          # 默认 centos:7 编译
#   ./build.sh -i rockylinux:9 -t el9   # 指定基础镜像和系统标签
#   ./build.sh -i <麒麟V10镜像> -t ky10 # 麒麟 V10 SP3 编译
#
# ARM (aarch64) 编译:
#   ./build.sh -i <ARM版基础镜像>                      # 在 ARM 宿主机上直接编译
#   ./build.sh -p linux/arm64 -i <ARM版基础镜像>       # 在 x86 宿主机上用 QEMU 交叉编译
#     (x86 上首次需: docker run --privileged --rm tonistiigi/binfmt --install arm64)
#
# 前置: 当前目录需有 openssh-*.tar.gz 和 openssl-*.tar.gz 源码包
# 产物: ./output/openssh-<版本>-rpms-<标签>-<架构>.tar.gz
# =============================================================
set -e

cd "$(dirname "$0")"

BASE_IMAGE="centos:7"
OS_TAG=""
IMAGE_NAME=""
PLATFORM=""
FORCE=0

while getopts "i:t:p:f" opt; do
  case $opt in
    i) BASE_IMAGE="$OPTARG" ;;
    t) OS_TAG="$OPTARG" ;;
    p) PLATFORM="$OPTARG" ;;
    f) FORCE=1 ;;
    *) echo "用法: $0 [-i 基础镜像] [-t 系统标签] [-p 平台 linux/amd64|linux/arm64] [-f 强制重建镜像]"; exit 1 ;;
  esac
done

# 平台参数 -> docker build/run 的 --platform
PLAT_OPT=()
[ -n "$PLATFORM" ] && PLAT_OPT=(--platform "$PLATFORM")

# --- 源码包检查 ---
SSH_TAR=$(ls openssh-*.tar.gz 2>/dev/null | head -1 || true)
SSL_TAR=$(ls openssl-*.tar.gz 2>/dev/null | head -1 || true)
[ -z "$SSH_TAR" ] && echo "❌ 未找到 openssh-*.tar.gz，请先放到当前目录" && exit 1
[ -z "$SSL_TAR" ] && echo "❌ 未找到 openssl-*.tar.gz，请先放到当前目录" && exit 1

# 未指定 OS_TAG 时从镜像名猜
if [ -z "$OS_TAG" ]; then
  case "$BASE_IMAGE" in
    *el7*|*centos:7*)  OS_TAG=el7 ;;
    *el8*|*centos:8*|*rockylinux:8*) OS_TAG=el8 ;;
    *rockylinux:9*|*el9*) OS_TAG=el9 ;;
    *kylin*|*ky10*)    OS_TAG=ky10 ;;
    *openeuler*)       OS_TAG=oe22 ;;
    *anolis*)          OS_TAG=an8 ;;
    *) OS_TAG=custom ;;
  esac
fi

IMAGE_NAME="openssh-builder:${OS_TAG}${PLATFORM:+-$(echo "$PLATFORM" | tr '/' '-')}"

echo "=========================================="
echo " 基础镜像 : ${BASE_IMAGE}"
echo " 系统标签 : ${OS_TAG}"
[ -n "$PLATFORM" ] && echo " 目标平台 : ${PLATFORM}"
echo " SSH 源码 : ${SSH_TAR}"
echo " SSL 源码 : ${SSL_TAR}"
echo "=========================================="

# --- 构建编译镜像 ---
if [ $FORCE -eq 1 ] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo ">>> 构建编译镜像 ${IMAGE_NAME} ..."
  docker build "${PLAT_OPT[@]}" --build-arg BASE_IMAGE="$BASE_IMAGE" -t "$IMAGE_NAME" .
else
  echo ">>> 复用已有镜像 ${IMAGE_NAME}（-f 可强制重建）"
fi

mkdir -p output

# --- 运行编译 ---
# 原理: 把当前目录挂到容器的 /build，脚本在那里探测源码；
#       把 ./output 挂到 /opt 直接接住产物 tar 包。
#       echo 1 应答脚本里的"安装依赖"交互(镜像里已预装，选1也无害)。
echo ">>> 启动容器编译（可能需要 10-30 分钟，交叉编译更久）..."
docker run --rm -t "${PLAT_OPT[@]}" \
  -v "$(pwd):/build" \
  -v "$(pwd)/output:/opt" \
  "$IMAGE_NAME" \
  bash -c "cd /build/repo && echo 1 | bash build_openssh.sh"

# --- 结果检查 ---
echo ""
if ls output/*.tar.gz >/dev/null 2>&1; then
  echo "✅ 编译完成，产物:"
  ls -lh output/*.tar.gz
else
  echo "❌ 未在 output/ 找到产物，请查看上方编译日志排查。"
  exit 1
fi
