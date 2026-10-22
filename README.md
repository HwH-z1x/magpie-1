# Magpie 每请求意图路由版

**同一轮对话中，每个模型请求都重新运行意图判断，包括工具结果续接请求。**

[下载 Windows 修改版](https://github.com/HwH-z1x/magpie-1/releases?q=request-v&expanded=true) · [构建状态](https://github.com/HwH-z1x/magpie-1/actions/workflows/custom-release.yml) · [操作与更新说明](docs/custom-request-routing.zh-CN.md) · [在线更新机制](docs/custom-release-channel.zh-CN.md) · [验证状态](docs/custom-request-routing-validation.md) · [English](README.en.md) · [上游 Magpie](https://github.com/yetone/magpie)

这是一个非官方 Magpie 修改版，面向使用 Codex、Claude Code、OpenCode 等多步工具调用 Agent 的用户。原版 Magpie 只在每轮对话开始时做一次意图判断，整轮后续的工具调用都会锁在轮初选定的模型上。本分支在路由组中新增**“按轮 / 每请求”**判断频率开关，直接复用原有的路由组、分类模型、规则顺序、子组嵌套、故障转移和路由页实时动画，无需额外编写路由插件，也不必把任务拆成子代理。

## 为什么关闭“会话保持”还不够？

用户发出一条消息后，Agent 往往会在同一轮里连续发起几十次请求：读文件、改代码、运行命令、根据报错继续排查。

原版 Magpie 在一轮开始时运行一次意图分类，同一轮后续的工具结果请求全部复用轮初的规则决定。路由组里的“会话保持”只控制同一模型下的**账号 / Key 亲和性**（用于保留提示词缓存）；把会话保持设为“关闭”只会重新挑选账号，**不会重新调用意图分类器，也不会切换到其他意图规则对应的模型**。

开启本分支的“每请求”模式后，网关会在每次生成请求到达时，结合**用户原始任务与最近的工具调用、输出和报错状态**，重新判断下一步要做什么并匹配规则。同一轮里的读文件、改代码和分析报错因此可以分别命中不同模型。具体选模结果取决于规则配置与分类模型能力；重新判断后如果仍匹配原规则，也会继续留在原模型。

| 行为 | 按轮（默认） | 每请求（手动开启） |
| --- | --- | --- |
| 用户发出新消息 | 运行意图分类 | 运行意图分类 |
| 同轮返回工具结果继续执行 | 沿用本轮开始时的决定 | 根据最新执行状态重新分类 |
| 相同分类输入 | 复用 10 分钟分类缓存并合并并发请求 | 每次请求独立分类，不跨请求复用缓存 |
| 分类器调用失败 | 进入分类冷却期 | 下一请求继续尝试分类，供应商自身限流仍生效 |
| 规则顺序、子组嵌套、故障转移 | 原有语义 | 原有语义；每个子组可单独设置判断频率 |

## 相比设置“子代理（Subagent）”有哪些优势？

原版文档提到“子代理的轮次单独决定，依据它自己的消息”。但设置子代理并不能替代同轮每请求路由，两者的作用机制完全不同：

| 对比维度 | 靠 Agent 子代理（Subagent）分流 | 本分支“每请求意图路由” |
| --- | --- | --- |
| **主代理能否中途换模** | **不能**。原版通过会话首条用户消息（`firstWords`）区分主代理与子代理：主代理整轮仍锁在轮初模型上，且子代理自身内部的工具循环也锁在该子代理轮初模型上 | **能**。无论是主代理还是子代理，同一轮工具循环里的每一次生成请求都能按当前步骤重新选模 |
| **触发条件** | **依赖主代理主动派发**。只有主代理决定发起子代理调用时才会触发新路由；日常直接读写文件、跑命令、修报错通常在主代理循环内完成，一旦轮初落在弱模型上就会一直用弱模型硬解 | **由真实执行结果自动驱动**。网关自动提取原始任务及最近最多 12 条工具调用、返回文本与 `error` 报错标记，每次请求前自动判断下一步该用什么模型 |
| **上下文连续性** | **多段会话割裂**。每次派发子代理都要新建独立会话，由主代理整理背景传参、子代理跑完再摘要返回，容易丢失细节并产生额外的包装请求开销 | **单会话无缝连续**。始终在同一段完整对话上下文里推进，只在网关转发层切换模型，无需拆解任务或来回汇总 |
| **配置与维护成本** | 依赖具体 Agent 支持子代理机制，需为不同角色编写和维护子代理说明或提示词 | **网关层透明生效**。在 Magpie 路由组里开启“每请求”即可，所有接入网关的 Agent 直接共用同一套规则与故障转移 |
| **路由页可视化** | 主代理与子代理拆成多条独立会话记录 | 同一轮对话的每次分类结果、耗时、命中规则和模型切换轨迹都在路由页实时展示 |

**取舍说明**：子代理拥有隔离的独立上下文窗口，适合需要避免大量中间输出撑满主会话的独立支线任务；本分支则在同一上下文内按请求切模，每次请求会多一次轻量分类调用，中途跨模型切换也可能减少提示词缓存命中，或遇到部分供应商对历史消息与推理签名的兼容性限制。两者互不冲突，可以同时使用。

## 如何开启

1. 从 [Releases](https://github.com/HwH-z1x/magpie-1/releases?q=request-v&expanded=true) 下载最新的 `magpie-windows-amd64.exe`（或按下方步骤从源码构建），先退出正在运行的原版 Magpie，再启动本分支程序。
2. 在**路由（Routing）**页面编辑目标路由组，将**规则判断频率**设为**每请求**。
3. 选择分类模型并添加意图规则，把不带意图的通用兜底规则放在意图规则后面。
4. 在 **Agent** 页面让目标 Agent 使用该路由组。如果组内嵌套了子组，且希望子组也按每请求判断，请对子组分别开启。

也可以通过命令行开启或恢复：

```powershell
.\dist\magpie-custom.exe group set <组ID> rule-scope=request
# 恢复该组的默认按轮行为：
.\dist\magpie-custom.exe group set <组ID> rule-scope=turn
```

**边界说明**：“请求”指新到达的模型生成请求，不包括流式输出的单个分片，也不包括单次请求内部的供应商重试。分类器自身的请求不会递归触发分类；手动路由保留手选模型。同一路由组不能同时开启“严格会话保持”和“每请求”规则判断；普通会话保持仍可用于组内同一模型的账号选择。

## 点击“重启更新”会丢掉修改吗？

不会。Windows x64 发行版保留了 Magpie 原有的“检查更新 → 下载 → 重启更新”流程，但更新源固定指向本仓库的专属渠道（`request-update` 分支与 `request-v*` 发行包），**绝不回退到官方原版二进制**。

- **自动同步上游**：GitHub Actions 在**北京时间每天 08:00–23:00 每小时整点**自动检查上游正式版（00:00–08:00 不检查）。发现上游新版本或本分支新提交时，流水线会自动合并上游正式版源码、运行检查、编译带每请求路由功能的 exe，并在回读校验 SHA256 后更新发布清单。若合并冲突或检查失败则停止发布，现有可用版本保持不变。
- **首次切换**：从原版或本地 `custom-<sha>` 开发构建切换过来时，需先手动下载安装一次[分支发行版](https://github.com/HwH-z1x/magpie-1/releases?q=request-v&expanded=true)；安装后即可直接在软件内点击“重启更新”，无需在本机安装 Git 或 Go。详细机制见[分支发行与重启更新说明](docs/custom-release-channel.zh-CN.md)。
- **目录与备份建议**：建议将程序放在独立目录，并在 exe 旁新建 `.portable` 文件隔离配置。首次切换前请退出官方版并备份数据，确认快捷方式和开机启动项指向本分支程序。二进制启动恢复不等于配置数据回滚，升级前请保留备份。离线源码维护仍可使用 [PowerShell 助手](build/update-custom.ps1)。

## Windows 源码构建

如需自行编译，请先安装 Git 和 `go.mod` 要求的 Go 版本（当前为 1.26.8），再执行：

```powershell
git clone --single-branch --branch main https://github.com/HwH-z1x/magpie-1.git
cd magpie-1
git remote add upstream https://github.com/yetone/magpie.git
$env:CGO_ENABLED = '0'
go run github.com/tc-hib/go-winres@v0.3.3 make --in build/windows/winres.json --arch amd64,arm64 --out rsrc --file-version 0.0.0 --product-version 0.0.0
if ($LASTEXITCODE -ne 0) { throw '资源生成失败' }
go build -tags production -trimpath -ldflags '-s -w -H windowsgui -X main.version=custom-request-intent-dev' -o dist/magpie-custom.exe .
if ($LASTEXITCODE -ne 0) { throw '构建失败' }
```

以上命令会在 `dist/magpie-custom.exe` 生成手动开发构建。预编译的 Windows x64 实验发行版通过[分支专属更新渠道](docs/custom-release-channel.zh-CN.md)发布。**注意：从官方站点、官方安装脚本或 `go install github.com/yetone/magpie@latest` 安装的是原版程序，不包含本分支功能。**

## 当前状态与代价

本仓库为**开发分支**。目前已通过 Windows 桌面版构建、跨平台静态与编译检查，以及部分既有 GUI 与更新器检查；上游完整 Go 测试套件仍有失败或未完成项，真实 Agent 跨模型续接和部署回滚尚未完成实测认证。详细范围以[验证记录](docs/custom-request-routing-validation.md)为准。

每次请求重新分类会增加一次分类延迟和 token 消耗；中途切换模型可能降低提示词缓存命中率，也可能遇到部分供应商对历史消息、推理签名或会话格式的兼容性限制。分类输入受长度预算控制，超出时会截断中间内容；分类失败时可回退到最近一次有效意图，原有账号限流与冷却规则继续生效。模型列表、健康检查等非生成接口不触发分类。

## 原版项目说明

本项目基于 [yetone/magpie](https://github.com/yetone/magpie) 修改，保留原作者署名及 [MIT 许可证](LICENSE)。

<details>
<summary>查看原版项目说明</summary>

原版项目说明如下：[Magpie 原版中文 README](https://github.com/yetone/magpie/blob/main/README.zh-CN.md) · [Original English README](https://github.com/yetone/magpie/blob/main/README.md)。其中的下载链接安装的是原版程序，不包含本分支功能。

</details>
