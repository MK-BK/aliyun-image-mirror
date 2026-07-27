# Aliyun Image Mirror

自动将 Docker 镜像同步到阿里云容器镜像服务 (ACR) 的 GitHub Actions 仓库。

## 工作原理

1. 在 `images.txt` 中添加需要同步的镜像（每行一个）
2. 提交到 `main` 分支后，GitHub Workflow 自动：
   - 计算本次提交 **新增** 的镜像行（删除的行会被忽略）
   - 拉取每个新增镜像
   - 重新打标并推送到阿里云 ACR

## 快速开始

### 1. 配置 GitHub Secrets

在仓库 **Settings → Secrets and variables → Actions** 中添加以下 Secrets：

| Secret 名称 | 说明 | 示例 |
|---|---|---|
| `ALIYUN_REGISTRY` | 阿里云 ACR 注册地址（含命名空间） | `registry.cn-hangzhou.aliyuncs.com/your-namespace` |
| `ALIYUN_USERNAME` | ACR 用户名 | `your-username` |
| `ALIYUN_PASSWORD` | ACR 密码 | `your-password` |

### 2. 编辑镜像列表

编辑 `images.txt`，每行一个镜像：

```
nginx:latest
redis:7-alpine
busybox:latest
```

- 以 `#` 开头的行视为注释，空行会被忽略
- 仅 **新增行** 会触发同步，删除行不会处理

### 3. 提交并推送

```bash
git add images.txt
git commit -m "add: nginx, redis"
git push origin main
```

Workflow 会自动触发，同步新增的镜像。

## 目标镜像命名规则

源镜像会被推送到 `${ALIYUN_REGISTRY}/<源镜像名>`：

| 源镜像 | 目标镜像（假设 `ALIYUN_REGISTRY=registry.cn-hangzhou.aliyuncs.com/myns`） |
|---|---|
| `nginx:latest` | `registry.cn-hangzhou.aliyuncs.com/myns/nginx:latest` |
| `library/redis:7` | `registry.cn-hangzhou.aliyuncs.com/myns/library/redis:7` |
| `registry.k8s.io/pause:3.9` | `registry.cn-hangzhou.aliyuncs.com/myns/registry.k8s.io/pause:3.9` |

## 新增行检测逻辑

Workflow 使用 `git diff` 计算提交前后的差异：

- **新增行**（diff 中以 `+` 开头）：拉取并推送到阿里云 ACR
- **删除行**（diff 中以 `-` 开头）：忽略，不处理
- **首次提交**：`images.txt` 中所有非注释行视为新增

## 文件说明

```
.
├── images.txt                    # 镜像列表文件
├── scripts/
│   └── sync-to-local.sh          # 从阿里云 ACR 同步到本地私有仓库的脚本
├── .github/
│   └── workflows/
│       └── mirror.yml            # GitHub Actions 工作流
├── .gitignore
└── README.md
```

## 从阿里云同步到本地私有仓库

`scripts/sync-to-local.sh` 脚本用于将阿里云 ACR 中的镜像同步到本地私有镜像仓库（如 Harbor、Nexus、自建 Docker Registry 等）。

### 依赖

需要安装 `skopeo`：

```bash
# Ubuntu/Debian
sudo apt-get install -y skopeo

# CentOS/RHEL
sudo dnf install -y skopeo

# macOS
brew install skopeo
```

### 使用方式

**方式一：使用环境变量**

```bash
export ALIYUN_REGISTRY="crpi-xxx.cn-hangzhou.personal.cr.aliyuncs.com/ns"
export ALIYUN_USERNAME="your-username"
export ALIYUN_PASSWORD="your-password"
export LOCAL_REGISTRY="192.168.1.100:5000"
# 如果本地仓库需要认证：
# export LOCAL_USERNAME="admin"
# export LOCAL_PASSWORD="Harbor12345"

./scripts/sync-to-local.sh
```

**方式二：使用命令行参数**

```bash
./scripts/sync-to-local.sh \
  -s crpi-xxx.cn-hangzhou.personal.cr.aliyuncs.com/ns \
  -u your-username -p your-password \
  -d 192.168.1.100:5000
```

**方式三：预览（不实际同步）**

```bash
./scripts/sync-to-local.sh --dry-run \
  -s crpi-xxx.cn-hangzhou.personal.cr.aliyuncs.com/ns \
  -d 192.168.1.100:5000
```

### 参数说明

| 参数 | 环境变量 | 说明 | 默认值 |
|------|----------|------|--------|
| `-s` | `ALIYUN_REGISTRY` | 阿里云 ACR 地址（含命名空间） | - |
| `-u` | `ALIYUN_USERNAME` | ACR 用户名 | - |
| `-p` | `ALIYUN_PASSWORD` | ACR 密码 | - |
| `-d` | `LOCAL_REGISTRY` | 本地仓库地址 | - |
| - | `LOCAL_USERNAME` | 本地仓库用户名（可选） | - |
| - | `LOCAL_PASSWORD` | 本地仓库密码（可选） | - |
| `-f` | - | 镜像列表文件 | `images.txt` |
| - | `SRC_TLS_VERIFY` | 源仓库 TLS 校验 | `true` |
| - | `DST_TLS_VERIFY` | 目标仓库 TLS 校验 | `false` |
| - | `MULTI_ARCH` | 多架构模式 | `system` |
| `--dry-run` | - | 仅预览不执行 | `false` |

### 镜像命名规则

与 GitHub Workflow 一致，取镜像名的最后一段作为仓库名：

| `images.txt` 中的镜像 | 阿里云 ACR 中的镜像 | 本地仓库中的镜像 |
|---|---|---|
| `lmsysorg/sglang:v0.5.16` | `crpi-xxx/ns/sglang:v0.5.16` | `192.168.1.100:5000/sglang:v0.5.16` |
| `vllm/vllm-openai:v0.26.0` | `crpi-xxx/ns/vllm-openai:v0.26.0` | `192.168.1.100:5000/vllm-openai:v0.26.0` |
| `nginx:latest` | `crpi-xxx/ns/nginx:latest` | `192.168.1.100:5000/nginx:latest` |

### TLS 说明

本地私有仓库通常使用 HTTP 或自签名证书，脚本默认对目标仓库关闭 TLS 校验（`DST_TLS_VERIFY=false`）。如果你的本地仓库使用了正规证书，可以开启：

```bash
export DST_TLS_VERIFY=true
```

## 注意事项

- 阿里云 ACR 需提前创建对应的仓库（或开启自动创建仓库功能）
- Docker Hub 有拉取频率限制，大量同步时建议配置 Docker Hub 凭据
- Workflow 使用 `concurrency` 确保同分支推送按顺序执行
- 同一镜像重复添加不会重复同步（diff 只检测实际新增行）
