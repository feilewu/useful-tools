# ipage-visit

每天访问一次下面两个站点：

- https://ipage.kesug.com/
- https://ipage.byethost18.com/

单个 Python 文件，只依赖标准库。

## 为什么不能直接 `curl`

这两个站前面是 openresty 的反爬，会按 User-Agent 区别对待：

| User-Agent | 结果 |
|---|---|
| `curl/7.88.1`、`python-requests`、`Wget` | 连接被直接关闭，0 字节，`curl: (52)` |
| `Go-http-client/1.1` | `403 Forbidden` |
| 浏览器 UA | `200`，但内容是 `aes.js` 挑战页（约 850 字节） |
| `Googlebot/2.1` | `200`，直接返回真实页面 |

TCP 握手是成功的，请求也发出去了；服务端收下后直接 FIN，不返回任何数据。这不是 DNS、防火墙或 TLS 问题。

## 脚本做了什么

1. 用浏览器 UA 请求首页，拿到 `aes.js` 挑战页；
2. 从页面里解析 `a`（key）、`b`（IV）、`c`（密文）三个 16 字节参数；
3. 纯 Python 做一次 AES-128-CBC 单分组解密，得到 `__test` cookie 的值；
4. 带上 cookie 请求 `/?i=1`，拿到真实页面（`<title>Hello World</title>`）；
5. 校验响应不是挑战页、状态码 200、内容长度正常；
6. 失败时按次数重试，最后用 `Googlebot/2.1` UA 兜底直连。

脚本不执行远程 JavaScript，也不需要 Java、jar 包、Node 或任何第三方 Python 包。

## 用法

```bash
# 默认访问两个站点
python3 visit_blog.py

# 输出示例
2026-11-22 15:38:25 CST OK   ipage.kesug.com        via=challenge http=200 bytes=7070  1.6s title='Hello World'
2026-11-22 15:38:25 CST OK   ipage.byethost18.com   via=challenge http=200 bytes=7205  1.6s title='Hello World'
---- 2/2 成功

# JSON 输出，便于监控
python3 visit_blog.py --json

# 自定义地址 / 超时 / 重试
python3 visit_blog.py --url https://ipage.kesug.com/ --timeout 30 --retries 3
```

常用参数：

| 参数 | 说明 |
|---|---|
| `--url URL` | 要访问的地址，可重复；默认两个 ipage 站点 |
| `--timeout N` | 单次请求超时秒数，默认 20 |
| `--retries N` | 每个地址重试次数，默认 2 |
| `--retry-delay N` | 重试退避基数，默认 3 秒 |
| `--tz` | 日志时区，默认 `Asia/Shanghai` |
| `--insecure` | 跳过 HTTPS 证书校验（一般不需要） |
| `--no-bot-fallback` | 禁用 Googlebot UA 兜底 |
| `--json` | JSON 输出 |

退出码：全部成功 `0`，任一站点失败 `1`。

## 部署到服务器的 RunWisp

把 `visit_blog.py` 和 `install.sh` 放到目标机器（运行 RunWisp 的服务器）上，然后执行：

```bash
sudo bash /var/tmp/ipage-visit/install.sh
```

`install.sh` 会做四件事：

1. 把脚本安装到 `/opt/ipage-visit/visit_blog.py`（属主 `runwisp:runwisp`，755）；
2. 如果 `/etc/runwisp/runwisp.toml` 里还没有 `[tasks.ipage-visit]`，追加任务并备份原文件；
3. `runwisp validate`，再以 `runwisp` 身份 `runwisp reload`；
4. 立即手动跑一次并列出任务。

追加的任务配置：

```toml
[tasks.ipage-visit]
description = "每天访问 ipage 两个站点"
cron        = "17 9 * * *"
timezone    = "Asia/Shanghai"
on_overlap  = "skip"
catch_up    = 1
timeout     = "3m"
keep_runs   = 90
run         = "/usr/bin/python3 /opt/ipage-visit/visit_blog.py"
```

即每天北京时间 **09:17** 执行一次；错过（服务器宕机）会在启动后补跑最近一次；保留 90 次运行记录。

## 验证

```bash
# 任务是否注册（读配置文件即可）
runwisp list -c /etc/runwisp/runwisp.toml

# 立即跑一次（socket 只认同 uid，需要 root 切到 runwisp）
sudo runuser -u runwisp -- /usr/local/bin/runwisp \
  -c /etc/runwisp/runwisp.toml --data /var/lib/runwisp run ipage-visit

# 看运行记录
ls -lt /var/lib/runwisp/logs/ipage-visit/ | head
```

## 注意

- 免费主机的反爬规则可能变。如果哪天两个站点都失败，先手动 `curl -A "Mozilla/5.0"` 看返回的是不是挑战页，再检查 `aes.js` 的参数格式是否变化。
- `Googlebot` UA 只是兜底，正常路径是浏览器 UA + 解挑战；不建议把它当主路径。
- 脚本只请求首页，不登录、不提交表单、不碰后台。
