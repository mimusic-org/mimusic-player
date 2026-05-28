#!/bin/bash

# Songloft Flutter 前端 Docker 构建脚本
# 用法（从 frontend 目录或项目根目录运行）：
#   ./scripts/docker-build-frontend.sh              # 构建所有平台
#   ./scripts/docker-build-frontend.sh android       # 仅构建 Android
#   ./scripts/docker-build-frontend.sh web           # 仅构建 Web

BUILD_PLATFORM="${1:-all}"

# 获取脚本所在目录，定位到 frontend 根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(dirname "$SCRIPT_DIR")"

echo "构建平台: ${BUILD_PLATFORM}"
echo "前端目录: ${FRONTEND_DIR}"

# 构建镜像（构建上下文为 frontend 根目录）
docker build \
    --build-arg BUILD_PLATFORM="${BUILD_PLATFORM}" \
    -t songloft-frontend-builder \
    "$FRONTEND_DIR"

# 复制产物到本地
docker create --name tmp-frontend songloft-frontend-builder
docker cp tmp-frontend:/output/ "${FRONTEND_DIR}/frontend-build/"
docker rm tmp-frontend

echo "✓ 构建产物已输出到 ${FRONTEND_DIR}/frontend-build/"
