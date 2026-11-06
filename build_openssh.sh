#!/usr/bin/env bash
#===============================================================================
# Name:        build_openssh.sh
# Description: 把 OpenSSH 源码编译并打包成目标 RPM 发行版可安装的 RPM 包
# Usage:       bash build_openssh.sh
# Exit Codes:  0=成功 1=参数错误 2=前置依赖缺失 3=源码探测失败
#              4=构建失败 5=打包失败 6=用户中断
# Requires:    bash 4+, rpm-build, gcc, make, perl, tar
#
# 可选环境变量：
#   FORCE_OS_TAG   强制产物系统标签（el9 / oe2403sp2 / ky10sp3 ...），跳过自动探测
#   RPM_RELEASE    RPM Release 序号，默认 1
#   OUTPUT_DIR     产物输出目录，默认 /opt
#   LOG_DIR        构建日志目录，默认 /tmp/openssh_build_logs
#   RPMBUILD_DIR   rpmbuild 工作目录，默认 /root/rpmbuild
#   AUTO_DEPS=1    自动安装依赖且不询问（容器 / CI 场景）
#   JOBS           并行编译任务数，默认 nproc
#   PRIVSEP_PATH   sshd 权限隔离目录，默认 /var/empty/sshd
#   KEEP_WORKDIR=1 保留 rpmbuild 与日志，默认构建结束后清理
#===============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_VERSION="v3.0"
readonly SCRIPT_AUTHOR="nugent1a / hirak0"

readonly EXIT_OK=0 EXIT_USAGE=1 EXIT_PREREQ=2 EXIT_SOURCE=3
readonly EXIT_BUILD=4 EXIT_PACKAGE=5 EXIT_CANCELLED=6

# ---------------------------------------------------------------- 配置区 ----
RPM_RELEASE="${RPM_RELEASE:-1}"
# rpmbuild 的工作根目录随发行版不同（EL: /root/rpmbuild，SUSE: /usr/src/packages），
# 这里跟随发行版自带的 %{_topdir}，避免 spec 里的 Source0 找不到文件。
if [ -z "${RPMBUILD_DIR:-}" ]; then
    RPMBUILD_DIR="$(rpm --eval '%{_topdir}' 2>/dev/null || true)"
    [ -n "$RPMBUILD_DIR" ] || RPMBUILD_DIR="/root/rpmbuild"
fi
OUTPUT_DIR="${OUTPUT_DIR:-/opt}"
LOG_DIR="${LOG_DIR:-/tmp/openssh_build_logs}"
PRIVSEP_PATH="${PRIVSEP_PATH:-/var/empty/sshd}"
PRIVSEP_USER="${PRIVSEP_USER:-sshd}"
AUTO_DEPS="${AUTO_DEPS:-0}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

# ------------------------------------------------------------- 运行时状态 ----
DISTRO_ID="unknown"
DISTRO_VERSION_ID=""
DISTRO_ID_LIKE=""
DISTRO_PRETTY=""
SSH_TAR=""
SSL_TAR=""
ASKPASS_TAR=""
HAS_ASKPASS="false"
OPENSSH_VERSION=""
OPENSSL_VERSION=""
OS_TAG=""
ARCH_TAG=""
RPM_DIST=""
CURRENT_STEP="init"
CURSOR_HIDDEN=""

# ------------------------------------------------------------------ 输出 ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[1;31m'
    C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_BLUE=$'\033[1;34m'
    C_CYAN=$'\033[1;36m'; C_GREY=$'\033[90m'; C_WHITE=$'\033[1;37m'
else
    C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""
    C_BLUE=""; C_CYAN=""; C_GREY=""; C_WHITE=""
fi

log()  { printf '%s[%s]%s %s: %s\n' "$C_GREY" "$(date '+%F %T')" "$C_RESET" "$SCRIPT_NAME" "$*" >&2; }
info() { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit "${EXIT_RUNTIME:-1}"; }

hide_cursor() {
    [ -t 1 ] || return 0
    CURSOR_HIDDEN=1
    tput civis 2>/dev/null || true
}

show_cursor() {
    [ -n "$CURSOR_HIDDEN" ] || return 0
    tput cnorm 2>/dev/null || true
    CURSOR_HIDDEN=""
}

cleanup() {
    local rc=$?
    show_cursor
    if [ "$rc" -ne 0 ] && [ "$rc" -ne "$EXIT_CANCELLED" ]; then
        err "构建在步骤「${CURRENT_STEP}」失败（退出码 ${rc}）；日志：${LOG_DIR}"
    fi
    return "$rc"
}

on_interrupt() {
    show_cursor
    printf '\n%s[CANCEL]%s 用户中断，已终止构建。\n' "$C_CYAN" "$C_RESET" >&2
    exit "$EXIT_CANCELLED"
}

usage() {
    cat >&2 <<EOF
用法: $SCRIPT_NAME [--help]

可选环境变量:
  FORCE_OS_TAG   强制产物系统标签（el9 / oe2403sp2 / ky10sp3 ...）
  RPM_RELEASE    RPM Release 序号（默认 1）
  OUTPUT_DIR     产物输出目录（默认 /opt）
  LOG_DIR        构建日志目录（默认 /tmp/openssh_build_logs）
  RPMBUILD_DIR   rpmbuild 工作目录（默认 /root/rpmbuild）
  AUTO_DEPS=1    自动安装依赖且不询问
  JOBS           并行编译任务数（默认 nproc）
  PRIVSEP_PATH   sshd 权限隔离目录（默认 /var/empty/sshd）
  KEEP_WORKDIR=1 保留 rpmbuild 与日志
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit "$EXIT_OK" ;;
            *) usage; err "未知参数: $1"; exit "$EXIT_USAGE" ;;
        esac
    done
}

