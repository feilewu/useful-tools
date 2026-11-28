# 向 feilewu/useful-tools 仓库推送的约束

## 核心原则
向 `https://github.com/feilewu/useful-tools.git` 推送时，**不要直接把文件推到仓库根目录**。每个工具应放在独立的子目录下，避免污染根目录，保持仓库结构整洁。

## 正确目录结构示例
```
useful-tools/ (远程仓库)
├── 7z-util/              ← 7Z 视频压缩工具，已就位
│   ├── README.md
│   ├── compress.conf
│   ├── compress_videos.sh
│   ├── simple_compress.sh
│   ├── test_*.sh
│   └── .gitignore
├── idle-traffic/         ← 原有内容，保留
├── ipage-visit/          ← 原有内容，保留
└── x_dl.sh               ← 原有内容，保留
```

## 添加新工具的操作规范
1. 在本地仓库根创建独立子目录：`mkdir -p 新工具名/`
2. 将该工具的所有脚本、配置、测试文件放入该子目录
3. 添加 `.gitignore` 排除二进制产物、日志、测试生成数据（如 `*.7z`, `*.log`, `test_*/` 等）
4. `git add 新工具名/`、`git commit`、`git push origin main`

## 禁止行为
- ❌ 直接将脚本、配置文件等丢在仓库根目录（如 `compress_videos.sh` 放在根目录）
- ❌ 将 `.7z` 压缩包、`*.log` 日志、`test_*/` 测试数据提交到仓库

## 相关仓库
- 远程：`https://github.com/feilewu/useful-tools.git`
- 本地克隆：`/home/xpf/ai/7z-util/`
