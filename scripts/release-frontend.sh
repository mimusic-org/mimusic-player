#!/bin/bash

# Songloft Flutter 前端版本发布脚本
# 用法：./scripts/release-frontend.sh [major|minor|patch]
# 示例：./scripts/release-frontend.sh patch  # 1.0.0 -> 1.0.1

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录（脚本位于 frontend/scripts/ 下）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$FRONTEND_DIR")"

# 文件路径
PUBSPEC_FILE="$FRONTEND_DIR/pubspec.yaml"

# 帮助信息
show_help() {
    echo -e "${BLUE}Songloft Flutter 前端版本发布工具${NC}"
    echo ""
    echo "用法:"
    echo "  $0 [major|minor|patch]"
    echo ""
    echo "参数:"
    echo "  major  - 主版本号升级 (1.0.0 -> 2.0.0)"
    echo "  minor  - 次版本号升级 (1.0.0 -> 1.1.0)"
    echo "  patch  - 补丁版本号升级 (1.0.0 -> 1.0.1，默认)"
    echo ""
    echo "示例:"
    echo "  $0 patch   # 1.0.0 -> 1.0.1"
    echo "  $0 minor   # 1.0.0 -> 1.1.0"
    echo "  $0 major   # 1.0.0 -> 2.0.0"
    echo ""
}

# 检查是否在 git 仓库中
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}错误：当前目录不是 git 仓库${NC}"
        exit 1
    fi
}

# 检查是否有未提交的更改
check_uncommitted_changes() {
    if ! git diff-index --quiet HEAD --; then
        echo -e "${YELLOW}警告：存在未提交的更改${NC}"
        read -p "是否继续？(y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}已取消${NC}"
            exit 1
        fi
    fi
}

# 获取当前版本号
get_current_version() {
    if [ ! -f "$PUBSPEC_FILE" ]; then
        echo -e "${RED}错误：找不到 pubspec.yaml 文件${NC}"
        exit 1
    fi

    # 从 pubspec.yaml 中提取版本号 (格式：version: X.Y.Z+W)
    local version_line
    version_line=$(grep '^version:' "$PUBSPEC_FILE" | head -1)

    if [ -z "$version_line" ]; then
        echo -e "${RED}错误：pubspec.yaml 中找不到 version 字段${NC}"
        exit 1
    fi

    # 提取版本号部分 (去掉 "version: " 前缀)
    echo "$version_line" | sed 's/version: //' | cut -d'+' -f1
}

# 解析版本号
parse_version() {
    local version=$1
    # 去掉可能的 'v' 前缀
    echo "$version" | sed 's/^v//'
}