trap cleanup EXIT
trap on_interrupt INT TERM

# ====================================================================== 工具 ==
have() { command -v "$1" >/dev/null 2>&1; }

# ============================================================== 系统探测 =====
detect_distro() {    DISTRO_ID="unknown"; DISTRO_VERSION_ID=""; DISTRO_ID_LIKE=""; DISTRO_PRETTY=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_VERSION_ID="${VERSION_ID:-}"
        DISTRO_ID_LIKE="${ID_LIKE:-}"
        DISTRO_PRETTY="${PRETTY_NAME:-}"
    elif [ -r /etc/redhat-release ]; then
        DISTRO_ID="rhel"
        DISTRO_VERSION_ID="$(sed -n 's/.*release \([0-9][0-9.]*\).*/\1/p' /etc/redhat-release | head -1)"
        DISTRO_PRETTY="$(cat /etc/redhat-release)"
    fi
    log "探测到发行版：id=${DISTRO_ID} version=${DISTRO_VERSION_ID:-?} like=${DISTRO_ID_LIKE:-?}"
}

# openEuler 24.03 LTS SP2 的 VERSION 形如 "24.03 (LTS-SP2)"
distro_service_pack() {
    printf '%s' "${DISTRO_PRETTY:-} ${1:-}" \
        | grep -oE '(LTS-)?SP[0-9]+' | head -1 | tr -d 'LTS-' | tr '[:upper:]' '[:lower:]'
}

os_tag_for_distro() {
    local id="$1" ver="$2" major sp
    major="${ver%%.*}"
    sp="$(distro_service_pack "$ver")"

    case "$id" in
        centos|rhel|almalinux|rocky|scientific|eurolinux|circle|ol|oracle|cloudlinux|miracle|highgo|ncs|xenserver|tongxin)
            printf 'el%s' "$major" ;;
        fedora)
            printf 'fc%s' "$major" ;;
        amzn)
            case "$major" in
                2) printf 'amzn2' ;;
                2023) printf 'amzn2023' ;;
                *) printf 'amzn%s' "$major" ;;
            esac ;;
        anolis)
            printf 'an%s' "$major" ;;
        openEuler|openeuler)
            if [ -n "$sp" ]; then
                printf 'oe%s%s' "$(printf '%s' "$ver" | tr -d '.')" "$sp"
            else
                printf 'oe%s' "$(printf '%s' "$ver" | tr -d '.')"
            fi ;;
        opencloudos)
            printf 'oc%s' "$major" ;;
        euleros)
            printf 'euler%s' "$major" ;;
        kylin|kylin_linux_advanced_server|kylin_desktop)
            printf 'ky%s' "${ver#V}" ;;
        uos|uniontech)
            printf 'uos%s' "$major" ;;
        alinux)
            printf 'ali%s' "$major" ;;
        tencentos)
            printf 'tos%s' "$major" ;;
        mageia)
            printf 'mga%s' "$major" ;;
        opensuse|opensuse-leap|opensuse-tumbleweed)
            case "$id" in
                opensuse-leap) printf 'leap%s' "$major" ;;
                opensuse-tumbleweed) printf 'tumbleweed' ;;
                *) printf 'leap%s' "$major" ;;
            esac ;;
        sles|sled|suse|suse_linux_enterprise_server)
            printf 'sle%s' "$major" ;;
        openssh)
            printf 'el%s' "$major" ;;
        *)
            # 未知 ID 时按 ID_LIKE 兜底
            case " $DISTRO_ID_LIKE " in
                *" rhel "*|*" fedora "*) printf 'el%s' "$major" ;;
                *" suse "*)           printf 'sle%s' "$major" ;;
                *" debian "*)         printf 'deb%s' "$major" ;;
                *) return 1 ;;
            esac ;;
    esac
}

get_os_tag() {
    # rpm 自身的 dist 标记最可靠（如 .el9 / .ky10 / .oe2403）
    local dist
    dist="$(detect_rpm_dist)"
    if [ -n "$dist" ]; then
        printf '%s' "$dist"
        return 0
    fi
    os_tag_for_distro "$DISTRO_ID" "$DISTRO_VERSION_ID"
}

detect_rpm_dist() {
    local dist
    dist="$(rpm --eval '%{?dist}' 2>/dev/null | tr -d '.' || true)"
    if [ -n "$dist" ] && [ "$dist" != '%{?dist}' ]; then
        printf '%s' "$dist"
        return 0
    fi
    return 1
}

get_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)  printf 'x86_64' ;;
        aarch64|arm64) printf 'aarch64' ;;
        ppc64le)       printf 'ppc64le' ;;
        s390x)         printf 's390x' ;;
        riscv64)       printf 'riscv64' ;;
        *)
            err "不支持的 CPU 架构: ${arch}"
            return 1 ;;
    esac
}

