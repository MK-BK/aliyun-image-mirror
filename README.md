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
├── .github/
│   └── workflows/
│       └── mirror.yml            # GitHub Actions 工作流
├── .gitignore
└── README.md
```

## 注意事项

- 阿里云 ACR 需提前创建对应的仓库（或开启自动创建仓库功能）
- Docker Hub 有拉取频率限制，大量同步时建议配置 Docker Hub 凭据
- Workflow 使用 `concurrency` 确保同分支推送按顺序执行
- 同一镜像重复添加不会重复同步（diff 只检测实际新增行）
