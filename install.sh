#!/bin/sh
#===============================================================================
# Name:        install.sh
# Description: 安装随包提供的 OpenSSH RPM，并校验配置后重启 sshd 服务
# Usage:       ./install.sh [--no-restart]
#              ./install.sh --self-test
# Exit Codes:  0=成功 1=运行失败 2=前置条件不满足 3=配置校验失败
#
# 环境变量:
#   SSHD_CONFIG        sshd 配置文件路径，默认 /etc/ssh/sshd_config
#   ALLOW_ROOT_PASSWORD=1  安装后允许 root 密码登录
#   DISABLE_SELINUX=1      安装后关闭 SELinux（需重启生效）
#===============================================================================
set -eu

EXIT_OK=0
EXIT_FAIL=1
EXIT_PREREQ=2
EXIT_CONFIG=3
EXIT_USAGE=4

# shellcheck disable=SC1007  # CDPATH= 前缀用于避免 cd 打印目录名
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
SSHD_CONFIG=${SSHD_CONFIG:-/etc/ssh/sshd_config}
BACKUP_TIME=$(date +%Y%m%d%H%M%S)
DO_RESTART=1

die() {
    echo "ERROR: $*" >&2
    exit "$EXIT_FAIL"
}

log() {
    echo "==> $*" >&2
}

backup_file() {
    file=$1
    [ -f "$file" ] || return 0
    backup="${file}.bak.${BACKUP_TIME}"
    cp -p "$file" "$backup"
    echo "已备份: $backup"
}

set_sshd_option() {
    key=$1
    value=$2
    tmp="${SSHD_CONFIG}.tmp.$$"
    awk -v key="$key" -v value="$value" '
        BEGIN { done = 0; in_match = 0; wanted = tolower(key) }
        {
            active = $0
            sub(/^[[:space:]]*/, "", active)
            split(active, active_fields, /[[:space:]]+/)
            active_key = tolower(active_fields[1])

            normalized = active
            sub(/^#[[:space:]]*/, "", normalized)
            split(normalized, fields, /[[:space:]]+/)
            current_key = tolower(fields[1])
        }
        !in_match && (active_key == "include" || active_key == "match") {
            if (!done) print key " " value
            done = 1
            if (active_key == "match") in_match = 1
        }
        !in_match && current_key == wanted {
            if (!done) print key " " value
            done = 1
            next
        }
        { print }
        END { if (!done) print key " " value }
    ' "$SSHD_CONFIG" > "$tmp"
    cat "$tmp" > "$SSHD_CONFIG"
    rm -f "$tmp"
}

disable_selinux_config() {
    file=$1
    [ -f "$file" ] || return 0
    backup_file "$file"
    if grep -q '^[[:space:]]*SELINUX=' "$file"; then
        sed -i 's/^[[:space:]]*SELINUX=.*/SELINUX=disabled/' "$file"
    else
        echo 'SELINUX=disabled' >> "$file"
    fi
}

generate_host_keys() {
    # sshd -t 需要主机密钥存在，否则新装机器上校验会失败
    if ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
        return 0
    fi
    if [ -x /usr/bin/ssh-keygen ]; then
        log "生成缺失的主机密钥 ..."
        /usr/bin/ssh-keygen -A >/dev/null 2>&1 || true
    fi
}

restart_sshd() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
        systemctl restart sshd
    elif command -v service >/dev/null 2>&1; then
        service sshd restart
    elif [ -x /etc/init.d/sshd ]; then
        /etc/init.d/sshd restart
    else
        die "未找到 sshd 服务管理命令（systemctl/service/init.d）"
    fi
}

run_self_test() {
    test_dir=$(mktemp -d)
    trap 'rm -rf "$test_dir"' 0
    SSHD_CONFIG="$test_dir/sshd_config"
    BACKUP_TIME="test"
    printf '%s\n' 'include /etc/ssh/sshd_config.d/*.conf' 'permitrootlogin no' \
        'passwordauthentication no' 'match User backup' \
        '    passwordauthentication no' > "$SSHD_CONFIG"
    set_sshd_option PermitRootLogin yes
    set_sshd_option PasswordAuthentication yes
    [ "$(grep -c '^PermitRootLogin yes$' "$SSHD_CONFIG")" -eq 1 ]
    [ "$(grep -c '^PasswordAuthentication yes$' "$SSHD_CONFIG")" -eq 1 ]
    [ "$(sed -n '1p' "$SSHD_CONFIG")" = 'PermitRootLogin yes' ]
    [ "$(sed -n '2p' "$SSHD_CONFIG")" = 'PasswordAuthentication yes' ]
    grep -q '^    passwordauthentication no$' "$SSHD_CONFIG"
    printf '%s\n' 'SELINUX=enforcing' > "$test_dir/selinux"
    disable_selinux_config "$test_dir/selinux"
    grep -q '^SELINUX=disabled$' "$test_dir/selinux"
    echo "install.sh self-test passed"
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --self-test) run_self_test ;;
        --no-restart) DO_RESTART=0 ;;
        -h|--help)
            echo "用法: $0 [--no-restart] [--self-test]"
            exit "$EXIT_OK"
            ;;
        *) echo "未知参数: $1" >&2; exit "$EXIT_USAGE" ;;
    esac
    shift
done

[ "$(id -u)" -eq 0 ] || die "请使用 root 运行此脚本"
command -v rpm >/dev/null 2>&1 || { echo "ERROR: 未找到 rpm 命令" >&2; exit "$EXIT_PREREQ"; }

set -- "$SCRIPT_DIR"/*.rpm
[ -f "$1" ] || die "当前安装包中未找到 RPM 文件"

log "即将升级 OpenSSH；请保持当前 SSH 会话，并准备备用登录通道。"
backup_file "$SSHD_CONFIG"
rpm -Uvh --replacefiles "$@"

[ -f "$SSHD_CONFIG" ] || die "未找到 $SSHD_CONFIG"

if [ "${ALLOW_ROOT_PASSWORD:-0}" = "1" ]; then
    set_sshd_option PermitRootLogin yes
    set_sshd_option PasswordAuthentication yes
    echo "已启用 root 密码登录"
fi

if [ "${DISABLE_SELINUX:-0}" = "1" ]; then
    disable_selinux_config /etc/selinux/config
    disable_selinux_config /etc/sysconfig/selinux
    setenforce 0 2>/dev/null || true
    echo "已禁用 SELinux；永久生效需要重启系统"
fi

for key in /etc/ssh/ssh_host_*_key; do
    if [ -f "$key" ]; then
        chmod 600 "$key"
    fi
done

generate_host_keys

SSHD_BIN=$(command -v sshd 2>/dev/null || true)
[ -n "$SSHD_BIN" ] || SSHD_BIN=/usr/sbin/sshd
[ -x "$SSHD_BIN" ] || die "未找到 sshd"

if ! "$SSHD_BIN" -t; then
    if [ -f "${SSHD_CONFIG}.bak.${BACKUP_TIME}" ]; then
        cp -p "${SSHD_CONFIG}.bak.${BACKUP_TIME}" "$SSHD_CONFIG"
    fi
    echo "ERROR: sshd 配置校验失败，已恢复安装前配置，服务未重启" >&2
    exit "$EXIT_CONFIG"
fi

if [ "$DO_RESTART" -eq 1 ]; then
    restart_sshd
else
    log "已跳过服务重启（--no-restart）"
fi

if [ -x /usr/bin/ssh ]; then
    /usr/bin/ssh -V 2>&1 || true
fi
echo "OpenSSH 安装完成"
exit "$EXIT_OK"