# ============================================================== 源码探测 =====
# 依据 tarball 文件名推导版本号：openssh-10.6p2.tar.gz -> 10.6p2
version_from_tarball() {
    local file="$1" prefix="$2"
    local base="${file##*/}"
    base="${base#"${prefix}"-}"
    base="${base%.tar.gz}"
    base="${base%.tar.xz}"
    printf '%s' "$base"
}

# $1 = 文件名前缀，$2 = 变量名（结果写入）
pick_source() {
    local prefix="$1" target="$2"
    local -a matches=()
    local f
    for f in "$BASE_DIR"/${prefix}-*.tar.gz "$BASE_DIR"/${prefix}-*.tar.xz; do
        [ -f "$f" ] && matches+=("$f")
    done
    if [ "${#matches[@]}" -eq 0 ]; then
        return 1
    fi
    if [ "${#matches[@]}" -eq 1 ]; then
        printf -v "$target" '%s' "${matches[0]}"
        return 0
    fi
    if [ ! -t 0 ]; then
        # 非交互环境（CI / 管道）取版本号最高的一个
        local best="${matches[0]}" bestv="" curv
        for f in "${matches[@]}"; do
            curv="$(version_from_tarball "$f" "$prefix")"
            if [ -z "$bestv" ] || [ "$(printf '%s\n%s\n' "$bestv" "$curv" | sort -V | tail -1)" = "$curv" ]; then
                bestv="$curv"; best="$f"
            fi
        done
        printf -v "$target" '%s' "$best"
        return 0
    fi
    show_cursor
    printf '%s[?] 请选择 %s 版本:%s\n' "$C_YELLOW" "$prefix" "$C_RESET" >&2
    local i
    for i in "${!matches[@]}"; do
        printf '   %d) %s\n' "$((i + 1))" "${matches[$i]##*/}" >&2
    done
    local choice=""
    read -r -p "   输入编号 [1-${#matches[@]}]: " choice >&2
    hide_cursor
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#matches[@]}" ]; then
        err "无效选择: ${choice}"
        return 1
    fi
    printf -v "$target" '%s' "${matches[$((choice - 1))]}"
}

detect_source_files() {
    BASE_DIR="$(pwd)"

    if [ -n "${SSH_TAR:-}" ] && [ -f "$SSH_TAR" ]; then
        :
    else
        pick_source openssh SSH_TAR || die "未找到 openssh-*.tar.gz / openssh-*.tar.xz（当前目录：${BASE_DIR}）"
    fi
    OPENSSH_VERSION="$(version_from_tarball "$SSH_TAR" openssh)"

    if [ -n "${SSL_TAR:-}" ] && [ -f "$SSL_TAR" ]; then
        :
    else
        pick_source openssl SSL_TAR || die "未找到 openssl-*.tar.gz / openssl-*.tar.xz（当前目录：${BASE_DIR}）"
    fi
    OPENSSL_VERSION="$(version_from_tarball "$SSL_TAR" openssl)"

    # x11-ssh-askpass 可选
    if pick_source x11-ssh-askpass ASKPASS_TAR 2>/dev/null; then
        HAS_ASKPASS="true"
    else
        ASKPASS_TAR=""
        HAS_ASKPASS="false"
    fi

    # 校验版本号能否安全地写进 RPM 的 Version 字段
    if ! [[ "$OPENSSH_VERSION" =~ ^[0-9][0-9A-Za-z._-]*$ ]]; then
        die "无法从文件名解析出合法的 OpenSSH 版本号: ${OPENSSH_VERSION}"
    fi
    if ! [[ "$OPENSSL_VERSION" =~ ^[0-9][0-9A-Za-z._-]*$ ]]; then
        die "无法从文件名解析出合法的 OpenSSL 版本号: ${OPENSSL_VERSION}"
    fi
}

# ============================================================ 依赖与工具 ====
install_build_deps() {
    local pkg_mgr="" pkgs=()
    if   have dnf; then pkg_mgr="dnf"
    elif have yum; then pkg_mgr="yum"
    elif have microdnf; then pkg_mgr="microdnf"
    else
        warn "未找到 dnf/yum/microdnf，跳过依赖自动安装（请确认镜像内已装好编译依赖）"
        return 0
    fi

    pkgs=(rpm-build gcc gcc-c++ make perl perl-IPC-Cmd perl-Data-Dumper
          perl-Pod-Html perl-devel perl-Time-Piece zlib-devel pam-devel
          tar gzip which patch ncurses file findutils libedit-devel)

    info "使用 ${pkg_mgr} 安装编译依赖 ..."
    if ! "$pkg_mgr" install -y "${pkgs[@]}"; then
        warn "依赖安装失败，继续尝试构建（详细日志见 ${LOG_DIR}/01_deps.log）"
        return 1
    fi
    return 0
}

require_tools() {
    local missing=()
    local tool
    for tool in rpmbuild gcc make perl tar gzip patch; do
        have "$tool" || missing+=("$tool")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        err "缺少构建工具: ${missing[*]}"
        return 1
    fi
    return 0
}

