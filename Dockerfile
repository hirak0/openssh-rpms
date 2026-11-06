# syntax=docker/dockerfile:1
# =============================================================================
# OpenSSH RPM 编译镜像（多发行版通用）
#
# 用法:
#   docker build --build-arg BASE_IMAGE=rockylinux:9 -t openssh-builder:el9 .
#
# 常用基础镜像 -> 产物标签:
#   centos:7 / centos:8 / centos:9   -> el7 / el8 / el9
#   rockylinux:8|9|10                 -> el8 / el9 / el10
#   almalinux:8|9|10                  -> el8 / el9 / el10
#   quay.io/centos/centos:stream8|9  -> el8 / el9
#   openeuler/openeuler:22.03-lts|24.03-lts-sp*  -> oe2203 / oe2403sp*
#   opencloudos/opencloudos:9         -> oc9
#   amazonlinux:2 / amazonlinux:2023  -> amzn2 / amzn2023
#   registry.access.redhat.com/ubi9    -> el9
#   opensuse/leap:15.6 / opensuse/sle15 -> leap15 / sle15
#
# ARM (aarch64):
#   - ARM 宿主机直接用多架构镜像；
#   - x86 宿主机交叉编译加 --platform linux/arm64，
#     首次需: docker run --privileged --rm tonistiigi/binfmt --install arm64
# =============================================================================
ARG BASE_IMAGE=rockylinux:9
FROM ${BASE_IMAGE}

ARG EXTRA_PACKAGES=""

# --- 1. 归档中的 CentOS / CentOS Stream 软件源修复 -----------------------------
# CentOS 7 与 Stream 8 已 EOL，官方源 404；此处按可用性依次尝试多个 vault 镜像。
RUN set -eux; \
    if [ -d /etc/yum.repos.d ]; then \
        for repo in /etc/yum.repos.d/CentOS-*.repo; do \
            [ -f "$repo" ] || continue; \
            sed -i -e 's|^mirrorlist=|#mirrorlist=|' \
                   -e 's|^metalink=|#metalink=|' "$repo" || true; \
        done; \
        if grep -q 'CentOS Linux release 7' /etc/centos-release 2>/dev/null; then \
            for base in \
                "https://mirrors.aliyun.com/centos-vault/7.9.2009" \
                "https://mirrors.tuna.tsinghua.edu.cn/centos-vault/7.9.2009" \
                "https://repo.huaweicloud.com/centos-vault/7.9.2009" \
                "https://vault.centos.org/7.9.2009" ; do \
                if curl -fsS --max-time 20 -o /dev/null "$base/os/x86_64/repodata/repomd.xml" 2>/dev/null \
                   || curl -fsS --max-time 20 -o /dev/null "$base/os/aarch64/repodata/repomd.xml" 2>/dev/null; then \
                    sed -i -e "s|^#*baseurl=http://mirror.centos.org/centos/\\\$releasever|baseurl=$base|" \
                        /etc/yum.repos.d/CentOS-Base.repo; \
                    break; \
                fi; \
            done; \
        elif grep -q 'CentOS Stream release 8' /etc/centos-release 2>/dev/null; then \
            for base in \
                "https://mirrors.aliyun.com/centos-stream/8" \
                "https://mirrors.tuna.tsinghua.edu.cn/centos-stream/8" \
                "https://vault.centos.org/8.5.2111" ; do \
                if curl -fsS --max-time 20 -o /dev/null "$base/BaseOS/x86_64/os/repodata/repomd.xml" 2>/dev/null \
                   || curl -fsS --max-time 20 -o /dev/null "$base/BaseOS/aarch64/os/repodata/repomd.xml" 2>/dev/null; then \
                    sed -i -e "s|^#*baseurl=http://mirror.centos.org/\\\$contentdir|baseurl=$base|" \
                        /etc/yum.repos.d/CentOS-Stream-*.repo || true; \
                    break; \
                fi; \
            done; \
        fi; \
    fi

# --- 2. 依赖安装（dnf / yum / microdnf / zypper 通用） -------------------------
# 说明:
#   - rpm-build / rpm   提供 rpmbuild（EL 系用 rpm-build，SLE 系用 rpm-build 包）
#   - perl-IPC-Cmd/perl-Data-Dumper/perl-Pod-Html  OpenSSH 回归测试脚本依赖
#   - libedit-devel  sftp 的行编辑增强（可选，缺失时自动降级）
#   - libselinux-devel  sshd 的 SELinux 支持（可选）
#   - libXt-devel  x11-ssh-askpass 构建依赖（可选）
#   - 部分发行版（SLE_BCI 精简源）没有个别包，整组安装失败时降级为最小集合
RUN set -eux; \
    if command -v dnf >/dev/null 2>&1; then PM=dnf; \
    elif command -v microdnf >/dev/null 2>&1; then PM=microdnf; \
    elif command -v yum >/dev/null 2>&1; then PM=yum; \
    elif command -v zypper >/dev/null 2>&1; then PM=zypper; \
    else echo "未找到可用的包管理器"; exit 1; fi; \
    COMMON="gcc gcc-c++ make perl tar gzip which patch findutils file zlib-devel pam-devel"; \
    case "$PM" in \
      dnf|microdnf|yum) \
        $PM install -y $COMMON rpm-build perl-devel perl-IPC-Cmd perl-Data-Dumper \
            perl-Pod-Html perl-Time-Piece libedit-devel libselinux-devel libXt-devel \
            systemd-devel ncurses || \
        $PM install -y $COMMON rpm-build perl-devel ; \
        $PM clean all || true ; \
        ;; \
      zypper) \
        # SLE 系用独立的 rpm-build 包；直接装 rpm 会与已装的 rpm-ndb 冲突
        $PM --non-interactive install -y $COMMON rpm-build || \
        $PM --non-interactive install -y $COMMON ; \
        $PM --non-interactive install -y perl-devel perl-IPC-Cmd perl-Data-Dumper \
            perl-Time-Piece libedit-devel libselinux-devel libXt-devel || true ; \
        $PM clean --all || true ; \
        ;; \
    esac; \
    if [ -n "$EXTRA_PACKAGES" ]; then \
        case "$PM" in \
          zypper) $PM --non-interactive install -y $EXTRA_PACKAGES || true ;; \
          *) $PM install -y $EXTRA_PACKAGES || true ;; \
        esac; \
    fi; \
    rpmbuild --version

WORKDIR /build
CMD ["/bin/bash"]