# 升级版本号
bump_version() {
    local version=$1
    local bump_type=$2

    # 分解版本号
    local major minor patch
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    patch=$(echo "$version" | cut -d. -f3)

    # 验证版本号格式
    if ! [[ "$major" =~ ^[0-9]+$ ]] || ! [[ "$minor" =~ ^[0-9]+$ ]] || ! [[ "$patch" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误：无效的版本号格式 '$version'${NC}"
        exit 1
    fi

    case $bump_type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo -e "${RED}错误：无效的升级类型 '$bump_type'${NC}"
            echo "用法：$0 [major|minor|patch]"
            exit 1
            ;;
    esac

    echo "$major.$minor.$patch"
}

# 更新 pubspec.yaml 中的版本号
update_pubspec() {
    local new_version=$1
    local build_number

    # 获取当前的 build number (+W 部分)
    local current_version_line
    current_version_line=$(grep '^version:' "$PUBSPEC_FILE" | head -1)

    if [[ "$current_version_line" == *"+"* ]]; then
        build_number=$(echo "$current_version_line" | sed 's/.*+//')
    else
        build_number="1"
    fi

    # 更新版本号，保留 build number
    local new_version_full="${new_version}+${build_number}"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^version: .*/version: ${new_version_full}/" "$PUBSPEC_FILE"
    else
        sed -i "s/^version: .*/version: ${new_version_full}/" "$PUBSPEC_FILE"
    fi

    echo -e "${GREEN}✓${NC} pubspec.yaml 已更新为 ${new_version_full}"
}

# 创建 git tag
create_git_tag() {
    local new_version=$1
    local tag_name="v$new_version"

    # 检查 tag 是否已存在
    if git rev-parse "$tag_name" >/dev/null 2>&1; then
        echo -e "${YELLOW}警告：Git 标签 '$tag_name' 已存在${NC}"
        read -p "是否覆盖现有标签？(y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git tag -d "$tag_name" >/dev/null 2>&1 || true
            git push origin ":refs/tags/$tag_name" >/dev/null 2>&1 || true
            echo -e "${YELLOW}✓ 已删除旧标签${NC}"
        else
            echo -e "${RED}已取消${NC}"
            exit 1
        fi
    fi

    # 创建新的 annotated tag
    git tag -a "$tag_name" -m "Frontend release version $new_version"
    echo -e "${GREEN}✓${NC} Git 标签 ${tag_name} 已创建"
}

# 推送 git tag 到远程仓库
push_git_tag() {
    local new_version=$1
    local tag_name="v$new_version"

    echo -e "${BLUE}[推送]${NC} 正在推送 Git 标签到远程仓库..."

    if git push origin "$tag_name"; then
        echo -e "${GREEN}✓${NC} Git 标签 ${tag_name} 已推送到远程仓库"
    else
        echo -e "${RED}✗${NC} 推送 Git 标签失败"
        exit 1
    fi
}

# 提交更改
commit_changes() {
    local new_version=$1

    echo -e "${BLUE}[提交]${NC} 提交更改到 git..."

    # 添加修改的文件
    git add "$PUBSPEC_FILE" 2>/dev/null || true

    # 检查是否有内容需要提交
    if ! git diff-index --quiet --cached HEAD --; then
        git commit -m "chore(frontend): release version $new_version" > /dev/null 2>&1
        echo -e "${GREEN}✓${NC} 更改已提交到 git"
    else
        echo -e "${YELLOW}⚠${NC} 没有检测到需要提交的更改"
    fi
}

# 主函数
main() {
    local bump_type=${1:-patch}

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Songloft Flutter 前端版本发布工具${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # 检查
    check_git_repo
    check_uncommitted_changes

    # 获取当前版本
    local current_version
    current_version=$(get_current_version)
    current_version=$(parse_version "$current_version")

    # 计算新版本
    local new_version
    new_version=$(bump_version "$current_version" "$bump_type")

    echo -e "${BLUE}当前版本:${NC} $current_version"
    echo -e "${BLUE}新版本:${NC} $new_version"
    echo -e "${BLUE}升级类型:${NC} $bump_type"
    echo ""

    # 确认
    read -p "确认发布 Flutter 前端新版本？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}已取消${NC}"
        exit 1
    fi

    echo ""
    echo -e "${BLUE}开始发布流程...${NC}"
    echo ""

    # 更新 pubspec.yaml
    echo -e "${BLUE}[1/5]${NC} 更新 pubspec.yaml 中的版本号..."
    update_pubspec "$new_version"

    # 提交更改
    echo -e "${BLUE}[3/5]${NC} 提交更改到 git..."
    commit_changes "$new_version"

    # 创建 git tag
    echo -e "${BLUE}[4/5]${NC} 创建 git tag..."
    create_git_tag "$new_version"

    # 推送 git tag
    echo -e "${BLUE}[5/5]${NC} 推送 git tag 到远程仓库..."
    push_git_tag "$new_version"

    git push --follow-tags

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Flutter 前端版本发布完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}新版本:${NC} $new_version"
    echo -e "${BLUE}Git Tag:${NC} v$new_version"
    echo -e "${BLUE}Release URL:${NC} https://github.com/songloft-org/songloft-player/releases/tag/v$new_version"
    echo ""
}

# 检查参数
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_help
    exit 0
fi

# 执行主函数
main "$@"
