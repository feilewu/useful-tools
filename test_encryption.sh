#!/bin/bash

# 测试加密压缩和解密还原功能的脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}开始测试加密压缩和解密还原功能...${NC}"

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
mkdir -p test_encryption/source
mkdir -p test_encryption/compressed
mkdir -p test_encryption/extracted

# 创建测试文件
echo "This is a test file for encryption compression test." > test_encryption/source/test1.txt
echo "Another test file with different content for verification." > test_encryption/source/test2.log
mkdir -p test_encryption/source/subdir
echo "File in subdirectory for testing structure preservation." > test_encryption/source/subdir/test3.txt

echo -e "${GREEN}测试文件创建完成${NC}"

# 创建加密配置文件
echo -e "${YELLOW}创建加密配置文件...${NC}"
cat > test_encryption/encrypt.conf << EOF
# 加密测试配置文件
SOURCE_DIR=./source
DEST_DIR=./compressed
ENCRYPTION_ENABLED=true
ENCRYPTION_PASSWORD=TestPassword123
INCLUDE_EXTENSIONS="txt log"
EXCLUDE_EXTENSIONS=""
COMPRESSION_METHOD=lzma2
COMPRESSION_LEVEL=9
SOLID_COMPRESSION=on
EOF

echo -e "${GREEN}加密配置文件创建完成${NC}"

# 复制简化版压缩脚本并修改以适应测试
echo -e "${YELLOW}准备压缩脚本...${NC}"
cp simple_compress.sh test_encryption/compress_test.sh

# 修改脚本中的默认配置文件路径
sed -i 's/CONFIG_FILE="\.\/compress\.conf"/CONFIG_FILE="\.\/encrypt\.conf"/' test_encryption/compress_test.sh

echo -e "${GREEN}压缩脚本准备完成${NC}"

# 执行加密压缩
echo -e "${YELLOW}执行加密压缩...${NC}"
cd test_encryption
./compress_test.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}加密压缩失败${NC}"
    exit 1
fi

echo -e "${GREEN}加密压缩完成${NC}"

# 验证压缩文件是否存在
echo -e "${YELLOW}验证压缩文件...${NC}"
if [ ! -f "compressed/test1.7z" ] || [ ! -f "compressed/test2.7z" ] || [ ! -f "compressed/subdir/test3.7z" ]; then
    echo -e "${RED}压缩文件未正确生成${NC}"
    exit 1
fi

echo -e "${GREEN}压缩文件验证通过${NC}"

# 尝试在没有密码的情况下解压（应该失败）
echo -e "${YELLOW}测试无密码解压（应该失败）...${NC}"
set +e
7z x compressed/test1.7z -oextracted_fail 2>/dev/null
EXTRACT_RESULT=$?
set -e

if [ $EXTRACT_RESULT -eq 0 ]; then
    echo -e "${RED}警告：无密码解压成功，可能存在安全问题${NC}"
else
    echo -e "${GREEN}无密码解压失败，加密保护正常工作${NC}"
fi

# 执行解密还原
echo -e "${YELLOW}执行解密还原...${NC}"
mkdir -p extracted

7z x compressed/test1.7z -oextracted -pTestPassword123
7z x compressed/test2.7z -oextracted -pTestPassword123
mkdir -p extracted/subdir
7z x compressed/subdir/test3.7z -oextracted/subdir -pTestPassword123

echo -e "${GREEN}解密还原完成${NC}"

# 校验文件一致性
echo -e "${YELLOW}校验文件一致性...${NC}"

# 比较文件内容
diff source/test1.txt extracted/test1.txt
if [ $? -eq 0 ]; then
    echo -e "${GREEN}test1.txt 文件一致性校验通过${NC}"
else
    echo -e "${RED}test1.txt 文件一致性校验失败${NC}"
fi

diff source/test2.log extracted/test2.log
if [ $? -eq 0 ]; then
    echo -e "${GREEN}test2.log 文件一致性校验通过${NC}"
else
    echo -e "${RED}test2.log 文件一致性校验失败${NC}"
fi

diff source/subdir/test3.txt extracted/subdir/test3.txt
if [ $? -eq 0 ]; then
    echo -e "${GREEN}subdir/test3.txt 文件一致性校验通过${NC}"
else
    echo -e "${RED}subdir/test3.txt 文件一致性校验失败${NC}"
fi

# 校验目录结构
if [ -d "extracted/subdir" ]; then
    echo -e "${GREEN}目录结构保持一致${NC}"
else
    echo -e "${RED}目录结构不一致${NC}"
fi

# 测试重复压缩功能
echo -e "${YELLOW}测试重复压缩检测功能...${NC}"
echo -e "${BLUE}再次运行压缩脚本，应该跳过已压缩的文件...${NC}"
./compress_test.sh | grep "跳过文件"

echo -e "${GREEN}重复压缩检测测试完成${NC}"

# 清理测试文件（可选）
echo -e "${YELLOW}是否清理测试文件？(y/N)${NC}"
read -n 1 -r cleanup
echo
if [[ $cleanup =~ ^[Yy]$ ]]; then
    cd ..
    rm -rf test_encryption
    echo -e "${GREEN}测试文件已清理${NC}"
else
    echo -e "${BLUE}测试文件保留在 test_encryption 目录中${NC}"
fi

echo -e "${GREEN}测试完成${NC}"