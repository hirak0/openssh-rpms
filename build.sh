#!/usr/bin/env bash
#===============================================================================
# Name:        build.sh
# Description: OpenSSH RPM 一键 Docker 编译脚本
# Usage:       ./build.sh [选项]
# Exit Codes:  0=成功 1=参数错误 2=前置条件不满足 3=Docker 构建/运行失败
# Requires:    docker, bash 4+
#
# 用法示例:
#   ./build.sh                                  # 默认 rockylinux:9
#   ./build.sh -i rockylinux:9 -t el9           # 指定基础镜像与系统标签
#   ./build.sh -i openeuler/openeuler:24.03-lts-sp2 -t oe2403sp2
#   ./build.sh -p linux/arm64 -i rockylinux:9   # 在 x86 上交叉编译 aarch64
#   ./build.sh -f                               # 强制重建镜像
#
# 前置: 当前目录需有 openssh-*.tar.gz 与 openssl-*.tar.gz 源码包
# 产物: ./output/openssh-<版本>-rpms-<标签>-<架构>.tar.gz
#===============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"
readonly EXIT_OK=0 EXIT_USAGE=1 EXIT_PREREQ=2 EXIT_RUNTIME=3

log()  { printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; exit "$EXIT_RUNTIME"; }
usage() {
    cat >&2 <<EOF
用法: $SCRIPT_NAME [-i 基础镜像] [-t 系统标签] [-p 平台] [-f] [-h]
  -i <镜像>   基础镜像，默认 rockylinux:9
  -t <标签>   产物系统标签（el9 / oe2403sp2 / ky10sp3 ...），默认按镜像名推断
  -p <平台>   docker 平台，如 linux/amd64、linux/arm64
  -f          强制重建编译镜像
  -h          显示本帮助
EOF
}

cd "$(dirname "$0")"

BASE_IMAGE="rockylinux:9"
OS_TAG=""
PLATFORM=""
FORCE=0

while getopts "i:t:p:fh" opt; do
    case "$opt" in
        i) BASE_IMAGE="$OPTARG" ;;
        t) OS_TAG="$OPTARG" ;;
        p) PLATFORM="$OPTARG" ;;
        f) FORCE=1 ;;
        h) usage; exit "$EXIT_OK" ;;
        *) usage; exit "$EXIT_USAGE" ;;
    esac
done

PLAT_OPT=()
[ -n "$PLATFORM" ] && PLAT_OPT=(--platform "$PLATFORM")

command -v docker >/dev/null 2>&1 || { usage; echo "[$SCRIPT_NAME] ERROR: 未找到 docker，请先安装 Docker" >&2; exit "$EXIT_PREREQ"; }

# --- 源码包检查 ---------------------------------------------------------------
SSH_TAR=""
for f in openssh-*.tar.gz openssh-*.tar.xz; do
    [ -f "$f" ] && { SSH_TAR="$f"; break; }
done
SSL_TAR=""
for f in openssl-*.tar.gz openssl-*.tar.xz; do
    [ -f "$f" ] && { SSL_TAR="$f"; break; }
done
[ -n "$SSH_TAR" ] || { usage; die "未找到 openssh-*.tar.gz，请先放到当前目录"; }
[ -n "$SSL_TAR" ] || { usage; die "未找到 openssl-*.tar.gz，请先放到当前目录"; }

# --- 未指定标签时按镜像名推断 -------------------------------------------------
if [ -z "$OS_TAG" ]; then
    case "$BASE_IMAGE" in
        *el7*|*centos:7*)                OS_TAG="el7" ;;
        *el8*|*centos:8*|*rockylinux:8*|*almalinux:8*) OS_TAG="el8" ;;
        *el9*|*centos:9*|*rockylinux:9*|*almalinux:9*|*ubi9*) OS_TAG="el9" ;;
        *el10*|*rockylinux:10*|*almalinux:10*) OS_TAG="el10" ;;
        *stream8*|*stream9*)              OS_TAG="el8" ;;
        *kylin*|*ky10*)                   OS_TAG="ky10" ;;
        *openeuler*24.03*|*oe2403*)      OS_TAG="oe2403" ;;
        *openeuler*22.03*|*oe2203*)      OS_TAG="oe2203" ;;
        *opencloudos*)                    OS_TAG="oc9" ;;
        *anolis*8*)                       OS_TAG="an8" ;;
        *anolis*23*)                      OS_TAG="an23" ;;
        *amazonlinux:2023*|*amzn2023*)   OS_TAG="amzn2023" ;;
        *amazonlinux:2*|*amzn2*)         OS_TAG="amzn2" ;;
        *sle15*|*opensuse/sle*)           OS_TAG="sle15" ;;
        *leap15*|*opensuse/leap*)         OS_TAG="leap15" ;;
        *)                                OS_TAG="custom" ;;
    esac
fi

IMAGE_NAME="openssh-builder:${OS_TAG}${PLATFORM:+-$(printf '%s' "$PLATFORM" | tr '/' '-')}"

printf '==========================================\n'
printf ' 基础镜像 : %s\n' "$BASE_IMAGE"
printf ' 系统标签 : %s\n' "$OS_TAG"
[ -n "$PLATFORM" ] && printf ' 目标平台 : %s\n' "$PLATFORM"
printf ' SSH 源码 : %s\n' "$SSH_TAR"
printf ' SSL 源码 : %s\n' "$SSL_TAR"
printf '==========================================\n'

# --- 构建编译镜像 -------------------------------------------------------------
if [ "$FORCE" -eq 1 ] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    log "构建编译镜像 ${IMAGE_NAME} ..."
    docker build "${PLAT_OPT[@]}" --build-arg "BASE_IMAGE=$BASE_IMAGE" -t "$IMAGE_NAME" .
else
    log "复用已有镜像 ${IMAGE_NAME}（-f 可强制重建）"
fi

mkdir -p output

# --- 运行编译 -----------------------------------------------------------------
# 原理: 当前目录挂到容器 /build（脚本在其中探测源码包）；
#       ./output 挂到容器 /opt 直接接住产物 tar 包。
log "启动容器编译（可能需要 10-30 分钟，交叉编译更久）..."
docker run --rm "${PLAT_OPT[@]}" \
    -e "FORCE_OS_TAG=$OS_TAG" \
    -e "AUTO_DEPS=${AUTO_DEPS:-0}" \
    -v "$(pwd):/build" \
    -v "$(pwd)/output:/opt" \
    "$IMAGE_NAME" \
    bash -c "cd /build && bash build_openssh.sh"

# --- 结果检查 -----------------------------------------------------------------
printf '\n'
if ls output/*.tar.gz >/dev/null 2>&1; then
    log "编译完成，产物:"
    ls -lh output/*.tar.gz
    exit "$EXIT_OK"
fi
die "未在 output/ 找到产物，请查看上方编译日志排查。"
