#!/bin/bash

# 创建测试目录结构和文件

echo "创建测试目录结构..."

mkdir -p test_videos/movies/action
mkdir -p test_videos/movies/comedy
mkdir -p test_videos/tvshows

# 创建一些空的测试文件来模拟视频文件
touch test_videos/movies/action/movie1.mp4
touch test_videos/movies/action/movie2.mkv
touch test_videos/movies/comedy/comedy1.avi
touch test_videos/movies/comedy/comedy2.mov
touch test_videos/tvshows/episode1.mp4
touch test_videos/tvshows/episode2.webm

echo "测试目录结构创建完成:"
echo "test_videos/"
echo "├── movies/"
echo "│   ├── action/"
echo "│   │   ├── movie1.mp4"
echo "│   │   └── movie2.mkv"
echo "│   └── comedy/"
echo "│       ├── comedy1.avi"
echo "│       └── comedy2.mov"
echo "└── tvshows/"
echo "    ├── episode1.mp4"
echo "    └── episode2.webm"

echo ""
echo "您可以运行以下命令来测试压缩脚本:"
echo "./compress_videos.sh -s test_videos -d compressed_test"