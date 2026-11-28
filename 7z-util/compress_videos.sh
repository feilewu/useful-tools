#!/bin/bash

# 视频文件压缩脚本
# 使用7Z压缩指定目录中的视频文件，并保持目录结构

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 全局变量，用于跟踪当前正在压缩的文件
current_compress_file=""
# 全局标志，用于指示是否应该停止所有压缩任务
stop_compression=false
# 日志文件路径
LOG_FILE=""

# 信号处理函数，用于在脚本被中断时删除未完成的压缩文件
cleanup() {
    echo -e "\n${RED}收到中断信号，正在停止所有压缩任务...${NC}" >&2
    if [[ -n "$LOG_FILE" ]]; then
        echo -e "\n${RED}收到中断信号，正在停止所有压缩任务...${NC}" | tee -a "$LOG_FILE" >&2
    else
        echo -e "\n${RED}收到中断信号，正在停止所有压缩任务...${NC}" >&2
    fi
    stop_compression=true
    if [[ -n "$current_compress_file" && -f "$current_compress_file" ]]; then
        if [[ -n "$LOG_FILE" ]]; then
            echo -e "${YELLOW}删除未完成的压缩文件: $current_compress_file${NC}" | tee -a "$LOG_FILE" >&2
        else
            echo -e "${YELLOW}删除未完成的压缩文件: $current_compress_file${NC}" >&2
        fi
        rm -f "$current_compress_file"
    fi
    if [[ -n "$LOG_FILE" ]]; then
        echo -e "${RED}压缩任务已停止${NC}" | tee -a "$LOG_FILE" >&2
    else
        echo -e "${RED}压缩任务已停止${NC}" >&2
    fi
    exit 1
}

# 设置信号处理
trap cleanup SIGINT SIGTERM SIGQUIT

# 帮助信息
function show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -s, --source DIR     源目录路径 (默认: 当前目录)"
    echo "  -d, --destination DIR   目标目录路径 (默认: compressed_videos)"
    echo "  -l, --log FILE       日志文件路径 (默认: 不记录日志)"
    echo "  -h, --help           显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -s /path/to/videos -d /path/to/compressed"
    echo "  $0 --source ./videos --destination ./backup --log compress.log"
}

# 默认参数
SOURCE_DIR="."
DEST_DIR="compressed_videos"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--source)
            SOURCE_DIR="$2"
            shift 2
            ;;
        -d|--destination)
            DEST_DIR="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -n "$LOG_FILE" ]]; then
                echo -e "${RED}未知选项: $1${NC}" | tee -a "$LOG_FILE" >&2
            else
                echo -e "${RED}未知选项: $1${NC}" >&2
            fi
            show_help
            exit 1
            ;;
    esac
done

# 检查源目录是否存在
if [ ! -d "$SOURCE_DIR" ]; then
    if [[ -n "$LOG_FILE" ]]; then
        echo -e "${RED}错误: 源目录 '$SOURCE_DIR' 不存在${NC}" | tee -a "$LOG_FILE" >&2
    else
        echo -e "${RED}错误: 源目录 '$SOURCE_DIR' 不存在${NC}" >&2
    fi
    exit 1
fi

# 检查是否安装了7z
if ! command -v 7z &> /dev/null; then
    if [[ -n "$LOG_FILE" ]]; then
        echo -e "${RED}错误: 未找到 7z 命令。请安装 p7zip-full:${NC}" | tee -a "$LOG_FILE" >&2
        echo "  Ubuntu/Debian: sudo apt install p7zip-full" | tee -a "$LOG_FILE"
        echo "  CentOS/RHEL: sudo yum install p7zip p7zip-plugins" | tee -a "$LOG_FILE"
        echo "  Fedora: sudo dnf install p7zip p7zip-plugins" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}错误: 未找到 7z 命令。请安装 p7zip-full:${NC}" >&2
        echo "  Ubuntu/Debian: sudo apt install p7zip-full" >&2
        echo "  CentOS/RHEL: sudo yum install p7zip p7zip-plugins" >&2
        echo "  Fedora: sudo dnf install p7zip p7zip-plugins" >&2
    fi
    exit 1
fi

# 创建目标目录
mkdir -p "$DEST_DIR"

# 定义视频文件扩展名
VIDEO_EXTENSIONS=("mp4" "avi" "mkv" "mov" "wmv" "flv" "webm" "m4v" "mpg" "mpeg" "3gp" "ogv")