# ================================================================ 任务执行 ==
# 不使用 eval：命令以数组形式传入，避免注入与转义问题
run_task() {
    local desc="$1"; shift
    local log_file="${LOG_DIR}/$1"; shift
    local -a cmd=("$@")
    local start_time end_time exit_code duration

    [ "${#cmd[@]}" -eq 0 ] && { err "run_task: 空命令"; return 1; }

    printf '   Target: %s%s%s ... ' "$C_BLUE" "$desc" "$C_RESET"

    start_time="$(date +%s)"
    "${cmd[@]}" >"$log_file" 2>&1 &
    local pid=$!

    if [ -t 1 ]; then
        local spinstr='|/-\' temp delay=0.1
        while kill -0 "$pid" 2>/dev/null; do
            temp="${spinstr#?}"
            printf ' [%s%c%s] ' "$C_GREEN" "$spinstr" "$C_RESET"
            spinstr="${temp}${spinstr%"$temp"}"
            sleep "$delay"
            printf '\b\b\b\b\b'
        done
    fi

    wait "$pid"
    exit_code=$?
    end_time="$(date +%s)"
    duration=$((end_time - start_time))

    if [ "$exit_code" -eq 0 ]; then
        printf '%s[OK]%s %s(%ss)%s\n' "$C_GREEN" "$C_RESET" "$C_GREY" "$duration" "$C_RESET"
        return 0
    fi
    printf '%s[FAILED]%s %s(%ss)%s\n' "$C_RED" "$C_RESET" "$C_GREY" "$duration" "$C_RESET"
    echo "-------------------------------------------------------"
    tail -n 20 "$log_file"
    echo "-------------------------------------------------------"
    return "$exit_code"
}

# ============================================================ SPEC 生成 =====
write_pam_file() {
    cat > "${RPMBUILD_DIR}/SOURCES/sshd.pam" <<'EOF'
#%PAM-1.0
auth       required     pam_sepermit.so
auth       include      password-auth
account    required     pam_nologin.so
account    include      password-auth
password   include      password-auth
session    required     pam_selinux.so close
session    required     pam_loginuid.so
session    required     pam_selinux.so open env_params
session    optional     pam_keyinit.so force revoke
session    include      password-auth
EOF
}

