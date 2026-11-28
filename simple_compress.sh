#!/bin/bash

# 简化版视频文件压缩脚本
# 使用配置文件配置源目录、目标目录、加密选项等

# 配置文件路径
CONFIG_FILE="./compress.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量，用于跟踪当前正在压缩的文件
current_compress_file=""
# 全局标志，用于指示是否应该停止所有压缩任务
stop_compression=false
# 日志文件路径
LOG_FILE=""

# 信号处理函数，用于在脚本被中断时删除未完成的压缩文件
cleanup() {
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
    echo "  -c, --config FILE   配置文件路径 (默认: ./compress.conf)"
    echo "  -l, --log FILE      日志文件路径 (默认: 不记录日志)"
    echo "  -h, --help          显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0"
    echo "  $0 -c /path/to/config.conf"
    echo "  $0 -c /path/to/config.conf -l compress.log"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
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

# 加载配置文件
source "$CONFIG_FILE"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    if [[ -n "$LOG_FILE" ]]; then
        echo -e "${RED}错误: 配置文件 '$CONFIG_FILE' 不存在${NC}" | tee -a "$LOG_FILE" >&2
        echo "请创建配置文件或使用 -c 指定配置文件路径" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}错误: 配置文件 '$CONFIG_FILE' 不存在${NC}" >&2
        echo "请创建配置文件或使用 -c 指定配置文件路径" >&2
    fi
    exit 1
fi

# 如果命令行参数未指定日志文件，则使用配置文件中的设置
if [[ -z "$LOG_FILE" && -n "$DEFAULT_LOG_FILE" ]]; then
    LOG_FILE="$DEFAULT_LOG_FILE"
fi

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

# 将包含的扩展名转换为数组
read -ra INCLUDE_ARRAY <<< "$INCLUDE_EXTENSIONS"

# 将排除的扩展名转换为数组
read -ra EXCLUDE_ARRAY <<< "$EXCLUDE_EXTENSIONS"

# 检查文件是否已经压缩的函数
is_file_compressed() {
    local source_file="$1"
    local relative_path="$2"
    
    # 获取文件名和目录
    local filename=$(basename "$source_file")
    local dest_subdir="$DEST_DIR/$(dirname "$relative_path")"
    local dest_file="$dest_subdir/${filename%.*}.7z"
    
    # 检查目标压缩文件是否存在
    if [ -f "$dest_file" ]; then
        # 获取源文件和目标文件的修改时间
        local source_mtime=$(stat -c %Y "$source_file" 2>/dev/null || echo "0")
        local dest_mtime=$(stat -c %Y "$dest_file" 2>/dev/null || echo "0")
        
        # 如果目标文件的修改时间晚于源文件，认为已经压缩过了
        if [ "$dest_mtime" -ge "$source_mtime" ]; then
            return 0  # 已经压缩
        fi
    fi
    
    return 1  # 未压缩或需要重新压缩
}

