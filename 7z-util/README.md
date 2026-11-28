# 7Z 视频文件压缩工具

该工具可以使用 7-Zip 压缩指定目录中的视频文件，并保持原有的目录结构。

## 功能特性

- 递归查找目录中的视频文件
- 使用 7-Zip 高效压缩
- 保持原有目录结构
- 支持多种视频格式
- 显示压缩进度和统计信息
- 支持加密压缩和解密还原
- 智能跳过已压缩的文件
- 支持随机文件名（通过配置开关开启）

## 支持的视频格式

- MP4
- AVI
- MKV
- MOV
- WMV
- FLV
- WEBM
- M4V
- MPG/MPEG
- 3GP
- OGV

## 安装依赖

在使用脚本之前，需要安装 7-Zip 工具：

### Ubuntu/Debian:
```bash
sudo apt update
sudo apt install p7zip-full
```

### CentOS/RHEL:
```bash
sudo yum install p7zip p7zip-plugins
```

### Fedora:
```bash
sudo dnf install p7zip p7zip-plugins
```

## 使用方法

本工具提供两个版本的脚本：

1. **完整版** ([compress_videos.sh](file:///home/ubuntu/vscode/7z-util/compress_videos.sh)) - 使用命令行参数控制
2. **简化版** ([simple_compress.sh](file:///home/ubuntu/vscode/7z-util/simple_compress.sh)) - 使用配置文件控制（推荐）

### 使用简化版脚本（推荐）

1. 编辑 [compress.conf](file:///home/ubuntu/vscode/7z-util/compress.conf) 配置文件:
   ```bash
   # 源目录 (输入目录)
   SOURCE_DIR=./test_videos
   
   # 目标目录 (输出目录)
   DEST_DIR=./compressed_videos
   
   # 是否启用加密 (true/false)
   ENCRYPTION_ENABLED=false
   
   # 加密密码 (仅在启用加密时使用)
   ENCRYPTION_PASSWORD=your_password_here
   
   # 包含的文件扩展名 (以空格分隔)
   INCLUDE_EXTENSIONS="mp4 avi mkv mov wmv flv webm m4v mpg mpeg 3gp ogv"
   
   # 排除的文件扩展名 (以空格分隔)
   EXCLUDE_EXTENSIONS=""
   ```

2. 运行脚本:
   ```bash
   ./simple_compress.sh
   ```

### 使用完整版脚本

```bash
./compress_videos.sh -s /path/to/videos -d /path/to/output
```

或者使用长选项：
```bash
./compress_videos.sh --source /path/to/videos --destination /path/to/output
```

## 配置选项说明

### 简化版脚本配置文件选项

- `SOURCE_DIR`: 输入目录，包含需要压缩的视频文件
- `DEST_DIR`: 输出目录，压缩后的文件将存放在此目录中
- `ENCRYPTION_ENABLED`: 是否启用加密 (true/false)
- `ENCRYPTION_PASSWORD`: 加密密码 (仅在启用加密时使用)
- `INCLUDE_EXTENSIONS`: 包含的文件扩展名列表，以空格分隔
- `EXCLUDE_EXTENSIONS`: 排除的文件扩展名列表，以空格分隔
- `COMPRESSION_METHOD`: 压缩算法 (默认: lzma2)
- `COMPRESSION_LEVEL`: 压缩级别 1-9 (默认: 9)
- `SOLID_COMPRESSION`: 固实压缩 (默认: on)
- `RANDOM_NAME_ENABLED`: 是否启用随机文件名 (true/false，默认: false)。启用后，压缩目标文件将使用 md5(原文件名)_时间戳 命名，无法通过固定文件名判断是否已压缩，因此每次运行都会重新压缩

## 重复压缩检测

脚本具有智能检测功能，可以避免重复压缩已经压缩过的文件：

- 自动检查目标目录中是否已存在对应的压缩文件
- 比较源文件和目标压缩文件的时间戳
- 如果源文件未被修改，则跳过压缩
- 如果源文件已被修改，则重新压缩
- 显示跳过文件的信息，提高处理效率

## 测试用例

项目包含测试脚本来验证各种功能：

### 加密压缩测试
```bash
./test_encryption.sh
```

该测试脚本会：
1. 创建测试文件和目录结构
2. 使用加密配置压缩文件
3. 验证压缩文件的加密保护（无密码无法解压）
4. 使用正确密码解压文件
5. 校验解压后的文件与原始文件一致性
6. 验证目录结构保持一致

### 重复压缩检测测试
```bash
./test_skip_compressed.sh
```

该测试脚本会：
1. 创建测试文件
2. 第一次运行压缩所有文件
3. 第二次运行验证跳过所有已压缩文件
4. 修改一个源文件
5. 第三次运行验证只压缩修改过的文件

## 压缩选项

脚本使用以下 7-Zip 参数进行压缩：
- `-m0=lzma2`: 使用 LZMA2 压缩算法
- `-mx=9`: 使用最高压缩比
- `-ms=on`: 启用固实压缩

## 示例

假设您的目录结构如下：
```
videos/
├── movies/
│   ├── action/
│   │   └── movie1.mp4
│   └── comedy/
│       └── movie2.avi
└── tvshows/
    └── episode1.mkv
```

运行命令：
```bash
./simple_compress.sh
```

将会生成：
```
compressed/
├── movies/
│   ├── action/
│   │   └── movie1.7z
│   └── comedy/
│       └── movie2.7z
└── tvshows/
    └── episode1.7z
```

## 注意事项

1. 压缩过程不会删除原始视频文件
2. 脚本会自动创建目标目录（如果不存在）
3. 如果目标目录中已存在同名的 .7z 文件，将会被覆盖
4. 压缩速度取决于文件大小和系统性能