write_systemd_unit() {
    cat > "${RPMBUILD_DIR}/SOURCES/sshd.service" <<'EOF'
[Unit]
Description=OpenSSH server daemon
Documentation=man:sshd(8) man:sshd_config(5)
After=network.target auditd.service
ConditionPathExists=!/etc/ssh/sshd_not_to_be_run

[Service]
Type=simple
RuntimeDirectory=sshd
RuntimeDirectoryMode=0755
ExecStartPre=-/usr/bin/mkdir -p /run/sshd
ExecStartPre=/usr/bin/ssh-keygen -A
ExecStart=/usr/sbin/sshd -D
ExecReload=/bin/kill -HUP $MAINPID
KillMode=control-group
Restart=on-failure
RestartSec=3s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# ========================================================== SPEC 内容生成 ===
# 用「引用 heredoc + 占位符」生成 spec，避免 shell 提前展开 %post 里的 $1、
# %prep 里的 $(pwd)；占位符最后统一用 sed 替换。
write_spec_template() {
    cat > "${RPMBUILD_DIR}/SPECS/openssh.spec" <<'SPEC_EOF'
%global debug_package %{nil}

%define openssl_prefix /opt/openssl-static
%define privsep_path @PRIVSEP_PATH@
%define privsep_user @PRIVSEP_USER@

Name:           openssh
Version:        @OPENSSH_VERSION@
Release:        @RPM_RELEASE@%{?dist}
Summary:        OpenSSH @OPENSSH_VERSION@ with statically linked OpenSSL @OPENSSL_VERSION@
Source0:        @SSH_TAR@
@ASKPASS_SOURCE@
Source2:        sshd.pam
Source3:        @SSL_TAR@
Source4:        sshd.service
@PATCH_HEADER@
License:        BSD
Group:          Applications/Internet
BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  perl
BuildRequires:  zlib-devel
BuildRequires:  pam-devel
@BUILD_REQ_EXTRA@
Provides:       config(openssh) = %{version}-%{release}
@SUSE_FIPS_PROVIDE@
Requires:       systemd
Requires:       zlib
@SELINUX_REQ@
@PAM_REQ@
@LIBEDIT_REQ@

%description
OpenSSH @OPENSSH_VERSION@ with statically linked OpenSSL @OPENSSL_VERSION@.

%package server
Summary:        The OpenSSH server daemon
Requires:       openssh = %{version}-%{release}
Requires:       systemd
@PRE_SHADOW_REQ@
@SELINUX_REQ@

%description server
OpenSSH Server with static OpenSSL.

%package clients
Summary:        OpenSSH clients
Requires:       openssh = %{version}-%{release}

%description clients
OpenSSH Clients with static OpenSSL.

%prep
%setup -q
@PATCH_PREP@
@ASKPASS_PREP@

mkdir -p openssl_static
tar xfz %{SOURCE3} --strip-components=1 -C openssl_static
pushd openssl_static
./config --prefix=%{openssl_prefix} --libdir=lib -fPIC no-shared
make -j@JOBS@
make install_sw DESTDIR=$(pwd)/../openssl_install
popd

%build
%define openssl_install_path %{_builddir}/%{name}-%{version}/openssl_install%{openssl_prefix}
export LIBS='-lpthread -ldl -lz'
./configure \
    --prefix=/usr \
    --sysconfdir=/etc/ssh \
    --libexecdir=/usr/libexec/openssh \
    --with-ssl-dir=%{openssl_install_path} \
    --without-openssl-header-check \
    --with-zlib \
    --without-zlib-version-check \
    --with-pam \
    --with-privsep-path=%{privsep_path} \
    --with-privsep-user=%{privsep_user} \
    @SELINUX_OPT@ \
    @LIBEDIT_OPT@
# OpenSSH 10.x 只链接 libcrypto（不再使用 -lssl），把动态库替换为静态库
perl -pi -e 's|-lcrypto|%{openssl_install_path}/lib/libcrypto.a -lpthread -ldl -lz|g' Makefile
make -j@JOBS@

%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot}
install -m 755 contrib/ssh-copy-id %{buildroot}/usr/bin/
install -d -m 755 %{buildroot}%{_mandir}/@MANSUB@1
install -m 644 contrib/ssh-copy-id.1 %{buildroot}%{_mandir}/@MANSUB@1/
install -D -m 644 %{SOURCE2} %{buildroot}/etc/pam.d/sshd
mkdir -p %{buildroot}/usr/lib/systemd/system/
install -m 644 %{SOURCE4} %{buildroot}/usr/lib/systemd/system/sshd.service
rm -f %{buildroot}/usr/share/info/dir
# 本包以 --with-pam 编译并安装了 /etc/pam.d/sshd，而 OpenSSH 自带的 sshd_config
# 默认把 UsePAM 注释为 no，会让密码认证绕过 PAM 策略（faillock、审计等）。
# 这里显式打开；该文件是 %config(noreplace)，升级不会覆盖既有配置。
sed -i -e 's|^[#[:space:]]*UsePAM[[:space:]].*|UsePAM yes|' %{buildroot}/etc/ssh/sshd_config
@ASKPASS_INSTALL@
# 权限隔离目录：OpenSSH 默认是 /var/empty，会与 filesystem 包冲突，统一改为
# /var/empty/sshd；父目录由 filesystem 包提供，RPM 不会重复持有。
rm -rf %{buildroot}/var/empty
install -d -m 0755 %{buildroot}/var/empty
install -d -m 0700 %{buildroot}%{privsep_path}

%pre server
# 权限隔离用的低权限用户/组（OpenSSH 运行期必需）
getent group %{privsep_user} >/dev/null 2>&1 || groupadd -r %{privsep_user}
getent passwd %{privsep_user} >/dev/null 2>&1 || \
    useradd -g %{privsep_user} -r -s /sbin/nologin -d %{privsep_path} \
            -c "sshd privilege separation" %{privsep_user}
exit 0

%post server
# 生成主机密钥（缺失时），保证 sshd -t 与首次启动可用
if [ -x /usr/bin/ssh-keygen ]; then
    /usr/bin/ssh-keygen -A >/dev/null 2>&1 || :
fi
for key in /etc/ssh/ssh_host_*_key; do
    [ -f "$key" ] && chmod 600 "$key"
done
install -d -m 0755 /run/sshd 2>/dev/null || :
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || :
    systemctl enable sshd.service >/dev/null 2>&1 || :
fi
exit 0

%preun server
if [ "$1" -eq 0 ]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now sshd.service >/dev/null 2>&1 || :
    fi
fi
exit 0

%postun server
if [ "$1" -eq 0 ]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || :
    fi
fi
exit 0

%files
%defattr(-,root,root)
%config(noreplace) /etc/ssh/moduli
%config(noreplace) /etc/ssh/ssh_config
%config(noreplace) /etc/ssh/sshd_config
/usr/libexec/openssh/ssh-keysign
/usr/libexec/openssh/ssh-pkcs11-helper
/usr/libexec/openssh/ssh-sk-helper
@ASKPASS_FILES@
# man 页由 rpm 的 brp-man 脚本压缩成 *.gz，不同发行版压缩策略不同，
# 因此这里按「文件名 + 通配符」声明，兼容 .1 / .1.gz 两种形态。
# SUSE 系用 catN 子目录（cat1/cat5/cat8），其余发行版用 manN。
%{_mandir}/@MANSUB@1/ssh.1*
%{_mandir}/@MANSUB@1/scp.1*
%{_mandir}/@MANSUB@1/sftp.1*
%{_mandir}/@MANSUB@1/ssh-add.1*
%{_mandir}/@MANSUB@1/ssh-agent.1*
%{_mandir}/@MANSUB@1/ssh-keygen.1*
%{_mandir}/@MANSUB@1/ssh-keyscan.1*
%{_mandir}/@MANSUB@1/ssh-copy-id.1*
%{_mandir}/@MANSUB@5/ssh_config.5*
%{_mandir}/@MANSUB@5/sshd_config.5*
%{_mandir}/@MANSUB@5/moduli.5*
%{_mandir}/@MANSUB@8/sshd.8*
%{_mandir}/@MANSUB@8/sftp-server.8*
%{_mandir}/@MANSUB@8/ssh-keysign.8*
%{_mandir}/@MANSUB@8/ssh-pkcs11-helper.8*
%{_mandir}/@MANSUB@8/ssh-sk-helper.8*

%files server
%defattr(-,root,root)
/usr/lib/systemd/system/sshd.service
%config(noreplace) /etc/pam.d/sshd
/usr/sbin/sshd
/usr/libexec/openssh/sftp-server
/usr/libexec/openssh/sshd-session
/usr/libexec/openssh/sshd-auth
%dir %attr(0700,root,root) %{privsep_path}

%files clients
%defattr(-,root,root)
/usr/bin/ssh
/usr/bin/scp
/usr/bin/sftp
/usr/bin/ssh-add
/usr/bin/ssh-agent
/usr/bin/ssh-keygen
/usr/bin/ssh-keyscan
/usr/bin/ssh-copy-id

%clean
rm -rf %{buildroot}

%changelog
* Thu Jan 01 2026 OpenSSH RPM Builder <noreply@example.com> - @RPM_RELEASE@
- OpenSSH @OPENSSH_VERSION@ + static OpenSSL @OPENSSL_VERSION@
SPEC_EOF
}