# 压缩视频文件的函数
compress_video() {
    local source_file="$1"
    local relative_path="$2"
    
    # 检查是否应该停止压缩
    if [[ "$stop_compression" == true ]]; then
        echo -e "${YELLOW}压缩任务已被中断，跳过: $relative_path${NC}" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # 检查文件扩展名是否在排除列表中
    local file_ext="${source_file##*.}"
    for exclude_ext in "${EXCLUDE_ARRAY[@]}"; do
        if [[ "$file_ext" == "$exclude_ext" ]]; then
            echo -e "${YELLOW}跳过文件 (排除的扩展名): $relative_path${NC}" | tee -a "$LOG_FILE"
            return 0
        fi
    done
    
    # 检查文件是否已经压缩
    if is_file_compressed "$source_file" "$relative_path"; then
        echo -e "${BLUE}跳过文件 (已压缩): $relative_path${NC}" | tee -a "$LOG_FILE"
        return 0
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
    
    # 构建7z命令
    local cmd="7z a"
    
    # 添加压缩选项
    cmd+=" -m0=$COMPRESSION_METHOD"
    cmd+=" -mx=$COMPRESSION_LEVEL"
    cmd+=" -ms=$SOLID_COMPRESSION"
    
    # 如果启用加密，添加密码选项
    if [[ "$ENCRYPTION_ENABLED" == "true" ]]; then
        cmd+=" -p$ENCRYPTION_PASSWORD"
        cmd+=" -mhe=on"
    fi
    
    # 执行压缩
    if $cmd "$dest_file" "$source_file" >> "${LOG_FILE:-/dev/null}" 2>&1; then
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
        if command -v du &> /dev/null; then
            local original_size=$(du -h "$source_file" 2>/dev/null | cut -f1)
            local compressed_size=$(du -h "$dest_file" 2>/dev/null | cut -f1)
            if [[ -n "$original_size" && -n "$compressed_size" ]]; then
                echo "  原始大小: $original_size, 压缩后大小: $compressed_size" | tee -a "$LOG_FILE"
            fi
        fi
        return 0
    else
        echo -e "${RED}压缩失败: $relative_path${NC}" | tee -a "$LOG_FILE"
        # 删除压缩失败的文件
        if [[ -f "$dest_file" ]]; then
            rm -f "$dest_file"
        fi
        current_compress_file=""
        return 1
    fi
}

# 查找并压缩视频文件
if [[ -n "$LOG_FILE" ]]; then
    echo -e "${GREEN}开始在 '$SOURCE_DIR' 中查找视频文件...${NC}" | tee -a "$LOG_FILE"
else
    echo -e "${GREEN}开始在 '$SOURCE_DIR' 中查找视频文件...${NC}"
fi

found_videos=0
compressed_videos=0

# 添加对大写扩展名的支持
for extension in "${INCLUDE_ARRAY[@]}"; do
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
        if compress_video "$video_file" "$relative_path"; then
            ((found_videos++))
            # 检查是否实际执行了压缩（而不是跳过）
            filename=$(basename "$video_file")
            dest_subdir="$DEST_DIR/$(dirname "$relative_path")"
            dest_file="$dest_subdir/${filename%.*}.7z"
            if [ -f "$dest_file" ]; then
                # 检查文件是否是刚刚创建或更新的
                dest_mtime=$(stat -c %Y "$dest_file" 2>/dev/null || echo "0")
                current_time=$(date +%s)
                time_diff=$((current_time - dest_mtime))
                # 如果文件在最近10秒内修改过，认为是新压缩的
                if [ "$time_diff" -lt 10 ]; then
                    ((compressed_videos++))
                fi
            fi
        fi
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
        if compress_video "$video_file" "$relative_path"; then
            ((found_videos++))
            # 检查是否实际执行了压缩（而不是跳过）
            filename=$(basename "$video_file")
            dest_subdir="$DEST_DIR/$(dirname "$relative_path")"
            dest_file="$dest_subdir/${filename%.*}.7z"
            if [ -f "$dest_file" ]; then
                # 检查文件是否是刚刚创建或更新的
                dest_mtime=$(stat -c %Y "$dest_file" 2>/dev/null || echo "0")
                current_time=$(date +%s)
                time_diff=$((current_time - dest_mtime))
                # 如果文件在最近10秒内修改过，认为是新压缩的
                if [ "$time_diff" -lt 10 ]; then
                    ((compressed_videos++))
                fi
            fi
        fi
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
        echo -e "${GREEN}压缩完成！共找到 $found_videos 个视频文件，实际压缩了 $compressed_videos 个文件。${NC}" | tee -a "$LOG_FILE"
        echo "压缩文件保存在: $DEST_DIR" | tee -a "$LOG_FILE"
    else
        echo -e "${GREEN}压缩完成！共找到 $found_videos 个视频文件，实际压缩了 $compressed_videos 个文件。${NC}"
        echo "压缩文件保存在: $DEST_DIR"
    fi
fi