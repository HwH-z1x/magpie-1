# Magpie 每请求意图路由：同轮工具调用动态选模

**同一轮对话中，每个模型请求都重新运行意图判断，包括工具结果续接请求，不必等用户再次发言。**

[English](README.md) · [定制分支](https://github.com/HwH-z1x/magpie-1/tree/custom/request-intent) · [操作与更新说明](docs/custom-request-routing.zh-CN.md) · [验证状态](docs/custom-request-routing-validation.md) · [上游 Magpie](https://github.com/yetone/magpie)

这是一个非官方 Magpie fork，面向使用 Codex、Claude Code 等 Agent，希望在一次任务的工具循环中按阶段选择模型的用户。沿用路由组、分类器接入、规则顺序和故障转移，增加“按轮 / 每请求”开关，无需额外编写路由插件。

## 为什么关闭“会话保持”还不够？

一条用户消息可能产生许多模型请求：读文件、改代码、执行命令、分析输出，再继续工作。在本分支所基于的上游版本中，意图判断发生在一轮开始时，后续请求复用本轮决定。“会话保持”控制账号/Key 的保持方式，关闭它并不会让这些后续请求重新分类。

本分支让目标组每次根据**用户任务和最新执行状态，判断接下来该做什么**。例如，同轮中的排查、修改和分析报错可以分别选中不同模型。这取决于规则和分类器能力，不保证每次都选对，也不要求每次都换模型。

| 行为 | 按轮（默认） | 每请求（手动开启） |
| --- | --- | --- |
| 用户发出新消息 | 沿用原分类行为 | 新的分类尝试 |
| 同轮携带工具结果继续 | 沿用本轮决定 | 再次分类 |
| 相同分类输入 | 保留原缓存与并发合并 | 不跨请求复用结果或合并分类 |
| 分类器失败 | 保留原分类冷却 | 下一请求再次尝试，供应商限流仍生效 |
| 规则、子组和故障转移 | 原有语义 | 原有语义；每个子组单独设置频率 |

## 如何开启

1. 构建本分支，退出原版 Magpie，再启动定制 exe。
2. 在“路由”中编辑目标组，将“规则判断频率”设为“每请求”。
3. 选择分类模型并添加意图规则，把通用兜底规则放在意图规则后面。
4. 让 Agent 使用这个路由组。若子组也需要每请求判断，分别开启。

```powershell
.\dist\magpie-custom.exe group set <组ID> rule-scope=request
# 恢复该组的默认按轮行为：
.\dist\magpie-custom.exe group set <组ID> rule-scope=turn
```

“请求”指新到达的模型生成请求，不是流式输出的每个片段，也不是一次请求内部的每次供应商重试。分类器自身不递归分类；手动路由保留手选模型。同组不能同时启用严格会话保持和每请求规则。路由页继续显示核心网关的真实决策。

## Windows 构建

先安装 Git 和 `go.mod` 要求的 Go（当前为 1.26.8），再执行：

```powershell
git clone --single-branch --branch custom/request-intent https://github.com/HwH-z1x/magpie-1.git
cd magpie-1
git remote add upstream https://github.com/yetone/magpie.git
$env:CGO_ENABLED = '0'
go run github.com/tc-hib/go-winres@v0.3.3 make --in build/windows/winres.json --arch amd64,arm64 --out rsrc --file-version 0.0.0 --product-version 0.0.0
if ($LASTEXITCODE -ne 0) { throw '资源生成失败' }
go build -tags production -trimpath -ldflags '-s -w -H windowsgui -X main.version=custom-request-intent-dev' -o dist/magpie-custom.exe .
if ($LASTEXITCODE -ne 0) { throw '构建失败' }
```

输出为手动开发构建 `dist/magpie-custom.exe`。Windows x64 发行构建使用[分支专属更新渠道](docs/custom-release-channel.zh-CN.md)；这是实验渠道，不代表已通过完整套件或真实供应商验证。**官方站点、官方安装脚本和 `go install github.com/yetone/magpie@latest` 得到的是原版，不包含本分支的修改。**

## 点击“重启更新”会丢掉修改吗？

Windows x64 发行构建沿用“下载 → 重启更新”的交互，但只接受本 fork 的更新清单和安装包，**不会退回官方二进制渠道**。GitHub 流水线先合入上游正式版源码、执行现有检查、编译并回读校验上传的 exe，成功后才推进更新清单。合并冲突或检查失败时停止发布，现有渠道版本不变。

[下载分支发行版](https://github.com/HwH-z1x/magpie-1/releases?q=request-v&expanded=true) · [发布流水线、版本规则与恢复说明](docs/custom-release-channel.zh-CN.md)

从原版或旧的受保护开发版切换时，需要手动安装一次支持新渠道的分支发行版；之后更新不需要在用户电脑安装 Git 或 Go。`custom-<sha>` 开发构建及暂不支持的平台仍显示手动维护说明。**只有首次发布成功后渠道才可用，提交工作流不等于已经发布可下载版本。**

建议使用独立目录，并在 exe 旁放置 `.portable`。首次切换前退出官方版、备份数据，确认快捷方式和开机启动项指向分支程序。二进制启动失败恢复不等于数据迁移回滚；保留备份。手动源码维护仍可使用 [PowerShell 助手](build/update-custom.ps1)，其部署验收门槛独立保留。

## 当前状态与代价

这是**开发分支**。Windows 桌面构建、跨平台静态/构建检查和部分现有 GUI 检查通过；现有 Go 全集存在失败或未完成项目，真实 Agent 跨模型续接和部署回滚尚未完成验证。具体以[验证记录](docs/custom-request-routing-validation.md)为准。

每次分类都会增加延迟和用量，切换模型可能损失提示词缓存，也可能遇到供应商对历史、推理签名或会话的兼容性限制。分类上下文有长度预算；失败时可回退到最近的有效意图，原有账号限制仍生效。模型列表、健康检查等非生成接口不在该模式范围内。

## 原版项目说明

本项目基于 [yetone/magpie](https://github.com/yetone/magpie)，保留原作者署名及 [MIT 许可证](LICENSE)。

<details>
<summary>查看原版项目说明</summary>

原版项目说明如下：[Magpie 原版中文 README](https://github.com/yetone/magpie/blob/main/README.zh-CN.md)。其中的下载链接安装的是原版，不包含本分支功能。

</details>
