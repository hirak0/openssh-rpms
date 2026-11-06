# OpenSSH RPM 一键打包（Docker 多发行版）

[![license](https://img.shields.io/badge/license-BSD--2--Clause-green?style=flat)](https://github.com/openssh/openssh-portable/blob/master/LICENSE)
[![version](https://img.shields.io/badge/version-10.6p2-green?style=flat)](https://www.openssh.com/txt/release-10.6)
[![build](https://github.com/hirak0/openssh-rpms/actions/workflows/build-openssh.yml/badge.svg)](https://github.com/openssh-rpms-by-hirak0/openssh-rpms/actions/workflows/build-openssh.yml)
[![docker](https://img.shields.io/badge/docker-24+-blue?style=flat)](https://docs.docker.com/get-docker/)
[![openssl](https://img.shields.io/badge/OpenSSL-3.5%20LTS-lightgrey?style=flat)](https://www.openssl.org/source/)

> 把 **OpenSSH 10.6p2** 源码编译成目标发行版可安装的 **RPM** 包，并**静态链接 OpenSSL 3.5 LTS**。
> 一条命令即可在 Windows / macOS / Linux 上为 CentOS、Rocky、AlmaLinux、Oracle Linux、openEuler、
> openCloudOS、Anolis OS、银河麒麟、UOS、Amazon Linux、SUSE LE 等 **25 个目标**产出 RPM 包。

典型场景：在信创/老旧发行版上，系统自带的 OpenSSL 太旧（缺 `libcrypto.so.1.1`）或 OpenSSH 存在已知 CVE，
但又无法升级整套系统——本项目产出的 RPM 把新版 OpenSSL 静态链接进去，**不依赖系统 OpenSSL 动态库**。

---

## 📖 目录

- [✨ 核心特性](#-核心特性)
- [🛠 技术栈](#-技术栈)
- [📋 环境要求](#-环境要求)
- [🚀 快速开始](#-快速开始)
- [🖥 支持的目标系统](#-支持的目标系统)
- [🏗 架构概览](#-架构概览)
- [🔧 环境变量](#-环境变量)
- [📝 脚本与参数](#-脚本与参数)
- [📦 安装到目标机器](#-安装到目标机器)
- [🔄 CI/CD 自动构建](#-cicd-自动构建)
- [⚡ 构建加速](#-构建加速)
- [🔒 安全说明](#-安全说明)
- [🧪 验证与自检](#-验证与自检)
- [🔧 故障排除](#-故障排除)
- [📝 变更日志](#-变更日志)
- [🤝 贡献指南](#-贡献指南)
- [📄 许可证](#-许可证)
- [🙏 致谢](#-致谢)

---

## ✨ 核心特性

| 能力 | 说明 |
| --- | --- |
| 🐧 **多发行版** | 25 个目标系统：EL 7/8/9/10 系、openEuler、openCloudOS、Anolis OS、麒麟、UOS、Amazon Linux、SUSE LE |
| 🔒 **静态 OpenSSL** | `no-shared` 编译 OpenSSL 3.5 LTS 并静态链接，运行时不需要系统的 `libssl`/`libcrypto` |
| 📦 **三包拆分** | `openssh` / `openssh-server` / `openssh-clients`，与发行版原生包命名一致，可直接覆盖升级 |
| 🛡️ **权限隔离规范** | 隔离目录统一为 `/var/empty/sshd`（0700），不与 `filesystem` 包的 `/var/empty` 冲突 |
| 👤 **自动建用户** | `%pre` 脚本自动创建 `sshd` 低权限用户与用户组（OpenSSH 10.x 必需） |
| 🔑 **主机密钥自动生成** | `%post` 调用 `ssh-keygen -A`，安装后 `sshd -t` 立即可用，无需人工干预 |
| 🧩 **可选特性自动探测** | 按镜像实际内容决定是否启用 SELinux、libedit、x11-ssh-askpass，并补齐对应运行期依赖 |
| 🧹 **工程化脚本** | `set -Eeuo pipefail` + 退出码契约 + `trap` 清理，**零 `eval`**，shellcheck 零告警 |
| 🐳 **一条命令** | Docker 化，宿主机无需任何编译工具链；镜像构建层可缓存 |
| 🔁 **CI 矩阵自动生成** | 目标清单一行一个发行版，矩阵 JSON 自动生成，产物数量自动校验 |

---

## 🛠 技术栈

### 源码与依赖

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| **OpenSSH** | 10.6p2 | 待编译主体，支持 9.x / 10.x |
| **OpenSSL** | 3.5.9（LTS） | 静态链接，提供 `libcrypto.a` / `libssl.a` |
| **zlib** | 发行版自带 | 压缩支持（`--with-zlib`） |
| **PAM** | 发行版自带 | 服务端认证（`--with-pam`） |
| **x11-ssh-askpass** | 可选 | 存在源码包且镜像有 X11 头文件时，自动构建 GUI 口令框 |

### 工具链

| 组件 | 版本 | 用途 |
| --- | --- | --- |
| **Bash** | 4+ | 构建脚本解释器（`build_openssh.sh` / `build.sh`） |
| **POSIX sh** | 任意 | 安装脚本解释器（`install.sh`） |
| **rpm-build** | 4.11+（EL7）/ 4.14（SLE15） | RPM 打包 |
| **gcc / make / perl** | 发行版自带 | 编译 |
| **Docker** | 24+ | 编译环境隔离（宿主机无需装依赖） |
| **GitHub Actions** | - | 每日自动构建 + 发布 Release |

### 基础设施

- **容器**：Docker / BuildKit（`--platform` 支持 `linux/amd64`、`linux/arm64`）
- **CI/CD**：GitHub Actions（`resolve` → `sources` → `plan` → `build` → `release`）
- **静态检查**：shellcheck（脚本）、actionlint（Workflow）

---

## 📋 环境要求

### 必需（使用 Docker 方案时）

- **Docker Engine**：24.x 或更高版本
- **宿主机**：Linux / macOS / Windows（Windows 10+ 需启用 WSL2 后端）
- **磁盘**：约 3 GB 可用空间（容器镜像 + 源码 + 中间产物）
- **网络**：能访问 Docker Hub 与源码镜像站

### 必需（不使用 Docker、直接在目标机编译时）

- **rpm-build**：提供 `rpmbuild`
- **gcc / gcc-c++ / make / perl**
- **zlib-devel / pam-devel**
- **tar / gzip / patch / which / findutils**
- **root 权限**：需要写入 `%{_topdir}` 与安装运行期脚本

### 可选

- **x11-ssh-askpass 源码包**：用于构建 GUI 口令框
- **libedit-devel**：启用 sftp 行编辑增强（缺失时自动降级）
- **libselinux-devel**：启用 sshd 的 SELinux 支持（缺失时自动降级）
- **libXt-devel**：编译 askpass 所需

---

## 🚀 快速开始

### 1. 获取源码包

把下列文件放进本仓库根目录（版本组合与 CI 保持一致，最省心）：

```bash
# OpenSSH 10.6p2 —— 官方发布页提供 SHA256 校验
curl -LO https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.6p2.tar.gz
curl -LO https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.6p2.tar.gz.asc
curl -LO https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/RELEASE_KEY.asc

# OpenSSL 3.5.9（LTS）—— GitHub Release 资产
curl -LO https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz

# 可选：GUI 口令框（文件名必须以 x11-ssh-askpass- 开头，脚本据此探测）
curl -LO https://github.com/matthewpow/openssh-askpass/releases/download/v1.2.2/x11-ssh-askpass-1.2.2.tar.gz
```

> ⚠️ 请务必核对 SHA256。CI 流程会自动校验 OpenSSH 的 GPG 签名与 OpenSSL 的官方摘要，
> 本地手动下载时请自行比对 <https://www.openssh.com/txt/release-10.6>。

### 2. 一键编译（推荐：Docker）

```bash
git clone https://github.com/hirak0/openssh-rpms.git
cd openssh-rpms

# 默认使用 rockylinux:9 编译
bash build.sh
```

构建过程输出示例：

```text
========================================================================
                OpenSSH RPM Builder v3.0 by hirak0
========================================================================
 📦 OpenSSH 源码 : openssh-10.6p2.tar.gz (v10.6p2)
 🔒 OpenSSL 源码 : openssl-3.5.9.tar.gz (v3.5.9)
 🏗  架构        : x86_64
 📂 输出路径     : /opt
========================================================================

   Target: 初始化 rpmbuild 目录 ... [OK] (0s)
   Target: 准备源码文件 ... [OK] (0s)
   Target: 准备 OpenSSL 源码 ... [OK] (0s)
   Target: [极速模式] 编译并打包 RPM ... [OK] (94s)

========================================================================
 🎉 构建成功！📦 文件位置: /opt/openssh-10.6p2-rpms-el9-x86_64.tar.gz
========================================================================
```

### 3. 指定目标系统

```bash
# Rocky Linux 9
bash build.sh -i rockylinux/rockylinux:9 -t el9

# AlmaLinux 10
bash build.sh -i almalinux:10 -t el10

# openEuler 24.03 LTS SP2
bash build.sh -i openeuler/openeuler:24.03-lts-sp2 -t oe2403sp2

# SUSE Linux Enterprise 15 SP6
bash build.sh -i registry.suse.com/suse/sle15:15.6 -t sle15

# 银河麒麟 V10 SP3（使用你拿到的麒麟基础镜像）
bash build.sh -i <kylin-v10-sp3镜像名> -t ky10sp3
```

不指定 `-t` 时，脚本会按镜像名自动推断系统标签：

| 镜像名匹配 | 推断标签 |
| --- | --- |
| `centos:7` / `*el7*` | `el7` |
| `centos:8` / `rockylinux:8` / `almalinux:8` | `el8` |
| `centos:9` / `rockylinux:9` / `almalinux:9` / `ubi9` | `el9` |
| `rockylinux:10` / `almalinux:10` | `el10` |
| `*kylin*` / `*ky10*` | `ky10` |
| `*openeuler*24.03*` | `oe2403` |
| `*openeuler*22.03*` | `oe2203` |
| `*opencloudos*` | `oc9` |
| `*anolis*8` | `an8` |
| `*amazonlinux:2023*` | `amzn2023` |
| `*sle15*` | `sle15` |
| 其他 | `custom` |

### 4. 交叉编译 aarch64（可选）

在 x86 机器上为 ARM 服务器（鲲鹏 / 飞腾 / 海光）交叉编译：

```bash
# 首次：安装 QEMU 模拟器（一次性）
docker run --privileged --rm tonistiigi/binfmt --install arm64

# 交叉编译
bash build.sh -p linux/arm64 -i rockylinux/rockylinux:9 -t el9
```

> QEMU 模拟下编译 OpenSSL + OpenSSH 需要 1-3 小时。若有 ARM 服务器，直接在 ARM 机器上
> 用多架构镜像编译即可（去掉 `-p`），速度是 QEMU 的数倍。

### 5. 直接在目标系统内编译（无 Docker）

```bash
# EL / openEuler / 麒麟 / UOS 等 yum 系
yum install -y rpm-build gcc gcc-c++ make perl zlib-devel pam-devel perl-devel
bash build_openssh.sh
```

```bash
# SUSE 系
zypper --non-interactive install -y rpm-build gcc gcc-c++ make perl zlib-devel pam-devel
bash build_openssh.sh
```

脚本会自动探测发行版、架构与系统标签；无法识别时用 `FORCE_OS_TAG` 手动指定：

```bash
FORCE_OS_TAG=el9 bash build_openssh.sh
```

### 6. 取产物

| 场景 | 产物位置 |
| --- | --- |
| `build.sh`（Docker） | `./output/openssh-<版本>-rpms-<标签>-<架构>.tar.gz` |
| `build_openssh.sh`（本机） | `$OUTPUT_DIR/openssh-<版本>-rpms-<标签>-<架构>.tar.gz`，默认 `/opt` |

压缩包内容：

```text
openssh-10.6p2-rpms-el9-x86_64/
├── openssh-10.6p2-1.el9.x86_64.rpm
├── openssh-clients-10.6p2-1.el9.x86_64.rpm
├── openssh-server-10.6p2-1.el9.x86_64.rpm
├── install.sh          # 一键安装脚本
└── README.md
```

---

## 🖥 支持的目标系统

CI 每天自动构建以下 **25 个目标 × 2 个架构 = 50 个 RPM 包**：

| 系统 | x86_64 | aarch64 | 产物标签 | 基础镜像 |
| --- | :---: | :---: | --- | --- |
| CentOS 7 | ✅ | ✅ | `el7` | `centos:7` |
| CentOS Stream 8 | ✅ | ✅ | `el8` | `quay.io/centos/centos:stream8` |
| CentOS Stream 9 | ✅ | ✅ | `el9` | `quay.io/centos/centos:stream9` |
| CentOS Stream 10 | ✅ | ✅ | `el10` | `quay.io/centos/centos:stream10` |
| Rocky Linux 8 | ✅ | ✅ | `el8` | `rockylinux/rockylinux:8` |
| Rocky Linux 9 | ✅ | ✅ | `el9` | `rockylinux/rockylinux:9` |
| Rocky Linux 10 | ✅ | ✅ | `el10` | `rockylinux/rockylinux:10` |
| AlmaLinux 8 | ✅ | ✅ | `el8` | `almalinux:8` |
| AlmaLinux 9 | ✅ | ✅ | `el9` | `almalinux:9` |
| AlmaLinux 10 | ✅ | ✅ | `el10` | `almalinux:10` |
| Oracle Linux 8 | ✅ | ✅ | `el8` | `oraclelinux:8` |
| Oracle Linux 9 | ✅ | ✅ | `el9` | `oraclelinux:9` |
| openEuler 22.03 LTS | ✅ | ✅ | `oe2203` | `openeuler/openeuler:22.03-lts` |
| openEuler 24.03 LTS SP1 | ✅ | ✅ | `oe2403sp1` | `openeuler/openeuler:24.03-lts-sp1` |
| openEuler 24.03 LTS SP2 | ✅ | ✅ | `oe2403sp2` | `openeuler/openeuler:24.03-lts-sp2` |
| openEuler 24.03 LTS SP3 | ✅ | ✅ | `oe2403sp3` | `openeuler/openeuler:24.03-lts-sp3` |
| openEuler 24.03 LTS SP4 | ✅ | ✅ | `oe2403sp4` | `openeuler/openeuler:24.03-lts-sp4` |
| openCloudOS 9 | ✅ | ✅ | `oc9` | `opencloudos/opencloudos:9` |
| Anolis OS 8 | ✅ | ✅ | `an8` | `openanolis/anolis:8` |
| Amazon Linux 2023 | ✅ | ✅ | `amzn2023` | `amazonlinux:2023` |
| SUSE Linux Enterprise 15 SP6 | ✅ | ✅ | `sle15` | `registry.suse.com/suse/sle15:15.6` |
| 银河麒麟 V10 SP1 | ✅ | ✅ | `ky10sp1` | `hxsoong/kylin`（固定 digest） |
| 银河麒麟 V10 SP2 | ✅ | ✅ | `ky10sp2` | `hxsoong/kylin`（固定 digest） |
| 银河麒麟 V10 SP3 | ✅ | ✅ | `ky10sp3` | `hxsoong/kylin`（固定 digest） |
| UOS 20 兼容包 | ✅ | ✅ | `uos20` | `quay.io/centos/centos:stream8` + 内核补丁 |

### 发行版适配说明

| 适配点 | 说明 |
| --- | --- |
| **权限隔离目录** | 统一 `/var/empty/sshd`（0700）。上游默认 `/var/empty` 会被 `filesystem` 包占用，导致 RPM 文件冲突 |
| **man 页子目录** | EL 系用 `manN`，SUSE 系用 `catN`，脚本按 `ID_LIKE` 自动选择 |
| **man 页压缩** | rpm 的 `brp-man` 会把 man 页压成 `*.gz`，`%files` 使用 `文件名*` 通配以兼容两种形态 |
| **rpmbuild 根目录** | 跟随 `%{_topdir}`：EL 系 `/root/rpmbuild`，SUSE 系 `/usr/src/packages` |
| **BuildRequires** | 只声明镜像里确实已安装的包，避免精简源（如 `SLE_BCI`）缺失可选包导致构建中止 |
| **shadow 包名** | `%pre` 需要 `useradd`/`groupadd`，EL 系包名 `shadow-utils`，SUSE 系 `shadow`，脚本自动识别 |
| **SUSE FIPS 模式** | SLE 的 `patterns-base-fips` 带条件依赖 `(openssh-fips if openssh-clients)`，本包显式 `Provides: openssh-fips` 满足它 |
| **CentOS 7 / Stream 8 源** | 已 EOL，Dockerfile 会按可用性依次尝试阿里云 / 清华 / 华为云 / 官方 vault 镜像 |

---

## 🏗 架构概览

### 目录结构

```text
openssh-rpms/
├── build.sh                     # ★ Docker 一键编译入口（宿主机执行）
├── build_openssh.sh             # ★ 容器内主构建脚本：探测 → 生成 SPEC → rpmbuild → 打包
├── install.sh                   # ★ 产物内的一键安装脚本（目标机执行）
├── Dockerfile                   # 多发行版通用编译镜像（dnf/yum/microdnf/zypper 自适应）
├── .github/
│   └── workflows/
│       ├── build-openssh.yml    # 主 CI：版本解析 → 签名校验 → 矩阵构建 → 发布 Release
│       └── docker-publish.yml   # 编译镜像发布到 ghcr.io（含 cosign 签名）
└── .gitignore
```

### 构建流水线

```text
宿主机                        容器内（目标发行版）                    产物
──────                        ────────────────────                    ────
build.sh
  ├─ 探测源码包
  ├─ docker build ──────────► Dockerfile
  │                            ├─ 修复 EOL 源（CentOS 7 / Stream 8）
  │                            └─ 安装编译依赖（按包管理器自适应）
  └─ docker run ────────────► build_openssh.sh
                               ├─ detect_distro()     识别发行版
                               ├─ get_os_tag()        推导系统标签
                               ├─ get_arch()          推导架构
                               ├─ detect_source_files() 探测 openssh/openssl/askpass
                               ├─ detect_optional_features() 探测 SELinux/libedit/askpass
                               ├─ write_spec_template()   生成 SPEC
                               ├─ apply_spec_placeholders() 替换占位符
                               ├─ rpmbuild -bb ───────► %prep → %build → %install
                               │                          ├─ 编译静态 OpenSSL
                               │                          ├─ configure + make OpenSSH
                               │                          └─ 安装到 buildroot
                               └─ package_output() ──────────────────────────► output/*.tar.gz
```

### SPEC 各阶段做了什么

| 阶段 | 关键动作 |
| --- | --- |
| `%prep` | 解包 OpenSSH；编译**静态** OpenSSL（`./config --prefix=/opt/openssl-static no-shared`）到 `openssl_install`；应用 UOS 补丁；可选构建 askpass |
| `%build` | `./configure --with-ssl-dir=<静态 OpenSSL>`；把 Makefile 里的 `-lcrypto` 替换为 `libcrypto.a` 绝对路径；`make -j` |
| `%install` | `make install DESTDIR=`；安装 `ssh-copy-id`、PAM 文件、systemd 单元；创建 `/var/empty/sshd`（0700）；把 `sshd_config` 的 `UsePAM` 打开 |
| `%pre server` | 创建 `sshd` 低权限用户与用户组 |
| `%post server` | `ssh-keygen -A` 生成主机密钥；`chmod 600`；创建 `/run/sshd`；`systemctl daemon-reload` + `enable sshd` |
| `%files` | 三包拆分；man 页用 `文件名*` 通配；`%dir %attr(0700,root,root) /var/empty/sshd` |

### 产物包拆分

| 包 | 内容 |
| --- | --- |
| `openssh` | 公共文件：`/etc/ssh/{ssh_config,sshd_config,moduli}`、`ssh-keysign`、`ssh-pkcs11-helper`、`ssh-sk-helper`、man 页 |
| `openssh-server` | `/usr/sbin/sshd`、`sshd-session`、`sshd-auth`、`sftp-server`、`/etc/pam.d/sshd`、`sshd.service`、`/var/empty/sshd` |
| `openssh-clients` | `ssh`、`scp`、`sftp`、`ssh-add`、`ssh-agent`、`ssh-keygen`、`ssh-keyscan`、`ssh-copy-id` |

### 运行期依赖（由 RPM 自动声明）

| 依赖 | 来源 | 说明 |
| --- | --- | --- |
| `zlib` | `--with-zlib` | 动态链接压缩库 |
| `pam` | `--with-pam` | 服务端认证栈 |
| `libedit` | `--with-libedit` | sftp 行编辑（检测到才声明） |
| `libselinux` | `--with-selinux` | SELinux 支持（检测到才声明） |
| `systemd` | `sshd.service` | 服务管理 |
| `shadow-utils` / `shadow` | `%pre` 建用户 | 包名随发行版不同 |

> **注意**：OpenSSL 是**静态**链接的，因此不会出现在依赖列表里——这正是本项目的核心价值。

---

## 🔧 环境变量

`build_openssh.sh` 支持以下环境变量（全部可选）：

| 变量名 | 默认值 | 说明 |
| --- | --- | --- |
| `FORCE_OS_TAG` | 自动探测 | 强制产物系统标签，如 `el9`、`oe2403sp2`、`ky10sp3`、`sle15` |
| `RPM_RELEASE` | `1` | RPM 的 Release 序号，最终为 `<值>%{?dist}` |
| `RPMBUILD_DIR` | `rpm --eval '%{_topdir}'` | rpmbuild 工作根目录；EL 系 `/root/rpmbuild`，SUSE 系 `/usr/src/packages` |
| `OUTPUT_DIR` | `/opt` | 产物输出目录 |
| `LOG_DIR` | `/tmp/openssh_build_logs` | 构建日志目录（`KEEP_WORKDIR=1` 时保留） |
| `PRIVSEP_PATH` | `/var/empty/sshd` | sshd 权限隔离目录（以 0700 创建） |
| `PRIVSEP_USER` | `sshd` | 权限隔离用的低权限用户（不存在时自动创建） |
| `AUTO_DEPS` | `0` | `1` = 自动安装编译依赖且不询问；`0` = 交互询问（无 TTY 时自动跳过） |
| `JOBS` | `nproc` | 并行编译任务数 |
| `KEEP_WORKDIR` | `0` | `1` = 构建结束后保留 `rpmbuild` 目录与日志，便于排查 |
| `SSH_TAR` / `SSL_TAR` | 自动探测 | 显式指定源码包路径 |

用法示例：

```bash
# 指定标签、并行数，并保留日志用于排查
FORCE_OS_TAG=el9 JOBS=16 KEEP_WORKDIR=1 bash build_openssh.sh

# 在 CI/容器中全自动（不询问依赖安装）
AUTO_DEPS=1 bash build_openssh.sh

# 产物输出到指定目录
OUTPUT_DIR=/data/artifacts bash build_openssh.sh
```

### `build.sh` 传递给容器的环境变量

| 变量名 | 说明 |
| --- | --- |
| `FORCE_OS_TAG` | 由 `-t` 参数或镜像名推断得到 |
| `AUTO_DEPS` | 默认 `0`（镜像内已预装依赖，无需重复安装） |

---

## 📝 脚本与参数

### `build.sh`（宿主机入口）

| 参数 | 说明 | 示例 |
| --- | --- | --- |
| `-i <镜像>` | 基础镜像 | `-i rockylinux/rockylinux:9` |
| `-t <标签>` | 产物系统标签 | `-t el9` |
| `-p <平台>` | Docker 平台 | `-p linux/arm64` |
| `-f` | 强制重建编译镜像 | — |
| `-h` | 显示帮助 | — |

```bash
bash build.sh -h
```

### `build_openssh.sh`（容器内主脚本）

| 参数 | 说明 |
| --- | --- |
| `-h` / `--help` | 显示帮助 |

**退出码契约**（调用方可据此决定是否重试）：

| 退出码 | 含义 |
| --- | --- |
| `0` | 构建成功 |
| `1` | 参数错误 |
| `2` | 前置依赖缺失（无 `rpmbuild`/`gcc`/`make`） |
| `3` | 源码探测失败 |
| `4` | 构建失败（`rpmbuild` 非零退出） |
| `5` | 打包失败 |
| `6` | 用户中断（Ctrl+C） |

### `install.sh`（目标机安装）

| 参数 / 环境变量 | 说明 |
| --- | --- |
| `--no-restart` | 只安装，不重启 `sshd` 服务 |
| `--self-test` | 运行安装脚本自检（不改动系统） |
| `SSHD_CONFIG` | 指定 sshd 配置路径，默认 `/etc/ssh/sshd_config` |
| `ALLOW_ROOT_PASSWORD=1` | 安装后允许 root 密码登录 |
| `DISABLE_SELINUX=1` | 安装后关闭 SELinux（永久生效需重启） |

**退出码契约**：

| 退出码 | 含义 |
| --- | --- |
| `0` | 安装成功 |
| `1` | 运行失败 |
| `2` | 前置条件不满足（非 root / 无 rpm 命令） |
| `3` | `sshd -t` 配置校验失败（已自动回滚配置，未重启服务） |
| `4` | 命令行参数错误 |

---

## 📦 安装到目标机器

### 标准安装

```bash
tar zxvf openssh-10.6p2-rpms-el9-x86_64.tar.gz
cd openssh-10.6p2-rpms-el9-x86_64
sudo ./install.sh
```

`install.sh` 的执行序列：

```text
1. 检查 root 权限与 rpm 命令
2. 备份 /etc/ssh/sshd_config（sshd_config.bak.<时间戳>）
3. rpm -Uvh --replacefiles 安装三个 RPM
     ├─ %pre  创建 sshd 低权限用户
     └─ %post 生成主机密钥、chmod 600、systemctl enable
4. 按需应用 ALLOW_ROOT_PASSWORD / DISABLE_SELINUX
5. 主机密钥缺失时补生成（ssh-keygen -A）
6. sshd -t 校验配置
     └─ 失败 → 恢复安装前配置 → 退出码 3（不重启服务）
7. systemctl restart sshd
8. 打印 ssh -V 版本信息
```

### 常用变体

```bash
# 允许 root 密码登录 + 关闭 SELinux
sudo env ALLOW_ROOT_PASSWORD=1 DISABLE_SELINUX=1 ./install.sh

# 只安装不重启（滚动升级或批量分发时）
sudo ./install.sh --no-restart

# 验证安装脚本本身的正确性
sh ./install.sh --self-test
```

> ⚠️ **务必不要关闭当前的 SSH 窗口**。请新开一个连接确认能登录后，再关闭旧窗口，避免失联。
> 条件允许时提前准备 Telnet 等备用通道。

### 升级与回滚

```bash
# 查看当前版本
rpm -q openssh openssh-server openssh-clients

# 回滚到系统自带的版本
sudo yum downgrade openssh openssh-server openssh-clients

# 完全卸载本项目安装的包
sudo rpm -e openssh-clients openssh-server openssh
```

> `sshd_config` 是 `%config(noreplace)`，升级时**不会**覆盖你已有的配置；如需查看发行版原始配置，
> 使用 `rpm -V openssh` 或 `rpm -q --configfiles openssh` 对比。

---

## 🔄 CI/CD 自动构建

工作流文件：`.github/workflows/build-openssh.yml`

### Job 流程

```text
resolve  ──▶  sources  ──▶  plan  ──▶  build  ──▶  release
  │            │                    │        │
  │            │                    │        └─ 50 个矩阵任务（25 目标 × 2 架构）
  │            │                    └─ 生成矩阵 JSON + 期望产物数
  │            └─ 下载源码 + 校验 GPG 签名 + 校验 SHA256
  └─ 定时任务自动探测上游最新稳定版；Release 已存在则跳过
```

| Job | 职责 |
| --- | --- |
| `resolve` | 定时触发时抓取 OpenSSH 最新稳定版与 OpenSSL 最新 LTS；检查目标 Release 是否已存在 |
| `sources` | 下载源码；校验 OpenSSH 的 **GPG 签名**（可信指纹白名单）与 OpenSSL 的 **SHA256**（GitHub 官方摘要） |
| `plan` | 根据目标清单生成矩阵 JSON，并输出期望产物数量 |
| `build` | 每个矩阵项独立构建 Docker 镜像并执行 `build_openssh.sh`，上传 Artifact |
| `release` | 汇总全部 Artifact，校验数量与矩阵一致后发布 Release |

### 触发方式

| 触发条件 | 行为 |
| --- | --- |
| `schedule`（每天 02:00 UTC / 北京时间 10:00） | 自动探测上游最新稳定版；若对应 Release 已存在则跳过 |
| `workflow_dispatch` | 使用下方固定版本号手动触发 |
| `push`（仅以下路径） | `openssh-*.tar.gz`、`openssl-*.tar.gz`、`Dockerfile`、`build_openssh.sh`、`install.sh`、补丁文件、工作流文件 |

### 固定版本

```yaml
env:
  SSH_VERSION: "10.6p2"     # 推送/手动触发时使用的 OpenSSH 版本
  SSL_VERSION: "3.5.9"      # 推送/手动触发时使用的 OpenSSL LTS 版本
  OPENSSH_SIGNER_ALLOWLIST: "7168B983815A5EEF59A4ADFD2A3F414E736060BA"
```

> **签名白名单**：上游轮换发布密钥时，任务会**安全失败**（而不是静默安装未验证的源码）。
> 此时需人工核验新密钥后更新 `OPENSSH_SIGNER_ALLOWLIST`。
> 白名单支持用空格或逗号分隔多个指纹。

### 新增一个目标发行版

只需在 `plan` job 的目标清单里加一行：

```bash
cat > /tmp/targets.txt <<'EOF'
...
alinux3 alinux:3 ali3 0
EOF
```

行格式：`<target 名称> <基础镜像> <系统标签> <是否启用 UOS 补丁>`。矩阵 JSON 与期望产物数会自动重算。

### Release 命名规则

```text
openssh-<OpenSSH 版本>-openssl-<OpenSSL 版本>
例：openssh-10.6p2-openssl-3.5.9
```

单个产物命名：`openssh-<OpenSSH 版本>-rpms-<target>-<架构>.tar.gz`

---

## ⚡ 构建加速

| 手段 | 效果 | 说明 |
| --- | --- | --- |
| **Docker 镜像缓存** | 省掉 3-7 分钟的依赖安装 | `build.sh` 默认复用 `openssh-builder:<标签>` 镜像；改 Dockerfile 后用 `-f` 强制重建 |
| **并行编译** | OpenSSL + OpenSSH 提速明显 | `JOBS=$(nproc)`，容器内自动取 CPU 核数 |
| **ARM 原生构建** | 比 QEMU 交叉编译快数倍 | 在 ARM 服务器上直接用多架构镜像 |
| **CI 并行矩阵** | 50 个目标并行构建 | `fail-fast: false`，单个目标失败不影响其他目标 |
| **产物只保留必要文件** | 减少包体积 | OpenSSL 的中间产物安装在独立的 DESTDIR，不进 RPM |

实测参考（x86_64，宿主 8 核）：

| 目标 | 首次构建（含依赖安装） | 命中镜像缓存 |
| --- | --- | --- |
| CentOS 7 | ~7 min | ~115 s |
| Rocky Linux 9 | ~5 min | ~94 s |
| SUSE LE 15 | ~4 min | ~106 s |

---

## 🔒 安全说明

### 源码完整性

| 环节 | 防护措施 |
| --- | --- |
| OpenSSH 源码 | CI 校验 **GPG 签名**，签名者必须命中可信指纹白名单 |
| OpenSSL 源码 | CI 校验 **SHA256**（取自 GitHub 官方 Release 的 `digest` 字段） |
| 依赖安装 | 使用发行版官方仓库；CentOS 7 等 EOL 源优先选用可信镜像 |
| 编译镜像 | 基础镜像固定到具体 tag；麒麟镜像固定到 **sha256 digest** |

### 产物安全

- 权限隔离目录 `/var/empty/sshd` 权限为 **0700**，属主 `root:root`
- 主机密钥权限强制 `600`；由 `%post` 生成，避免弱默认密钥
- `sshd_config` 中 `UsePAM yes`，密码认证走 PAM 策略（faillock、审计）
- `sshd.service` 使用 `KillMode=control-group`，避免子进程残留

### 升级注意事项

> ⚠️ 升级 OpenSSH 会同时替换 `sshd` 二进制。若新版本与现有 PAM 配置或 SELinux 策略冲突，
> 可能导致无法登录。**请务必先在测试机验证，并保持当前 SSH 会话不要关闭。**

推荐流程：

1. 先在测试机执行 `sudo ./install.sh`，新开连接验证
2. 生产环境可用 `--no-restart` 先安装，择机重启
3. 提前准备回滚方案（见[升级与回滚](#升级与回滚)）

---

## 🧪 验证与自检

### 安装脚本自检

```bash
sh ./install.sh --self-test
# 输出：install.sh self-test passed
```

该自检在临时目录中验证 `sshd_config` 选项改写逻辑（`PermitRootLogin` / `PasswordAuthentication`
插入位置、`Match` 块不被破坏）与 SELinux 配置改写，不触碰真实系统。

### 静态检查

```bash
# 脚本语法与风格
bash -n build_openssh.sh build.sh install.sh
shellcheck -S warning build_openssh.sh build.sh install.sh

# GitHub Actions 工作流（含 schema 校验）
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest \
  .github/workflows/build-openssh.yml .github/workflows/docker-publish.yml
```

### 产物自检（目标机上）

```bash
# 版本与静态链接确认
ssh -V
ldd /usr/sbin/sshd | grep -E 'libssl|libcrypto' || echo "静态链接 OK（无动态 SSL 库）"

# 权限隔离目录
ls -ld /var/empty/sshd        # 期望 drwx------ root root

# 低权限用户
id sshd

# 配置校验
sshd -t && echo "配置 OK"

# 服务状态
systemctl status sshd
```

---

## 🔧 故障排除

### 构建阶段

<details>
<summary><b>CentOS 7 / Stream 8 镜像源 404 或 403</b></summary>

CentOS 7 与 Stream 8 已 EOL，官方源不可用。Dockerfile 会依次尝试阿里云 / 清华 / 华为云 / 官方 vault。

若全部失败，手动指定可用镜像后重试：

```bash
docker run --rm -it centos:7 bash -c '
  sed -i -e "s|^mirrorlist=|#mirrorlist=|" \
         -e "s|^#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009|" \
      /etc/yum.repos.d/CentOS-*.repo
  yum install -y rpm-build gcc make perl zlib-devel pam-devel
'
```
</details>

<details>
<summary><b><code>error: File not found: .../usr/share/man/man1/ssh.1</code></b></summary>

rpm 的 `brp-man` 脚本会把 man 页压缩成 `*.gz`。`%files` 中请使用 `文件名*` 通配写法，
同时兼容 `.1` 与 `.1.gz` 两种形态（本项目已处理）。
</details>

<details>
<summary><b><code>error: Failed build dependencies: perl-IPC-Cmd is needed by openssh-...</code></b></summary>

`BuildRequires` 声明了镜像里并不存在的包（如 SLE 精简源没有 `perl-IPC-Cmd`）。
本项目已改为**只声明实际已安装的包**，请勿在 spec 中硬编码可选依赖。
</details>

<details>
<summary><b><code>error: Bad source: /usr/src/packages/SOURCES/openssh-*.tar.gz: No such file</code></b></summary>

SUSE 的 rpmbuild 使用 `/usr/src/packages` 而非 `/root/rpmbuild`。本项目通过
`rpmbuild -bb --define "_topdir ${RPMBUILD_DIR}"` 解决；手工执行 rpmbuild 时请自行带上该参数。
</details>

<details>
<summary><b><code>error: Installed (but unpackaged) file(s) found</code></summary>

`%install` 往 buildroot 写入了未在 `%files` 声明的**普通文件**。
注意：未声明的**空目录**是被容忍的，普通文件则是硬错误。
</details>

<details>
<summary><b>编译很慢 / QEMU 下超时</b></summary>

- 交叉编译请给足时间（QEMU 下 1-3 小时），或改用 ARM 原生机器
- 确认 `JOBS` 生效：`JOBS=$(nproc) bash build_openssh.sh`
- 保留中间产物排查：`KEEP_WORKDIR=1 bash build_openssh.sh`
</details>

### 安装阶段

<details>
<summary><b><code>sshd: no hostkeys available -- exiting.</code></b></summary>

主机密钥缺失。RPM 的 `%post` 会自动执行 `ssh-keygen -A`；若 `/etc/ssh` 权限异常导致失败，
可手动执行：

```bash
sudo ssh-keygen -A
sudo chmod 600 /etc/ssh/ssh_host_*_key
```
</details>

<details>
<summary><b><code>Missing privilege separation directory: /var/empty/sshd</code></b></summary>

权限隔离目录缺失或权限不对：

```bash
sudo install -d -m 0700 /var/empty/sshd
sudo chown root:root /var/empty/sshd
```
</details>

<details>
<summary><b>安装后无法用密码登录</b></summary>

1. 确认 `sshd -T | grep -i usepam` 输出为 `yes`
2. 确认 `/etc/pam.d/sshd` 存在且 `password-auth` 可用
3. 检查 `/etc/selinux/config` 与 `getenforce`
4. 用 `sshd -ddd` 前台启动看详细报错
</details>

<details>
<summary><b><code>systemd is needed by openssh-...</code>（SUSE 精简容器）</b></summary>

最小化容器镜像里没有 systemd，而本包的服务端依赖它。
在真实 SLE 服务器上不存在此问题；容器内验证可加 `--nodeps`。
</details>

<details>
<summary><b>麒麟 / UOS 镜像哪里找</b></summary>

- 麒麟：需要内部信创源，或华为云/阿里云上的麒麟官方镜像；`ky10sp*` 只是产物标签，脚本兼容任何 yum 系系统
- UOS 20：走 EL8 环境 + 内核补丁方案，见 `openssh-uos20-kernel-panic-fix.patch`
</details>

---

## 📝 变更日志

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，并遵循[语义化版本](https://semver.org/lang/zh-CN/)。

### [3.0.0] - 2026-11-06

#### 新增

- **支持 OpenSSH 10.6p2**（含 10.6 新增的 `ssh-mldsa44-ed25519` 混合后量子签名算法）
- **新增 12 个目标发行版**：AlmaLinux 8/9/10、Oracle Linux 8/9、CentOS Stream 10、openEuler 22.03 LTS、
  openEuler 24.03 LTS SP1、openCloudOS 9、Anolis OS 8、Amazon Linux 2023、SUSE LE 15 SP6
- **新增 SUSE / zypper 支持**：`rpm-build` 独立包、man 页 `catN` 目录、`shadow` 包名、`openssh-fips` Provides
- **新增 `x11-ssh-askpass` 支持**：检测到源码包且有 X11 头文件时自动构建 `ssh-askpass`
- **新增可选特性自动探测**：SELinux / libedit 按镜像实际内容启用并补齐运行期依赖
- **CI 矩阵自动生成**：`plan` job 生成矩阵 JSON，产物数量动态校验
- **新增 `--no-restart`** 安装开关与 `install.sh --self-test` 自检

#### 变更

- 目标系统从 13 个扩展到 **25 个**（50 个架构组合）
- `build.sh` 修正容器内工作目录（原 `/build/repo` 不存在）
- `build_openssh.sh` 全面重写：`set -Eeuo pipefail`、退出码契约、去除 `eval`、占位符式 SPEC 生成
- `Dockerfile` 改为多发行版通用，CentOS 7 源增加多镜像回退
- `install.sh` 增加主机密钥兜底生成与配置校验失败自动回滚
- 移除根目录重复的 `build-openssh.yml`（与 `.github/workflows/` 下同名文件冲突）

#### 修复

- 权限隔离目录从 `/var/empty` 改为 `/var/empty/sshd`，不再与 `filesystem` 包冲突
- `%files` 的 man 页声明改为通配写法，修复 `brp-man` 压缩后 `File not found` 导致构建失败
- 新增 `%pre` 自动创建 `sshd` 低权限用户，修复 OpenSSH 10.x 无法启动
- `%post` 自动生成主机密钥，修复新装机器 `sshd -t` 失败
- `sshd_config` 的 `UsePAM` 显式置为 `yes`，修复密码认证绕过 PAM 策略
- `rpmbuild` 工作根目录跟随 `%{_topdir}`，修复 SUSE 上 `Bad source`
- 签名指纹白名单支持多指纹（原先 `tr ' ' ','` 导致第二个指纹永远匹配不上）
- 修复 GitHub Actions workflow schema 错误（游离顶层键 + `env` 上下文误用）

### [2.0.0] - 上游版本

- 基于[mouse0524/openssh-rpms](https://github.com/mouse0524/openssh-rpms) ，实现 Docker 化编译与 CI 矩阵发布

---

## 🤝 贡献指南

欢迎所有形式的贡献！

### 如何参与

1. **Fork** 本仓库
2. **创建分支**：`git checkout -b feature/your-feature`
3. **提交变更**：`git commit -m 'feat: 你的描述'`
4. **推送分支**：`git push origin feature/your-feature`
5. **发起 Pull Request**

### 开发规范

- 所有 Shell 脚本必须通过 `shellcheck -S warning`（零告警）
- 所有脚本必须开启 `set -Eeuo pipefail`、声明退出码契约、挂 `trap` 清理
- **禁止使用 `eval`** 执行外部输入
- Workflow 改动必须通过 `actionlint`
- 变量展开一律加引号；`$(...)` 替代反引号
- 保持 EL 系与 SUSE 系同时可用，发行版差异用运行时探测处理，不要硬编码

### 提交信息规范

采用[约定式提交](https://www.conventionalcommits.org/zh-hans/v1.0.0/)：

| 前缀 | 用途 |
| --- | --- |
| `feat:` | 新功能 |
| `fix:` | 缺陷修复 |
| `docs:` | 文档 |
| `style:` | 不影响行为的格式调整 |
| `refactor:` | 重构 |
| `test:` | 测试 |
| `chore:` | 构建流程或辅助工具 |

### 提交前自检清单

```bash
bash -n build_openssh.sh build.sh install.sh
shellcheck -S warning build_openssh.sh build.sh install.sh
sh install.sh --self-test
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest .github/workflows/*.yml
```

### 代码审查要点

审查者会关注：

- 是否引入新的发行版分支硬编码
- SPEC 的 `%files` 是否与 `%install` 的写入内容一致
- 运行期依赖是否完整声明
- 权限隔离目录 / 主机密钥等安全相关配置是否正确
- 脚本在非 TTY（CI）环境下是否仍能正常工作

---

## 📄 许可证

本项目（打包脚本部分）基于 [BSD 2-Clause](LICENSE) 许可证开源，派生自[mouse0524/openssh-rpms](https://github.com/mouse0524/openssh-rpms) 

本仓库**只包含打包脚本，不分发上游源码**。被打包的第三方组件各自遵循其上游许可证：

| 组件 | 许可证 |
| --- | --- |
| OpenSSH (openssh-portable) | BSD 2-Clause |
| OpenSSL 3.x | Apache License 2.0 |
| x11-ssh-askpass | BSD 2-Clause |

生成的 RPM 元数据中声明为 `License: BSD`。

---

## 🙏 致谢

- [OpenSSH](https://www.openssh.com/) —  portable OpenSSH 的开发者与发布签名者
- [OpenSSL](https://www.openssl.org/) — 提供 3.5 LTS 分支与长期支持
- [mouse0524/openssh-rpms](https://github.com/mouse0524/openssh-rpms) — 本项目的原始实现
- [boypt/openssh-rpms](https://github.com/boypt/openssh-rpms) — UOS 20 兼容方案参考
- [hxsoong/kylin](https://hub.docker.com/r/hxsoong/kylin) — 麒麟社区镜像
- [actionlint](https://github.com/rhysd/actionlint) / [shellcheck](https://www.shellcheck.net/) — 静态检查工具
