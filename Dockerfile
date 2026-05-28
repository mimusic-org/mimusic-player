# syntax=docker/dockerfile:1
# Songloft Flutter 前端构建镜像
# 用法：
#   cd songloft  # 项目根目录
#   docker build -t songloft-frontend-builder frontend/
#   docker build --build-arg BUILD_PLATFORM=android -t songloft-frontend-builder frontend/
#   docker build --build-arg BUILD_PLATFORM=web -t songloft-frontend-builder frontend/
#
# 提取构建产物到本地：
#   docker create --name tmp-frontend songloft-frontend-builder
#   docker cp tmp-frontend:/output/ ./frontend-build/
#   docker rm tmp-frontend
#
# 支持的平台：web | web-embedded | linux | android | all
# 默认构建 all（Web standalone + Web embedded + Linux + Android）

# ============================================================
# Stage 1: Flutter SDK 安装 + 前端构建
# ============================================================
FROM debian:bookworm-slim AS builder

ARG FLUTTER_VERSION=3.29.3
ARG BUILD_PLATFORM=all
ARG ANDROID_SDK_TOOLS_VERSION=11076708
ARG ANDROID_BUILD_TOOLS_VERSION=35.0.0
ARG ANDROID_PLATFORM_VERSION=35

# 避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 1. 安装系统依赖（Flutter Linux 桌面 + Android 构建 + 通用工具）
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    curl git unzip xz-utils zip ca-certificates \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev libglu1-mesa libstdc++-12-dev \
    openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

# 2. 安装 Android SDK
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=${ANDROID_HOME}
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS_VERSION}_latest.zip" -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools \
    && mv /tmp/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools \
    && yes | sdkmanager --licenses > /dev/null 2>&1 \
    && sdkmanager --install \
        "platform-tools" \
        "platforms;android-${ANDROID_PLATFORM_VERSION}" \
        "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
    && rm -rf ${ANDROID_HOME}/.android/cache

# 3. 安装 Flutter SDK
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

RUN git clone https://github.com/flutter/flutter.git -b ${FLUTTER_VERSION} --depth 1 ${FLUTTER_HOME} \
    && flutter precache --web --linux --android \
    && flutter doctor -v \
    && chown -R root:root ${FLUTTER_HOME}

# 4. 复制项目源码（构建上下文为 frontend/ 目录）
WORKDIR /app/frontend
COPY . .

# 5. 安装 Flutter 依赖
RUN flutter pub get

# 6. 执行构建（复用 build-frontend.sh 脚本）
RUN chmod +x scripts/build-frontend.sh && \
    bash scripts/build-frontend.sh ${BUILD_PLATFORM} /app/frontend-build

# ============================================================
# Stage 2: 仅保留构建产物（精简镜像）
# ============================================================
FROM debian:bookworm-slim

WORKDIR /output

COPY --from=builder /app/frontend-build/ /output/

CMD ["sh", "-c", "echo '=== Songloft Frontend Build Output ===' && ls -la /output/ && echo '' && echo 'Use: docker cp <container>:/output/ ./frontend-build/'"]