# ------------------------------------------------- 可选特性与占位符计算 ---
detect_optional_features() {
    SELINUX_OPT="--without-selinux"
    SELINUX_REQ=""
    if [ -f /usr/include/selinux/selinux.h ] \
       || { have pkg-config && pkg-config --exists libselinux 2>/dev/null; }; then
        SELINUX_OPT="--with-selinux"
        SELINUX_REQ="Requires: libselinux"
    fi

    LIBEDIT_OPT=""
    LIBEDIT_REQ=""
    if [ -f /usr/include/histedit.h ] || [ -f /usr/include/editline/readline.h ]; then
        LIBEDIT_OPT="--with-libedit"
        LIBEDIT_REQ="Requires: libedit"
    fi

    PAM_REQ="Requires: pam"

    # man 页子目录：SUSE/openSUSE 系用 catN，其余发行版用 manN
    case " ${DISTRO_ID_LIKE} ${DISTRO_ID} " in
        *suse*) MANSUB="cat" ;;
        *)      MANSUB="man" ;;
    esac

    # SUSE 的 patterns-base-fips 模式带有条件依赖
    #   (openssh-fips if openssh-clients) / (openssh-fips if openssh-server)
    # 自建 openssh 包会触发该条件，导致 rpm 安装时被判定为依赖不满足。
    # 这里显式提供 openssh-fips 能力以满足这条条件依赖。
    SUSE_FIPS_PROVIDE=""
    case " ${DISTRO_ID_LIKE} ${DISTRO_ID} " in
        *suse*) SUSE_FIPS_PROVIDE="Provides:       openssh-fips" ;;
    esac

    # BuildRequires 只能声明镜像里确实装了的包，否则 rpmbuild 会因依赖不满足而中止
    # （例如 SLE 精简源里没有 perl-IPC-Cmd）。
    BUILD_REQ_EXTRA=""
    local pkg
    for pkg in perl-IPC-Cmd perl-devel perl-Time-Piece; do
        if rpm -q "$pkg" >/dev/null 2>&1; then
            BUILD_REQ_EXTRA="${BUILD_REQ_EXTRA}BuildRequires:  ${pkg}
"
        fi
    done

    # %pre 需要 useradd/groupadd，包名随发行版不同（EL 系 shadow-utils，SUSE 系 shadow）
    PRE_SHADOW_REQ=""
    if rpm -q shadow-utils >/dev/null 2>&1; then
        PRE_SHADOW_REQ="Requires(pre):  shadow-utils"
    elif rpm -q shadow >/dev/null 2>&1; then
        PRE_SHADOW_REQ="Requires(pre):  shadow"
    fi

    if [ "$HAS_ASKPASS" = "true" ] && [ -f /usr/include/X11/Xlib.h ]; then
        ASKPASS_ENABLED="true"
        ASKPASS_SOURCE="Source1: $(basename "$ASKPASS_TAR")"
        ASKPASS_BUILDRQ="BuildRequires: libXt-devel"
        ASKPASS_PREP="mkdir -p askpass_src
tar xfz %{SOURCE1} --strip-components=1 -C askpass_src
pushd askpass_src
./configure --prefix=/usr
make
popd"
        ASKPASS_INSTALL="install -m 755 askpass_src/ssh-askpass %{buildroot}/usr/libexec/openssh/ssh-askpass"
        ASKPASS_FILES="/usr/libexec/openssh/ssh-askpass"
    else
        if [ "$HAS_ASKPASS" = "true" ]; then
            warn "检测到 x11-ssh-askpass 但缺少 X11 开发头文件，跳过构建"
        fi
        ASKPASS_ENABLED="false"
        ASKPASS_SOURCE=""
        ASKPASS_BUILDRQ=""
        ASKPASS_PREP=""
        ASKPASS_INSTALL=""
        ASKPASS_FILES=""
    fi

    if [ "${UOS20:-0}" = "1" ] && [ -f "${BASE_DIR}/openssh-uos20-kernel-panic-fix.patch" ]; then
        PATCH_HEADER="Patch999: openssh-uos20-kernel-panic-fix.patch"
        PATCH_PREP="%patch999 -p0"
    else
        PATCH_HEADER=""
        PATCH_PREP=""
    fi
}

# 把值里的正则元字符转义，并保留换行（GNU sed 支持替换串里的 \n）
# 注意顺序：先转义反斜杠/&/|，再把真实换行转成 \n，否则新插入的 \n 会被二次转义。
sed_escape() {
    printf '%s' "$1" | sed -e ':a' -e 'N' -e '$!ba' -e 's/[\\&|]/\\&/g' -e 's/\n/\\n/g'
}