# 压缩视频文件的函数
compress_video() {
    local source_file="$1"
    local relative_path="$2"
    
    # 检查是否应该停止压缩
    if [[ "$stop_compression" == true ]]; then
        echo -e "${YELLOW}压缩任务已被中断，跳过: $relative_path${NC}" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # 创建目标目录结构
    local dest_subdir="$DEST_DIR/$(dirname "$relative_path")"
    mkdir -p "$dest_subdir"
    
    # 获取文件名和目录
    local filename=$(basename "$source_file")
    local dest_file="$dest_subdir/${filename%.*}.7z"
    
    # 设置当前正在压缩的文件
    current_compress_file="$dest_file"
    
    echo -e "${YELLOW}正在压缩: $relative_path${NC}" | tee -a "$LOG_FILE"
    
    # 使用7z压缩文件
    if 7z a "$dest_file" "$source_file" -m0=lzma2 -mx=9 -ms=on >> "${LOG_FILE:-/dev/null}" 2>&1; then
        # 检查是否应该停止压缩
        if [[ "$stop_compression" == true ]]; then
            echo -e "${YELLOW}压缩任务已被中断，删除已完成的文件: $dest_file${NC}" | tee -a "$LOG_FILE"
            rm -f "$dest_file"
            current_compress_file=""
            return 1
        fi
        
        # 压缩成功，清除当前文件跟踪
        current_compress_file=""
        echo -e "${GREEN}成功压缩: $relative_path -> $dest_file${NC}" | tee -a "$LOG_FILE"
        # 显示压缩比
        local original_size=$(du -h "$source_file" | cut -f1)
        local compressed_size=$(du -h "$dest_file" | cut -f1)
        echo "  原始大小: $original_size, 压缩后大小: $compressed_size" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}压缩失败: $relative_path${NC}" | tee -a "$LOG_FILE"
        # 删除压缩失败的文件
        if [[ -f "$dest_file" ]]; then
            rm -f "$dest_file"
        fi
        current_compress_file=""
    fi
}

# 查找并压缩视频文件
if [[ -n "$LOG_FILE" ]]; then
    echo -e "${GREEN}开始在 '$SOURCE_DIR' 中查找视频文件...${NC}" | tee -a "$LOG_FILE"
else
    echo -e "${GREEN}开始在 '$SOURCE_DIR' 中查找视频文件...${NC}"
fi

found_videos=0

# 添加对大写扩展名的支持
for extension in "${VIDEO_EXTENSIONS[@]}"; do
    # 检查是否应该停止压缩
    if [[ "$stop_compression" == true ]]; then
        break
    fi
    
    # 处理小写扩展名
    while IFS= read -r -d '' video_file; do
        # 检查是否应该停止压缩
        if [[ "$stop_compression" == true ]]; then
            break
        fi
        
        # 获取相对于源目录的路径
        relative_path="${video_file#$SOURCE_DIR/}"
        if [ "$relative_path" = "$video_file" ]; then
            relative_path="$video_file"
        fi
        
        # 压缩视频文件
        compress_video "$video_file" "$relative_path"
        ((found_videos++))
    done < <(find "$SOURCE_DIR" -type f -name "*.$extension" -print0)
    
    # 处理大写扩展名
    while IFS= read -r -d '' video_file; do
        # 检查是否应该停止压缩
        if [[ "$stop_compression" == true ]]; then
            break
        fi
        
        # 获取相对于源目录的路径
        relative_path="${video_file#$SOURCE_DIR/}"
        if [ "$relative_path" = "$video_file" ]; then
            relative_path="$video_file"
        fi
        
        # 压缩视频文件
        compress_video "$video_file" "$relative_path"
        ((found_videos++))
    done < <(find "$SOURCE_DIR" -type f -name "*.${extension^^}" -print0)
done

if [ $found_videos -eq 0 ]; then
    if [[ -n "$LOG_FILE" ]]; then
        echo -e "${YELLOW}未在 '$SOURCE_DIR' 中找到视频文件${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}未在 '$SOURCE_DIR' 中找到视频文件${NC}"
    fi
else
    if [[ -n "$LOG_FILE" ]]; then
        echo -e "${GREEN}压缩完成！共处理 $found_videos 个视频文件。${NC}" | tee -a "$LOG_FILE"
        echo "压缩文件保存在: $DEST_DIR" | tee -a "$LOG_FILE"
    else
        echo -e "${GREEN}压缩完成！共处理 $found_videos 个视频文件。${NC}"
        echo "压缩文件保存在: $DEST_DIR"
    fi
fi