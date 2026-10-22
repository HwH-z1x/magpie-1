# Magpie Request Intent Routing Edition

**Reclassify every model request—including tool calls and tool-result continuations—within the same agent turn.**

[简体中文](README.md) · [Download Windows builds](https://github.com/HwH-z1x/magpie-1/releases?q=request-v&expanded=true) · [Build status](https://github.com/HwH-z1x/magpie-1/actions/workflows/custom-release.yml) · [Operation guide (ZH)](docs/custom-request-routing.zh-CN.md) · [Release channel guide (ZH)](docs/custom-release-channel.zh-CN.md) · [Validation record](docs/custom-request-routing-validation.md) · [Upstream Magpie](https://github.com/yetone/magpie)

This unofficial Magpie fork adds **per-request intent routing** for multi-step coding agents such as Codex, Claude Code, and OpenCode. Upstream Magpie classifies intent once at the start of a user turn and keeps subsequent tool requests on that initial decision. This fork adds a **Per turn / Per request** rule-evaluation switch to routing groups while preserving existing classifiers, rule priority, nested groups, failover, and live routing traces—without external plugins or splitting work into subagents.

## Why turning off session affinity or using subagents is not enough

### 1. Session affinity off does not re-run intent classification

A single user prompt can trigger dozens of model requests: reading files, editing code, running commands, and analyzing errors. Upstream Magpie evaluates intent rules only when a new turn begins; turning off session affinity only changes account/key stickiness and never re-invokes the intent classifier mid-turn.

With **Per-request decision** enabled on a routing group, the gateway evaluates the user's original task together with recent tool calls, outputs, and error flags on every incoming generation request. File inspection, code edits, and failure diagnosis within the same turn can therefore route to different models according to your rules.

| Behavior | Per turn (default) | Per request (opt-in) |
| --- | --- | --- |
| New user message | Existing classification behavior | Fresh classification attempt |
| Same-turn tool results | Reuse the turn decision | Reclassify from latest execution state |
| Same classification input | 10-minute cache and concurrent sharing | Independent per-request classification |
| Classifier failure | Classification cooldown | Next request tries again; provider limits still apply |
| Rule order, nested groups, failover | Existing semantics | Existing semantics; child groups configure scope independently |

### 2. Advantages over subagent routing

Upstream Magpie routes a subagent turn separately based on the subagent's own initial prompt (`firstWords`). Per-request routing solves a different problem:

| Dimension | Subagent routing | Per-request intent routing (this fork) |
| --- | --- | --- |
| **Main agent mid-turn switching** | **No.** Both the main agent and each subagent stay locked to their turn-start model across their own tool loops | **Yes.** Every generation request in the main agent's (or subagent's) tool loop can switch models mid-turn |
| **Trigger mechanism** | **Requires explicit delegation.** Only triggers when the main agent decides to spawn a subagent; ordinary read/edit/test loops stay on the initial model | **Driven by real execution state.** Automatically inspects the task plus up to 12 recent tool calls, results, and `error` flags before each request |
| **Context continuity** | **Split across sessions.** Spawning subagents creates separate contexts and requires summarizing state back and forth | **Single continuous conversation.** Switches models transparently at the gateway layer within one shared conversation history |
| **Setup overhead** | Requires agent-specific subagent support and custom subagent prompts | **Gateway-level switch.** Enable once on a Magpie routing group for any connected agent |

**Tradeoffs:** Subagents isolate verbose intermediate output in a separate context window, whereas per-request routing switches models within the same context. Per-request classification adds one lightweight classifier call per request, and mid-turn model switches can reduce prompt-cache hits or encounter provider-specific history/reasoning constraints. Both approaches can be used together.

## Enable per-request classification

1. Download the latest `magpie-windows-amd64.exe` from [Releases](https://github.com/HwH-z1x/magpie-1/releases?q=request-v&expanded=true) (or build from source), quit upstream Magpie, and launch this fork.
2. In **Routing**, edit your target group and set **Rule evaluation → Per-request decision**.
3. Select a classifier model and configure intent rules, placing generic fallback rules after intent rules.
4. Point your agent to the routing group. Enable per-request evaluation separately on any nested child groups that should also reclassify on each request.

```powershell
.\dist\magpie-custom.exe group set <group-id> rule-scope=request
# Restore the group's default turn-based behavior:
.\dist\magpie-custom.exe group set <group-id> rule-scope=turn
```

## Fork-only restart updates

Published Windows x64 builds preserve Magpie's download-and-restart update button while pinning the update feed to this repository (`request-update` branch and `request-v*` releases). They never fall back to official binaries. GitHub Actions checks upstream stable releases hourly at `:00` between 08:00 and 23:00 Asia/Shanghai (paused 00:00–08:00). See the [release channel guide](docs/custom-release-channel.zh-CN.md).

## Build from source on Windows

Install Git and the Go version required by `go.mod` (currently 1.26.8):

```powershell
git clone --single-branch --branch main https://github.com/HwH-z1x/magpie-1.git
cd magpie-1
git remote add upstream https://github.com/yetone/magpie.git
$env:CGO_ENABLED = '0'
go run github.com/tc-hib/go-winres@v0.3.3 make --in build/windows/winres.json --arch amd64,arm64 --out rsrc --file-version 0.0.0 --product-version 0.0.0
if ($LASTEXITCODE -ne 0) { throw 'Resource generation failed' }
go build -tags production -trimpath -ldflags '-s -w -H windowsgui -X main.version=custom-request-intent-dev' -o dist/magpie-custom.exe .
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
```

## Status and tradeoffs

This is a **development fork**. See the [validation record](docs/custom-request-routing-validation.md) for passed checks and unverified areas.

## Upstream Magpie documentation

Based on [yetone/magpie](https://github.com/yetone/magpie), with its authorship and [MIT license](LICENSE) retained.

<details>
<summary>Original Magpie project introduction</summary>

[Read the original project README](https://github.com/yetone/magpie/blob/main/README.md). Its downloads install upstream Magpie, not this fork.

</details>
