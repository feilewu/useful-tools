#!/bin/bash

# 测试重复压缩检测功能的简单脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}开始测试重复压缩检测功能...${NC}"

# 检查是否安装了7z
if ! command -v 7z &> /dev/null; then
    echo -e "${RED}错误: 未找到 7z 命令。请安装 p7zip-full:${NC}"
    echo "  Ubuntu/Debian: sudo apt install p7zip-full"
    echo "  CentOS/RHEL: sudo yum install p7zip p7zip-plugins"
    echo "  Fedora: sudo dnf install p7zip p7zip-plugins"
    exit 1
fi

# 创建测试目录和文件
echo -e "${YELLOW}创建测试环境...${NC}"
mkdir -p test_skip/source
mkdir -p test_skip/compressed

# 创建测试文件
echo "This is a test file for skip compression test." > test_skip/source/test1.txt
echo "Another test file with different content." > test_skip/source/test2.log
mkdir -p test_skip/source/subdir
echo "File in subdirectory." > test_skip/source/subdir/test3.txt

echo -e "${GREEN}测试文件创建完成${NC}"

# 创建配置文件
echo -e "${YELLOW}创建配置文件...${NC}"
cat > test_skip/test.conf << EOF
# 测试配置文件
SOURCE_DIR=./source
DEST_DIR=./compressed
ENCRYPTION_ENABLED=false
ENCRYPTION_PASSWORD=
INCLUDE_EXTENSIONS="txt log"
EXCLUDE_EXTENSIONS=""
COMPRESSION_METHOD=lzma2
COMPRESSION_LEVEL=9
SOLID_COMPRESSION=on
EOF

echo -e "${GREEN}配置文件创建完成${NC}"

# 复制简化版压缩脚本
echo -e "${YELLOW}准备压缩脚本...${NC}"
cp simple_compress.sh test_skip/compress_test.sh
sed -i 's/CONFIG_FILE="\.\/compress\.conf"/CONFIG_FILE="\.\/test.conf"/' test_skip/compress_test.sh

echo -e "${GREEN}压缩脚本准备完成${NC}"

# 第一次运行压缩
echo -e "${YELLOW}第一次运行压缩...${NC}"
cd test_skip
./compress_test.sh

# 等待几秒钟确保文件时间戳不同
sleep 2

# 第二次运行压缩，应该跳过所有文件
echo -e "${YELLOW}第二次运行压缩，应该跳过所有文件...${NC}"
echo -e "${BLUE}==============================${NC}"
./compress_test.sh
echo -e "${BLUE}==============================${NC}"

# 修改一个源文件
echo -e "${YELLOW}修改一个源文件...${NC}"
echo "Modified content for re-compression test." > source/test1.txt

# 第三次运行压缩，应该只压缩修改过的文件
echo -e "${YELLOW}第三次运行压缩，应该只压缩修改过的文件...${NC}"
echo -e "${BLUE}==============================${NC}"
./compress_test.sh
echo -e "${BLUE}==============================${NC}"

# 清理测试文件
cd ..
rm -rf test_skip
echo -e "${GREEN}测试完成，清理测试文件${NC}"