apply_spec_placeholders() {
    local spec="${RPMBUILD_DIR}/SPECS/openssh.spec"
    local key value
    while IFS='=' read -r key value; do
        [ -n "$key" ] || continue
        sed -i -e "s|@${key}@|$(sed_escape "$value")|g" "$spec"
    done <<PLACEHOLDERS
OPENSSH_VERSION=${OPENSSH_VERSION}
OPENSSL_VERSION=${OPENSSL_VERSION}
RPM_RELEASE=${RPM_RELEASE}
SSH_TAR=$(basename "$SSH_TAR")
SSL_TAR=$(basename "$SSL_TAR")
PRIVSEP_PATH=${PRIVSEP_PATH}
PRIVSEP_USER=${PRIVSEP_USER}
JOBS=${JOBS}
ASKPASS_SOURCE=${ASKPASS_SOURCE}
ASKPASS_BUILDRQ=${ASKPASS_BUILDRQ}
ASKPASS_PREP=${ASKPASS_PREP}
ASKPASS_INSTALL=${ASKPASS_INSTALL}
ASKPASS_FILES=${ASKPASS_FILES}
PATCH_HEADER=${PATCH_HEADER}
PATCH_PREP=${PATCH_PREP}
SELINUX_OPT=${SELINUX_OPT}
SELINUX_REQ=${SELINUX_REQ}
PAM_REQ=${PAM_REQ}
BUILD_REQ_EXTRA=${BUILD_REQ_EXTRA}
PRE_SHADOW_REQ=${PRE_SHADOW_REQ}
MANSUB=${MANSUB}
SUSE_FIPS_PROVIDE=${SUSE_FIPS_PROVIDE}
LIBEDIT_OPT=${LIBEDIT_OPT}
LIBEDIT_REQ=${LIBEDIT_REQ}
PLACEHOLDERS

    if grep -q '@[A-Z_]*@' "$spec"; then
        err "SPEC 中仍有未替换的占位符:"
        grep -o '@[A-Z_]*@' "$spec" | sort -u >&2
        return 1
    fi
    return 0
}

# ============================================================== 打包输出 ====
package_output() {
    local package_name="openssh-${OPENSSH_VERSION}-rpms-${OS_TAG}-${ARCH_TAG}"
    local tar_name="${package_name}.tar.gz"
    local stage="${OUTPUT_DIR}/${package_name}"

    mkdir -p "$OUTPUT_DIR"
    rm -rf "$stage"
    mkdir -p "$stage"

    cp "${RPMBUILD_DIR}/RPMS/${ARCH_TAG}"/*.rpm "$stage/" || {
        err "未找到构建产物: ${RPMBUILD_DIR}/RPMS/${ARCH_TAG}/*.rpm"
        return 1
    }
    if [ -f "${BASE_DIR}/install.sh" ]; then
        cp "${BASE_DIR}/install.sh" "$stage/"
        chmod 0755 "$stage/install.sh"
    fi
    if [ -f "${BASE_DIR}/README.md" ]; then
        cp "${BASE_DIR}/README.md" "$stage/"
    fi

    ( cd "$OUTPUT_DIR" && tar czf "$tar_name" "$package_name" ) || return 1
    rm -rf "$stage"
    printf '%s' "$tar_name"
}

# ================================================================ 主流程 ====
print_banner() {
    printf '%s%s%s\n' "$C_WHITE" "========================================================================" "$C_RESET"
    printf '%s                %sOpenSSH RPM Builder%s %s%s%s by %s%s%s\n' \
        "$C_WHITE" "$C_BOLD" "$C_RESET" "$C_YELLOW" "$SCRIPT_VERSION" "$C_RESET" "$C_YELLOW" "$SCRIPT_AUTHOR" "$C_RESET"
    printf '%s%s%s\n' "$C_WHITE" "========================================================================" "$C_RESET"
    printf ' 📦 OpenSSH 源码 : %s%s%s (v%s)\n' "$C_GREEN" "${SSH_TAR##*/}" "$C_RESET" "$OPENSSH_VERSION"
    printf ' 🔒 OpenSSL 源码 : %s%s%s (v%s)\n' "$C_GREEN" "${SSL_TAR##*/}" "$C_RESET" "$OPENSSL_VERSION"
    if [ "$ASKPASS_ENABLED" = "true" ]; then
        printf ' 🔑 Askpass 源码 : %s%s%s\n' "$C_GREEN" "${ASKPASS_TAR##*/}" "$C_RESET"
    else
        printf ' 🔑 Askpass 源码 : %s未构建%s\n' "$C_GREY" "$C_RESET"
    fi
    printf ' 🖥  目标系统     : %s%s%s (%s)\n' "$C_GREEN" "$OS_TAG" "$C_RESET" "$DISTRO_PRETTY"
    printf ' 🏷  RPM dist    : %s%s%s\n' "$C_GREEN" "${RPM_DIST:-未定义}" "$C_RESET"
    printf ' 🏗  架构        : %s%s%s\n' "$C_GREEN" "$ARCH_TAG" "$C_RESET"
    printf ' 📂 输出路径     : %s%s%s\n' "$C_GREEN" "$OUTPUT_DIR" "$C_RESET"
    printf ' 📝 日志路径     : %s%s%s\n' "$C_GREEN" "$LOG_DIR" "$C_RESET"
    printf '%s%s%s\n\n' "$C_WHITE" "========================================================================" "$C_RESET"
}

