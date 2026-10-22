# Magpie Request Intent Routing / 每请求意图路由

**Reclassify every model request, including tool-result continuations within the same agent turn.**

[简体中文](README.zh-CN.md) · [Custom branch](https://github.com/HwH-z1x/magpie-1/tree/custom/request-intent) · [Build and update guide](docs/custom-request-routing.zh-CN.md) · [Validation status](docs/custom-request-routing-validation.md) · [Upstream Magpie](https://github.com/yetone/magpie)

This unofficial fork adds **per-request intent routing** to Magpie. It is for Codex, Claude Code and other agents whose work should move between models during one tool loop, without waiting for another user message. It retains routing groups, classifier backends, rule priority and failover; no separate routing plugin is required.

中文：同一轮对话中的工具调用与工具结果请求，也重新运行意图判断并选择模型；关闭“会话保持”本身不能实现这个效果。

## Why session affinity off is not enough

One user message can lead to many model requests: inspect files, change code, run a command, interpret the result, then continue. In the upstream revision this fork is based on, intent is classified when the user's turn begins; subsequent requests reuse that decision. Turning off account/key affinity does not change that turn-level rule decision.

This fork can classify the **next step** from the task and recent execution state on each incoming generation request. Inspecting a bug, writing a fix and interpreting a failed command can therefore select different models within the same turn. That depends on the rules and classifier; it is not a guarantee that every selection is correct.

| Behavior | Per turn (default) | Per request (opt-in) |
| --- | --- | --- |
| New user message | Existing classification behavior | Fresh classification attempt |
| Same-turn tool results | Reuse the turn decision | Fresh classification attempt |
| Same classification input | Existing cache and concurrent sharing | No cross-request result cache or sharing |
| Classifier failure | Existing classification cooldown | Next request tries again; provider limits still apply |
| Rule order, nested groups, failover | Existing semantics | Existing semantics; child groups set their own scope |

## Enable per-request classification

1. Build this branch, quit upstream Magpie and launch the custom executable.
2. Edit a group in **Routing** and select **Rule evaluation → Per-request decision**.
3. Choose a classifier and add intent rules. Put generic fallback rules after intent rules.
4. Configure your agent to use the group. Enable request scope separately on participating child groups.

```powershell
.\dist\magpie-custom.exe group set <group-id> rule-scope=request
# Restore the group's default turn-based behavior:
.\dist\magpie-custom.exe group set <group-id> rule-scope=turn
```

A request is a new incoming model-generation call, not a stream chunk or each internal provider retry. Classifier calls do not recursively classify themselves. Manual routing keeps its pick; strict session affinity is incompatible with request scope on the same group. Reclassification can select the same model again. The Routing page continues to show the gateway's real decisions.

## Build this fork on Windows

Install Git and the Go version required by `go.mod` (currently 1.26.8):

```powershell
git clone --single-branch --branch custom/request-intent https://github.com/HwH-z1x/magpie-1.git
cd magpie-1
git remote add upstream https://github.com/yetone/magpie.git
$env:CGO_ENABLED = '0'
go run github.com/tc-hib/go-winres@v0.3.3 make --in build/windows/winres.json --arch amd64,arm64 --out rsrc --file-version 0.0.0 --product-version 0.0.0
if ($LASTEXITCODE -ne 0) { throw 'Resource generation failed' }
go build -tags production -trimpath -ldflags '-s -w -H windowsgui -X main.version=custom-request-intent-dev' -o dist/magpie-custom.exe .
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
```

The output is a manual development build at `dist/magpie-custom.exe`. Published Windows x64 builds use the [fork release channel](docs/custom-release-channel.zh-CN.md). The channel is experimental, not a claim of full-suite or real-provider certification. **Official downloads, the upstream installer and `go install github.com/yetone/magpie@latest` install upstream Magpie without these changes.**

## Updates that preserve the fork

Published Windows x64 builds keep Magpie's download-and-restart workflow, but accept only this fork's update feed and release assets. They never fall back to official binaries. The release pipeline integrates upstream stable source, runs existing checks, builds and verifies the uploaded executable, then advances the feed. Merge/check failures leave the current channel unchanged.

[Download fork releases](https://github.com/HwH-z1x/magpie-1/releases?q=request-v&expanded=true) · [Pipeline and recovery guide](docs/custom-release-channel.zh-CN.md)

The first migration from an official or old protected development build is manual. After installing a published fork build, later updates need no local Git or Go. Developer builds (`custom-<sha>`) and unsupported platforms still show the manual guide. A channel becomes usable only after its first successful publication; source/workflow files alone are not a published update.

Use a dedicated runtime directory, ideally with a `.portable` marker and its own `data`. Quit any official copy first, back up data and check shortcuts/login items. Binary startup recovery does not roll back data migrations. For manual source maintenance, the [PowerShell helper](build/update-custom.ps1) remains available with its own deployment gates.

## Status and tradeoffs

This is a **development fork**. Windows desktop builds, cross-platform build/static checks and selected existing GUI checks have passed; the existing Go suite has failures/incomplete runs, and real-agent cross-model use and deployment rollback remain unverified. See the [validation record](docs/custom-request-routing-validation.md).

Classification adds latency and usage. Model changes can reduce prompt-cache hits or run into provider-specific history/reasoning constraints. Input is bounded and may be shortened; failure can fall back to the last valid intent. Existing account restrictions still apply. Non-generation endpoints such as model listing and health checks are outside this mode.

## Upstream Magpie documentation

Based on [yetone/magpie](https://github.com/yetone/magpie), with its authorship and [MIT license](LICENSE) retained.

<details>
<summary>Original Magpie project introduction</summary>

[Read the original project README](https://github.com/yetone/magpie/blob/main/README.md). Its downloads install upstream Magpie, not this fork.

</details>
