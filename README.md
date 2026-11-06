# OpenSSH RPM 一键打包（Docker 多发行版）

基于 [nugent1a/openssh-rpms](https://github.com/nugent1a/openssh-rpms)，用 Docker 在任意宿主机
（含 Windows/WSL2、macOS、Linux）上把 **OpenSSH 10.6p2** 源码编译成目标系统的 RPM 包，
并静态链接 **OpenSSL 3.5.x LTS**，从而在缺少新版本 OpenSSL 的老旧/国产发行版上也能升级 OpenSSH。

## 特性

| 能力 | 说明 |
| --- | --- |
| 多发行版 | EL 7/8/9/10 系、openEuler、openCloudOS、Anolis OS、麒麟、UOS、openEuler、openSUSE/SLE、Amazon Linux 等 |
| 静态 OpenSSL | 运行时不再依赖系统 OpenSSL 动态库，避免 `libcrypto.so.1.1` 缺失类问题 |
| 权限隔离目录 | 统一使用 `/var/empty/sshd`，不再与 `filesystem` 包的 `/var/empty` 冲突 |
| 权限隔离用户 | 安装时自动创建 `sshd` 低权限用户/组，OpenSSH 10.x 必需 |
| 主机密钥 | `%post` 自动生成主机密钥，`sshd -t` 校验前即可用 |
| systemd 单元 | 附带 `sshd.service`，含 `RuntimeDirectory=sshd`、主机密钥预生成 |
| askpass | 检测到 `x11-ssh-askpass-*.tar.gz` 且有 X11 头文件时一并构建 `ssh-askpass` |
| 可选特性 | 自动探测 SELinux / libedit 支持，按需开启并补齐运行期依赖 |
| 工程化 | `set -Eeuo pipefail`、退出码契约、无 `eval`、shellcheck 零告警 |

## 支持的目标系统

| 系统 | x86_64 | aarch64 | 产物标签 |
| --- | --- | --- | --- |
| CentOS 7 | 是 | 是（AltArch 归档源） | `el7` |
| CentOS Stream 8 / 9 / 10 | 是 | 是 | `el8` / `el9` / `el10` |
| Rocky Linux 8 / 9 / 10 | 是 | 是 | `el8` / `el9` / `el10` |
| AlmaLinux 8 / 9 / 10 | 是 | 是 | `el8` / `el9` / `el10` |
| Oracle Linux 8 / 9 | 是 | 是 | `el8` / `el9` |
| openEuler 22.03 LTS | 是 | 是 | `oe2203` |
| openEuler 24.03 LTS SP1–SP4 | 是 | 是 | `oe2403sp1`–`oe2403sp4` |
| openCloudOS 9 | 是 | 是 | `oc9` |
| Anolis OS 8 | 是 | 是 | `an8` |
| Amazon Linux 2023 | 是 | 是 | `amzn2023` |
| 银河麒麟 V10 SP1/SP2/SP3 | 是 | 是 | `ky10sp1`–`ky10sp3` |
| UOS 20 兼容包 | 是 | 是 | `uos20` |
| openSUSE Leap 15 / SUSE LE 15 | 是 | 是 | `leap15` / `sle15` |

> 麒麟目标使用社区镜像 `hxsoong/kylin`，并锁定多架构 digest；该镜像不是麒麟官方发布。
> UOS 20 目标参考 [boypt/openssh-rpms](https://github.com/boypt/openssh-rpms)，在 EL8 环境构建并
> 应用 UOS 20 内核 `dup2()` 兼容补丁，并非使用 UOS 官方容器镜像。
>
> SUSE 目标使用官方 `registry.suse.com/suse/sle15` 镜像，`rpmbuild` 来自独立的 `rpm-build` 包
> （SLE 自带 `rpm-ndb`，直接装 `rpm` 会冲突）。本包会显式 `Provides: openssh-fips`，以满足
> SLE `patterns-base-fips` 模式的条件依赖 `(openssh-fips if openssh-clients)`。
> SLE 的 man 页子目录是 `catN` 而非 `manN`，脚本已自动适配。

## 目录结构

```
openssh-rpms/
├── build.sh              # 一键编译脚本（Docker 入口）
├── build_openssh.sh      # 容器内实际执行的主构建脚本（生成 SPEC 并 rpmbuild）
├── install.sh            # RPM 安装、配置校验与服务重启
├── Dockerfile            # 编译环境镜像（dnf/yum/microdnf/zypper 通用）
├── openssh-uos20-kernel-panic-fix.patch
└── .github/workflows/build-openssh.yml   # CI 构建矩阵
```

## 使用步骤

### 1. 准备源码包

放到本目录下（建议使用与 CI 相同的版本组合）：

- `openssh-10.6p2.tar.gz`
- `openssl-3.5.9.tar.gz`（任一 3.5.x LTS 补丁版）
- 可选：`x11-ssh-askpass-*.tar.gz`

下载地址：<https://www.openssh.com/releasenotes.html> / <https://www.openssl.org/source/>

### 2. 一键编译（Docker）

```bash
cd openssh-rpms
bash build.sh                       # 默认 rockylinux:9
bash build.sh -i rockylinux:9 -t el9
bash build.sh -i openeuler/openeuler:24.03-lts-sp2 -t oe2403sp2
bash build.sh -i <麒麟 V10 镜像> -t ky10sp3
bash build.sh -f                    # 强制重建编译镜像
```

参数：

| 参数 | 说明 |
| --- | --- |
| `-i <镜像>` | 基础镜像，默认 `rockylinux:9` |
| `-t <标签>` | 产物系统标签，默认按镜像名推断 |
| `-p <平台>` | `linux/amd64` / `linux/arm64`，用于交叉编译 |
| `-f` | 强制重建编译镜像 |

### 3. 直接在目标系统内构建（无 Docker）

```bash
yum install -y rpm-build gcc make perl zlib-devel pam-devel perl-IPC-Cmd
bash build_openssh.sh
```

可用环境变量：`FORCE_OS_TAG`、`RPM_RELEASE`、`OUTPUT_DIR`、`LOG_DIR`、`RPMBUILD_DIR`、
`AUTO_DEPS=1`、`JOBS`、`PRIVSEP_PATH`、`KEEP_WORKDIR=1`。

`build_openssh.sh` 退出码：`0` 成功、`1` 参数错误、`2` 前置依赖缺失、`3` 源码探测失败、
`4` 构建失败、`5` 打包失败、`6` 用户中断。

### 4. 取产物

编译完成后产物位于 `./output/openssh-<版本>-rpms-<标签>-<架构>.tar.gz`
（容器内默认输出到 `/opt`，由 `build.sh` 映射到 `./output`）。

## ARM (aarch64) 编译

`build_openssh.sh` 用 `uname -m` 自动探测架构，产物自动打上 `x86_64` 或 `aarch64` 标记。

**方式一：在 ARM 服务器上编译（推荐，鲲鹏/飞腾等）**

直接用多架构基础镜像，其余步骤完全相同：

```bash
bash build.sh -i rockylinux:9 -t el9
bash build.sh -i openeuler/openeuler:24.03-lts-sp2 -t oe2403sp2
```

**方式二：在 x86 电脑上交叉编译（QEMU 模拟，慢 3-10 倍）**

```bash
# 首次先安装 ARM 模拟支持
docker run --privileged --rm tonistiigi/binfmt --install arm64

# 编译
bash build.sh -p linux/arm64 -i rockylinux:9 -t el9
```

在 QEMU 下编译 OpenSSL + OpenSSH 可能需要 1-3 小时，建议优先用方式一。

## 安装到目标机器（以 el9 为例）

```bash
tar zxvf openssh-*.tar.gz
cd openssh-*-rpms-*
sudo ./install.sh
```

安装脚本会：备份 `sshd_config` → 安装 RPM → 补齐主机密钥 → `sshd -t` 校验 →
校验通过后才重启服务；校验失败会自动恢复原配置且不重启服务。

可选开关：

```bash
sudo env ALLOW_ROOT_PASSWORD=1 DISABLE_SELINUX=1 ./install.sh   # 允许 root 密码登录 + 关闭 SELinux
sudo ./install.sh --no-restart                                  # 只安装不重启服务
sh ./install.sh --self-test                                     # 安装脚本自检
```

> ⚠️ **不要关闭旧的 SSH 窗口**，新开一个连接验证成功后再退出，防止失联。建议提前开启 Telnet 等备用通道。

## 工作原理

- `Dockerfile` 以目标系统为基础镜像，按 `dnf` / `yum` / `microdnf` / `zypper` 自动选择包管理器，
  预装编译依赖；CentOS 7 / Stream 8 会自动切换到可用的 vault 镜像（阿里云 / 清华 / 华为云）。
- `build.sh` 把当前目录挂载到容器 `/build`（脚本在其中探测源码包），把 `./output` 挂到 `/opt`
  直接接住产物。
- `build_openssh.sh` 在容器内探测发行版与架构，生成 SPEC：
  - `%prep` 编译静态 OpenSSL（`no-shared` + `install_sw`）到 `openssl_install`；
  - `%build` 用 `--with-ssl-dir` 指向该静态库，并把 Makefile 中的 `-lcrypto` 替换为 `libcrypto.a`；
  - `%install` 安装并设置权限隔离目录 `/var/empty/sshd`（0700）；
  - `%pre` 创建 `sshd` 低权限用户，`%post` 生成主机密钥并启用服务。

## GitHub Actions 自动构建

工作流每天北京时间 10:00 自动检查 OpenSSH 最新稳定版和 OpenSSL 最新 LTS 补丁版。
对应版本组合的 Release 不存在时自动构建，已有 Release 时跳过。
OpenSSH 发布签名者必须命中工作流中的可信指纹白名单；上游轮换密钥时任务会安全失败，
需人工核验并更新白名单。

也可以修改 `.github/workflows/build-openssh.yml` 顶部的固定版本号并推送，或手动运行：

```yaml
env:
  SSH_VERSION: "10.6p2"
  SSL_VERSION: "3.5.9"
```

定时运行使用自动检测版本。构建矩阵定义在 `plan` 任务的 `/tmp/targets.txt` 中，
每行 `<target> <image> <os_tag> <uos20>`，新增发行版只需加一行。

## 常见问题

- **CentOS 7 镜像源 404**：Dockerfile 会依次尝试阿里云 / 清华 / 华为云 / 官方 vault 镜像。
- **`rpmbuild` 报 `Installed (but unpackaged) file(s) found`**：说明 `%install` 往 buildroot 写入了
  未在 `%files` 中声明的普通文件；检查 `%install` 是否新增了安装动作。
- **`sshd` 启动报 `Missing privilege separation directory`**：确认 `/var/empty/sshd` 存在且权限 0700
  （`install.sh` 与 RPM `%post` 会自动创建）。
- **`sshd -t` 报 `no hostkeys available`**：RPM `%post` 与 `install.sh` 都会调用 `ssh-keygen -A`。
- **麒麟 V10 镜像哪里找**：需要内部信创源或华为云/阿里云上的麒麟官方镜像；`ky10sp*` 只是产物标签，
  脚本本身兼容任何 yum 系系统。
- **更换源码版本**：直接替换目录里的 tar.gz 即可，脚本自动探测文件名中的版本号。
- **强制重建镜像**：`bash build.sh -f`。
