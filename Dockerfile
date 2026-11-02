# OpenSSH RPM 编译镜像
# 用法: docker build --build-arg BASE_IMAGE=centos:7 -t openssh-builder:el7 .
# 切换目标系统只需改 BASE_IMAGE，例如:
#   centos:7                -> el7
#   centos:8 / rockylinux:8 -> el8
#   rockylinux:9            -> el9
#   openeuler/openeuler:22.03-lts -> oe22
#   麒麟 V10 (需有内部/社区镜像，如 swr.cn-north-4.myhuaweicloud.com/.../kylin-v10-sp3)
#
# ARM (aarch64):
#   - ARM 宿主机(鲲鹏/飞腾)上直接用多架构镜像: rockylinux:9, openeuler/openeuler 等
#   - x86 宿主机交叉编译: 加 --platform linux/arm64，首次需安装 QEMU:
#     docker run --privileged --rm tonistiigi/binfmt --install arm64
#   - 注意: 官方 centos:7 没有 arm64 版本，ARM 用 rockylinux:8 / openeuler 或麒麟 ARM 镜像
ARG BASE_IMAGE=centos:7
FROM ${BASE_IMAGE}

# CentOS 7 已停止维护，固定到最终归档仓库
RUN (sed -i -e 's|^mirrorlist=|#mirrorlist=|' \
     -e 's|^#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=https://vault.centos.org/7.9.2009|' \
     /etc/yum.repos.d/CentOS-*.repo 2>/dev/null || true) \
 && (yum clean all 2>/dev/null || true)

# 预装编译依赖，容器内即可跳过脚本里的交互式依赖安装
RUN yum install -y rpm-build gcc gcc-c++ make \
    perl perl-IPC-Cmd perl-Data-Dumper perl-Pod-Html perl-devel perl-Time-Piece \
    zlib-devel pam-devel krb5-devel libXt-devel gtk2-devel systemd-devel \
    tar gzip which \
 && yum clean all \
 || (echo "WARN: 部分依赖安装失败，容器内运行脚本时选择 [1] 安装" )

# 编译基础工具（openssl 需要的额外 perl 模块兜底）
RUN yum install -y perl-WWW-Curl 2>/dev/null; true

WORKDIR /build
CMD ["/bin/bash"]
