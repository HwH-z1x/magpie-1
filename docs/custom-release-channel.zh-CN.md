# 分支发行与重启更新

## 更新的是什么

客户端始终下载“上游正式版源码 + 本分支修改”编译后的完整程序，不下载官方 exe 再补丁。当前只发布 Windows x64 桌面版，渠道为 `request-intent`，属于实验发行；不声称完整套件、真实供应商跨模型续接或数据回滚已经认证。检查范围和未验项目随每个 Release 的 `build.json` 一起公开。

Windows x64 实验发行版已发布，首个可用版本为 `1.0.2`。请先检查 [Actions](https://github.com/HwH-z1x/magpie-1/actions/workflows/custom-release.yml) 和 [分支 Releases](https://github.com/HwH-z1x/magpie-1/releases?q=request-v&expanded=true)，不要安装原版来代替缺失的分支包。

## 用户操作

1. 从带 `request-v` 前缀的分支 Release 下载 `magpie-windows-amd64.exe`，核对同页 `SHA256SUMS`，退出原版并备份数据。
2. 将 exe 放在专属目录，可以改名为 `magpie-custom.exe`。如需独立配置，在旁边创建 `.portable`；这不会自动迁移原账号。
3. 第一次从原版、旧受保护开发版切换需手动替换。之后使用原有“检查 / 下载 / 重启更新”按钮即可，不需要 Git 或 Go。
4. 版本行的悬停提示显示分支渠道、上游版本和源码提交；发行说明也记录它们。不要把分支 `1.0.N` 当成上游的版本号。

保留既有自动检查频率、仅通知/自动下载、网关忙时等待等设置。不同名的本地 exe 仍按本机 GUI 平台对应的资产名更新。开发构建（如 `custom-<sha>`）、元数据不完整的构建和其他平台继续显示手动维护说明。

## 分支布局

- `main`：默认分支，也是唯一维护和发行主线，直接展示每请求意图路由功能。
- `request-update`：仅存放客户端在线更新的 JSON 清单，不是另一套程序源码。
- `custom/request-intent`：旧链接兼容入口，迁移时指向同一修改版；不再由自动发布脚本推进。新 clone、贡献和更新都使用 `main`。
- 原版代码从 `upstream` 远程或 `yetone/magpie` 的正式标签读取，原版项目介绍仅以折叠超链接保留。

## GitHub 维护流程

入口为 `.github/workflows/custom-release.yml`：北京时间每天 **08:00–23:00 每小时整点**检查一次，00:00–08:00 不自动检查。维护分支有新提交也会触发，但同样遵守夜间静默；手动运行不受此限制。GitHub 可能延迟调度，入口和实际查询前都会复核时段。已开始的构建不因跨过午夜而强制中断。默认 `main` 同时承载修改版源码、首页 README、调度入口和可复用构建流水线。更新脚本只推进 `main`；不再把一个原版镜像作为仓库首页。

仓库须启用 Actions，允许本仓库工作流请求 `contents: write`。只使用内置 `GITHUB_TOKEN`，不需要个人 PAT、官方签名密钥或租用服务器。GitHub 对 fork、可复用工作流和第三方 Actions 的仓库/组织限制仍适用。定时任务只由默认分支触发；长时间无仓库活动时也可能被 GitHub 停用，可从 Actions 重新启用。

流水线按下列顺序执行：

1. 读取 `yetone/magpie-releases` 当前标记的正式 Latest，固定 `yetone/magpie` 同名源码标签的提交。
2. 在 runner 的候选 checkout 合并它。仅两份 README 明确保留分支介绍；代码冲突不会自动偏向任一边，直接失败。
3. 运行 Go 格式检查、Windows vet、现有 Go suite 的编译检查、现有 update 套件，以及 Chromium/WebKit 上现有更新界面和翻译检查。不生成或修改任何测试代码。这不是完整套件通过的承诺。
4. 生成 Windows 资源、production exe 和来源元数据。分支版本为独立递增的 `1.0.N`，标签为 `request-v1.0.N`，不会触发原版的 `v*` 发布工作流。
5. 再确认维护分支和更新渠道没有被其他提交推进，快进维护分支并创建实验 Release，上传 exe、校验值、来源记录和该版更新清单。
6. 从 GitHub 回读 exe 验证 SHA256，才公开 Release；最后用一次 Git 提交同时推进 `request-update` 分支的 `latest.json` 与 `notes.json`。

继承自上游的官方发布、Docker、隐私模型、官方全平台 CI 和截图工作流在本 fork 中不执行；本 fork 的检查与发行由 `custom-release` 流水线负责。没有新增测试代码，也没有把仅选定检查通过改写为完整套件通过。

同一渠道串行发布。没有源码或上游变化时退出；不重建相同版本、不覆盖既有标签或安装包。已占用的失败版本需要启动一次新的工作流运行，不能重跑后覆盖资产。合并或检查失败时维护分支和渠道不变；发布后半段失败可能留下候选提交或草稿，但客户端仍用原渠道。诊断和候选产物保留为 Actions artifact。

首次运行和后续运行均以 Actions 的实际结果为准。GitHub 配额、runner、网络、上游冲突或现有检查失败都会阻止更新；“最新”指最新成功集成并发布的上游版本，不保证与官方同步上线。

## 客户端信任边界

- 更新清单固定为 `https://raw.githubusercontent.com/HwH-z1x/magpie-1/request-update/latest.json`，历史说明为同分支 `notes.json`。不依赖 GitHub Pages，也不把 Releases API 当成 Magpie 清单。
- 官方或环境变量覆盖的更新源不被使用。清单必须带 `request-intent` 标记、合法发行版本和源码提交，下载地址必须精确指向本仓库对应 `request-v` Release 的唯一 Windows x64 资产。
- 校验值的权威清单直接从 GitHub HTTPS 获取，不经不可信镜像回退。exe 下载仍可使用已有下载镜像，但必须匹配清单哈希；安装前再与当前进程记录的可信哈希核对。旧官方 `.new` 不能直接安装，管理员替换也一样。
- 信任依赖本仓库权限和 GitHub HTTPS，不是独立签名体系。请保护 GitHub 账号；Windows 安装包目前没有承诺 Authenticode 签名。SHA256 不能抵御仓库/发布账号被攻陷。

## 故障处理和回退

合并冲突需维护者在源码分支解决并提交，下一次运行重新检查。不要只同步官方 exe。遇到下载或校验错误保留当前程序，修复网络或渠道后重试。

更新器复用上游的文件替换和新二进制启动检查；启动被 Windows 安全策略阻止时，原有恢复机制仍适用。但**这不是配置数据库事务或数据迁移回滚**。升级前保留数据备份；需要降级时退出程序，手动下载旧 `request-v` 资产，按必要情况恢复配套数据。自动版本比较不会推送较低版本；旧包、较新数据和备份不要混着覆盖。

外部安装器、另一份官方程序和错误的快捷方式不在当前进程的保护范围内。实际安装和原生 GUI 重启尚需在隔离便携目录确认，不能把已有 GUI fixture 检查当成真实升级演练。
