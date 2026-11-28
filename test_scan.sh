#!/bin/bash

# 测试视频文件扫描功能

SOURCE_DIR="/tmp/test_videos"
VIDEO_EXTENSIONS=("mp4" "avi" "mkv" "mov" "wmv" "flv" "webm" "m4v" "mpg" "mpeg" "3gp" "ogv")

echo "扫描目录: $SOURCE_DIR"
echo "支持的视频格式: ${VIDEO_EXTENSIONS[@]}"
echo ""

found_videos=0

for extension in "${VIDEO_EXTENSIONS[@]}"; do
    echo "查找 .$extension 文件:"
    while IFS= read -r -d '' video_file; do
        relative_path="${video_file#$SOURCE_DIR/}"
        if [ "$relative_path" = "$video_file" ]; then
            relative_path="$video_file"
        fi
        echo "  找到: $relative_path"
        ((found_videos++))
    done < <(find "$SOURCE_DIR" -type f -name "*.$extension" -print0)
    echo ""
done

echo "总共找到 $found_videos 个视频文件"