maybe_install_deps() {
    local choice=""
    if [ "$AUTO_DEPS" = "1" ]; then
        choice="1"
    elif [ ! -t 0 ]; then
        choice="2"
    else
        show_cursor
        printf '   %s--------------------------------------------%s\n' "$C_GREY" "$C_RESET"
        printf '   1) %s安装%s\n' "$C_GREEN" "$C_RESET"
        printf '   2) %s跳过%s\n' "$C_YELLOW" "$C_RESET"
        printf '   %s--------------------------------------------%s\n' "$C_GREY" "$C_RESET"
        read -r -p "   请输入选项 [1-2]: " choice || choice="2"
        hide_cursor
    fi

    if [ "$choice" = "1" ]; then
        CURRENT_STEP="安装依赖组件"
        install_build_deps >"${LOG_DIR}/01_deps.log" 2>&1 || warn "依赖安装存在问题，详见 ${LOG_DIR}/01_deps.log"
    else
        printf '   -> %s跳过依赖安装%s\n' "$C_YELLOW" "$C_RESET"
    fi
}

main() {
    parse_args "$@"
    mkdir -p "$LOG_DIR" || { err "无法创建日志目录 ${LOG_DIR}"; exit "$EXIT_PREREQ"; }
    hide_cursor

    detect_distro
    RPM_DIST="$(detect_rpm_dist || true)"
    OS_TAG="${FORCE_OS_TAG:-}"
    if [ -z "$OS_TAG" ]; then
        OS_TAG="$(get_os_tag || true)"
    fi
    [ -n "$OS_TAG" ] || { err "无法识别当前发行版，请用 FORCE_OS_TAG 指定标签"; exit "$EXIT_PREREQ"; }

    ARCH_TAG="$(get_arch)" || exit "$EXIT_PREREQ"

    detect_source_files || exit "$EXIT_SOURCE"
    detect_optional_features

    print_banner

    CURRENT_STEP="依赖检查"
    maybe_install_deps

    if ! have rpmbuild || ! have gcc || ! have make; then
        err "缺少构建工具（rpmbuild/gcc/make），请先安装依赖后重试"
        exit "$EXIT_PREREQ"
    fi

    CURRENT_STEP="初始化 rpmbuild 目录"
    run_task "初始化 rpmbuild 目录" "02_init_dir.log" \
        rm -rf "$RPMBUILD_DIR" || exit "$EXIT_BUILD"
    mkdir -p "${RPMBUILD_DIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    CURRENT_STEP="准备源码文件"
    run_task "准备源码文件" "03_copy_src.log" \
        cp -f "$SSH_TAR" "${RPMBUILD_DIR}/SOURCES/" || exit "$EXIT_BUILD"
    run_task "准备 OpenSSL 源码" "03b_copy_ssl.log" \
        cp -f "$SSL_TAR" "${RPMBUILD_DIR}/SOURCES/" || exit "$EXIT_BUILD"
    if [ "$ASKPASS_ENABLED" = "true" ]; then
        run_task "准备 askpass 源码" "03c_copy_askpass.log" \
            cp -f "$ASKPASS_TAR" "${RPMBUILD_DIR}/SOURCES/" || exit "$EXIT_BUILD"
    fi
    if [ -n "$PATCH_HEADER" ]; then
        run_task "准备补丁文件" "03d_copy_patch.log" \
            cp -f "${BASE_DIR}/openssh-uos20-kernel-panic-fix.patch" "${RPMBUILD_DIR}/SOURCES/" \
            || exit "$EXIT_BUILD"
    fi

    CURRENT_STEP="生成 SPEC 配置文件"
    write_pam_file
    write_systemd_unit
    write_spec_template
    apply_spec_placeholders || { err "SPEC 生成失败"; exit "$EXIT_BUILD"; }

    CURRENT_STEP="编译并打包 RPM"
    trap on_interrupt INT TERM
    if ! run_task "${C_YELLOW}[极速模式]${C_RESET} ${C_BLUE}编译并打包 RPM${C_RESET}" "04_rpmbuild.log" \
        rpmbuild -bb --define "_topdir ${RPMBUILD_DIR}" "${RPMBUILD_DIR}/SPECS/openssh.spec"; then
        err "rpmbuild 失败，完整日志：${LOG_DIR}/04_rpmbuild.log"
        exit "$EXIT_BUILD"
    fi
    trap on_interrupt INT TERM

    CURRENT_STEP="整理并压缩安装包"
    if ! TAR_NAME="$(package_output)"; then
        err "打包失败"
        exit "$EXIT_PACKAGE"
    fi

    if [ "$KEEP_WORKDIR" != "1" ]; then
        rm -rf "$LOG_DIR" "$RPMBUILD_DIR"
    fi

    show_cursor
    printf '\n%s%s%s\n' "$C_WHITE" "========================================================================" "$C_RESET"
    printf ' 🎉 %s构建成功！%s\n' "$C_GREEN" "$C_RESET"
    printf ' 📦 文件位置: %s%s/%s%s\n' "$C_WHITE" "$OUTPUT_DIR" "$TAR_NAME" "$C_RESET"
    printf '%s%s%s\n' "$C_WHITE" "========================================================================" "$C_RESET"
    ls -lh "${OUTPUT_DIR}/${TAR_NAME}" 2>/dev/null || true
    exit "$EXIT_OK"
}

main "$@"
