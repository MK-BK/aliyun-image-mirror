#!/usr/bin/env bash
#
# sync-to-local.sh — 从阿里云 ACR 同步镜像到本地私有仓库
#
# 用法:
#   ./scripts/sync-to-local.sh <本地仓库地址> [镜像列表文件]
#
# 示例:
#   ./scripts/sync-to-local.sh 192.168.1.100:5000
#   ./scripts/sync-to-local.sh 192.168.1.100:5000 my-images.txt
#   ./scripts/sync-to-local.sh 192.168.1.100:5000/library
#
# 环境变量（均有默认值，可按需覆盖）:
#   ALIYUN_REGISTRY   阿里云 ACR 地址（含命名空间）
#   ALIYUN_USERNAME   ACR 用户名
#   ALIYUN_PASSWORD   ACR 密码（执行时交互输入）
#
# 镜像列表文件格式同 images.txt:
#   - 每行一个镜像
#   - 以 # 开头的行为注释，会被忽略
#   - 空行会被忽略

set -euo pipefail

# ── 参数检查 ──────────────────────────────────────────────────
LOCAL_REGISTRY="${1:-}"
IMAGE_FILE="${2:-}"

if [ -z "${LOCAL_REGISTRY}" ]; then
    echo "用法: $(basename "$0") <本地仓库地址> [镜像列表文件]"
    echo "示例: $(basename "$0") 192.168.1.100:5000"
    echo "      $(basename "$0") 192.168.1.100:5000 my-images.txt"
    exit 1
fi

# 解析镜像列表文件路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# 未指定则用仓库根目录下的 images.txt
if [ -z "${IMAGE_FILE}" ]; then
    IMAGE_FILE="${REPO_DIR}/images.txt"
# 相对路径: 先查当前目录，找不到再查仓库根目录
elif [[ "${IMAGE_FILE}" != /* ]] && [ ! -f "${IMAGE_FILE}" ]; then
    if [ -f "${REPO_DIR}/${IMAGE_FILE}" ]; then
        IMAGE_FILE="${REPO_DIR}/${IMAGE_FILE}"
    fi
fi

# 默认值
ALIYUN_REGISTRY="${ALIYUN_REGISTRY:-crpi-pweus896l7j9p1b9.cn-hangzhou.personal.cr.aliyuncs.com/images_dev}"
ALIYUN_USERNAME="${ALIYUN_USERNAME:-QuellaBK}"

# 密码: 优先用环境变量，没有则交互输入
if [ -z "${ALIYUN_PASSWORD:-}" ]; then
    read -s -p "请输入 ACR 密码: " ALIYUN_PASSWORD
    echo ""
fi

if [ ! -f "${IMAGE_FILE}" ]; then
    echo "错误: 镜像列表文件不存在: ${IMAGE_FILE}"
    exit 1
fi

# ── 检查 skopeo ───────────────────────────────────────────────
if ! command -v skopeo &>/dev/null; then
    echo "错误: 未找到 skopeo，请先安装"
    echo "  Ubuntu/Debian: sudo apt-get install -y skopeo"
    echo "  macOS:         brew install skopeo"
    exit 1
fi

# 检测是否支持 --all 参数
MULTI_ARCH_FLAG=""
if skopeo copy --help 2>&1 | grep -q -- '--all'; then
    MULTI_ARCH_FLAG="--all"
fi

# ── 读取镜像列表 ──────────────────────────────────────────────
IMAGES=$(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "${IMAGE_FILE}" | sort -u)

if [ -z "${IMAGES}" ]; then
    echo "镜像列表为空，无内容需要同步"
    exit 0
fi

TOTAL=$(echo "${IMAGES}" | wc -l | tr -d ' ')

# ── 登录源仓库 ────────────────────────────────────────────────
echo "登录阿里云 ACR..."
echo "${ALIYUN_PASSWORD}" | skopeo login "${ALIYUN_REGISTRY%%/*}" \
    -u "${ALIYUN_USERNAME}" \
    --password-stdin

echo ""
echo "═══════════════════════════════════════════════"
echo "  同步 ${TOTAL} 个镜像: ${ALIYUN_REGISTRY} → ${LOCAL_REGISTRY}"
echo "═══════════════════════════════════════════════"
echo ""

# ── 同步 ──────────────────────────────────────────────────────
SUCCESS=0
FAILED=0
INDEX=0

while IFS= read -r image; do
    [ -z "$image" ] && continue
    INDEX=$((INDEX + 1))

    # 取最后一段作为仓库名: lmsysorg/sglang:v0.5.16 -> sglang:v0.5.16
    short_name="${image##*/}"

    src="${ALIYUN_REGISTRY}/${short_name}"
    dst="${LOCAL_REGISTRY}/${short_name}"

    echo "[${INDEX}/${TOTAL}] ${image}"
    echo "  ${src} → ${dst}"

    if skopeo copy \
        ${MULTI_ARCH_FLAG} \
        --src-tls-verify=true \
        --dest-tls-verify=false \
        "docker://${src}" \
        "docker://${dst}"; then
        echo "  ✓ 成功"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "  ✗ 失败"
        FAILED=$((FAILED + 1))
    fi
    echo ""

done <<< "${IMAGES}"

# ── 汇总 ──────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════"
echo "  完成: 成功 ${SUCCESS}, 失败 ${FAILED}, 共 ${TOTAL}"
echo "═══════════════════════════════════════════════"

[ "${FAILED}" -eq 0 ] || exit 1
