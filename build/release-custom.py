"""Integrate, package and publish the Windows request-intent distribution."""

import argparse
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


REPO = "HwH-z1x/magpie-1"
BRANCH = "main"
CHANNEL = "request-update"
ROOT = f"https://github.com/{REPO}"
EXE = "magpie-windows-amd64.exe"
SHA = re.compile(r"[0-9a-f]{40}")
VERSION = re.compile(r"1\.0\.[1-9][0-9]*")


def run(*args, capture=True):
    result = subprocess.run(args, text=True, encoding="utf-8", capture_output=capture)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr if capture else result.returncode}")
    return result.stdout.strip() if capture else None


def api(endpoint, data=None, missing=False):
    args = ["gh", "api", endpoint]
    if data is not None:
        args += ["--input", "-"]
    result = subprocess.run(args, input=json.dumps(data) if data is not None else None,
                            text=True, encoding="utf-8", capture_output=True)
    if result.returncode:
        if missing and "HTTP 404" in result.stderr:
            return None
        raise RuntimeError(f"GitHub API {endpoint}: {result.stderr.strip()}")
    return json.loads(result.stdout)


def channel_head():
    ref = api(f"repos/{REPO}/git/ref/heads/{CHANNEL}", missing=True)
    return ref["object"]["sha"] if ref else None


def channel_file(name, head):
    if not head:
        return None
    item = api(f"repos/{REPO}/contents/{name}?ref={head}")
    return json.loads(base64.b64decode(item["content"]))


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def output(key, value):
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
        handle.write(f"{key}={value}\n")


def superseded(message):
    print(f"::notice title=Build superseded::{message}")
    output("published", "false")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"### Build superseded\n\n{message}\n\nNo update was published by this run.\n")


def prepare(state):
    # A runner may be queued past the caller's window check. Do not start
    # an automatic upstream query overnight, even after a scheduling delay.
    if os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch":
        if datetime.now(timezone(timedelta(hours=8))).hour < 8:
            output("build", "false")
            print("Automatic checks paused until 08:00 Asia/Shanghai")
            return
    if run("git", "status", "--porcelain"):
        raise RuntimeError("Checkout must be clean before integration")
    base = run("git", "rev-parse", "HEAD")
    current = api(f"repos/{REPO}/git/ref/heads/{BRANCH}")["object"]["sha"]
    if current != base:
        output("build", "false")
        superseded(f"Checkout {base} was replaced by {current}; the newer run will handle it.")
        return
    release = api("repos/yetone/magpie-releases/releases/latest")
    upstream = release["tag_name"]
    if release["draft"] or release["prerelease"] or not re.fullmatch(r"v\d+\.\d+\.\d+", upstream):
        raise RuntimeError("Upstream is not a stable release")
    run("git", "fetch", "https://github.com/yetone/magpie.git", f"refs/tags/{upstream}")
    upstream_sha = run("git", "rev-parse", "FETCH_HEAD^{commit}")
    head = channel_head()
    previous = channel_file("latest.json", head)
    if previous and previous.get("channel") != "request-intent":
        raise RuntimeError("Unknown existing update channel")
    # A published source may already contain an upstream version newer than
    # the release currently marked Latest; never merge an older release into it.
    if previous and previous["sourceCommit"] == base:
        if run("git", "merge-base", base, upstream_sha) == upstream_sha:
            output("build", "false")
            print("No unpublished source or upstream release")
            return
    if previous and not VERSION.fullmatch(previous["version"]):
        raise RuntimeError("Invalid previous fork version")
    serial = max(int(os.environ["GITHUB_RUN_NUMBER"]),
                 int(previous["version"].split(".")[-1]) + 1 if previous else 1)
    version = f"1.0.{serial}"
    tag = f"request-v{version}"
    if api(f"repos/{REPO}/git/ref/tags/{tag}", missing=True):
        raise RuntimeError(f"{tag} already exists; start a new workflow run, never overwrite it")
    run("git", "config", "user.name", "magpie-request-intent[bot]")
    run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    run("git", "config", "merge.fork-readme.driver", "true")
    # A conflict is intentionally fatal. The candidate and logs remain in
    # the failed run; the maintenance branch and current feed are untouched.
    run("git", "merge", "--no-edit", upstream_sha, capture=False)
    candidate = run("git", "rev-parse", "HEAD")
    if not SHA.fullmatch(candidate) or not SHA.fullmatch(upstream_sha):
        raise RuntimeError("Invalid source commit")
    state.parent.mkdir(parents=True, exist_ok=True)
    write_json(state, dict(base=base, sourceCommit=candidate, upstreamVersion=upstream,
                          upstreamCommit=upstream_sha, upstreamURL=release["html_url"],
                          version=version, tag=tag, channelHead=head))
    for key, value in [("build", "true"), ("version", version), ("source", candidate),
                       ("upstream", upstream), ("upstream_sha", upstream_sha)]:
        output(key, value)


def package(state, directory):
    info = json.loads(state.read_text(encoding="utf-8"))
    if run("git", "rev-parse", "HEAD") != info["sourceCommit"] or run("git", "status", "--porcelain"):
        raise RuntimeError("Source changed after integration")
    binary = directory / EXE
    with binary.open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    url = f'{ROOT}/releases/tag/{info["tag"]}'
    notes = (
        f'Upstream: [{info["upstreamVersion"]}]({info["upstreamURL"]}) '
        f'(`{info["upstreamCommit"]}`). Fork source: `{info["sourceCommit"]}`.\n\n'
        'Includes per-request intent classification within tool loops and fork-only restart updates. '
        'Experimental Windows x64 distribution; see the validation record. '
        'Full-suite, real-provider cross-model continuation and configuration rollback are not certified.\n\n'
        '<!-- lang:zh -->\n'
        f'基于上游 [{info["upstreamVersion"]}]({info["upstreamURL"]})，'
        f'上游提交 `{info["upstreamCommit"]}`，分支源码 `{info["sourceCommit"]}`。\n\n'
        '保留同轮工具循环内每请求意图判断，并只从本分支下载重启更新。'
        '这是 Windows x64 实验发行版；完整套件、真实供应商跨模型续接和配置回滚尚未完成认证。'
        f'请阅读[验证记录]({ROOT}/blob/{info["sourceCommit"]}/docs/custom-request-routing-validation.md)。'
    )
    manifest = dict(version=info["version"], channel="request-intent", notes=notes, url=url,
                    upstreamVersion=info["upstreamVersion"], upstreamCommit=info["upstreamCommit"],
                    sourceCommit=info["sourceCommit"], assets={EXE: dict(
                        url=f'{ROOT}/releases/download/{info["tag"]}/{EXE}',
                        size=binary.stat().st_size, sha256=digest)})
    write_json(directory / "latest.json", manifest)
    write_json(directory / "build.json", dict(info, checks=["Windows go vet ./...",
               "existing Go suite compilation", "existing internal/update suite",
               "existing update GUI and translation checks in Chromium and WebKit"],
               remainingChecks=["full Go suite", "gateway race suite", "real-provider continuation",
                                "native GUI restart and data rollback"]))
    (directory / "release-notes.md").write_text(notes + "\n", encoding="utf-8")
    (directory / "SHA256SUMS").write_text(f"{digest}  {EXE}\n", encoding="ascii")


def publish(state, directory):
    info = json.loads(state.read_text(encoding="utf-8"))
    manifest = json.loads((directory / "latest.json").read_text(encoding="utf-8"))
    if manifest["sourceCommit"] != run("git", "rev-parse", "HEAD") or run("git", "status", "--porcelain"):
        raise RuntimeError("Checked source changed before publication")
    current = api(f"repos/{REPO}/git/ref/heads/{BRANCH}")["object"]["sha"]
    if current != info["base"] or channel_head() != info["channelHead"]:
        superseded("Maintenance branch or update channel advanced during checks; the newer run will handle it.")
        return
    try:
        run("git", "push", "origin", f"HEAD:refs/heads/{BRANCH}", capture=False)
    except RuntimeError:
        current = api(f"repos/{REPO}/git/ref/heads/{BRANCH}")["object"]["sha"]
        if current != info["base"]:
            superseded("Maintenance branch advanced before the candidate push; the newer run will handle it.")
            return
        raise
    run("gh", "release", "create", info["tag"], "-R", REPO, "--target", info["sourceCommit"],
        "--draft", "--title", f'Magpie 每请求意图路由 {info["version"]}',
        "--notes-file", str(directory / "release-notes.md"), capture=False)
    assets = [EXE, "latest.json", "build.json", "SHA256SUMS"]
    run("gh", "release", "upload", info["tag"], "-R", REPO,
        *(str(directory / name) for name in assets), capture=False)
    # Read back the uploaded executable before making any client see it.
    with tempfile.TemporaryDirectory() as downloaded:
        run("gh", "release", "download", info["tag"], "-R", REPO, "--pattern", EXE,
            "--dir", downloaded, capture=False)
        with (Path(downloaded) / EXE).open("rb") as handle:
            digest = hashlib.file_digest(handle, "sha256").hexdigest()
        if digest != manifest["assets"][EXE]["sha256"]:
            raise RuntimeError("Uploaded executable checksum mismatch; feed not changed")
    current = api(f"repos/{REPO}/git/ref/heads/{BRANCH}")["object"]["sha"]
    if current != info["sourceCommit"] or channel_head() != info["channelHead"]:
        superseded("Source or update channel advanced during upload; the draft is kept for diagnosis.")
        return
    run("gh", "release", "edit", info["tag"], "-R", REPO,
        "--draft=false", "--prerelease=false", "--latest=true", capture=False)
    previous = channel_file("notes.json", info["channelHead"])
    notes = previous["releases"] if previous else []
    notes = [dict(version=info["version"], notes=manifest["notes"], url=manifest["url"])] + notes
    documents = {"latest.json": manifest, "notes.json": {"releases": notes[:40]}}
    elements = []
    for name, content in documents.items():
        blob = api(f"repos/{REPO}/git/blobs", dict(
            content=json.dumps(content, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"))
        elements.append(dict(path=name, mode="100644", type="blob", sha=blob["sha"]))
    tree_data = dict(tree=elements)
    if info["channelHead"]:
        parent = api(f'repos/{REPO}/git/commits/{info["channelHead"]}')
        tree_data["base_tree"] = parent["tree"]["sha"]
    tree = api(f"repos/{REPO}/git/trees", tree_data)
    commit = api(f"repos/{REPO}/git/commits", dict(
        message=f'Publish request-intent {info["version"]}', tree=tree["sha"],
        parents=[info["channelHead"]] if info["channelHead"] else []))
    # One commit switches latest.json and history together, after all assets
    # are public. A non-fast-forward ref update fails rather than losing a release.
    if info["channelHead"]:
        run("gh", "api", "--method", "PATCH", f"repos/{REPO}/git/refs/heads/{CHANNEL}",
            "-f", f'sha={commit["sha"]}', "-F", "force=false", capture=False)
    else:
        api(f"repos/{REPO}/git/refs", dict(ref=f"refs/heads/{CHANNEL}", sha=commit["sha"]))
    output("published", "true")
    print(f'Published {manifest["url"]}; channel commit {commit["sha"]}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "package", "publish"])
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--directory", type=Path, default=Path("dist"))
    args = parser.parse_args()
    if os.environ.get("GITHUB_REPOSITORY") != REPO:
        parser.error("This publisher only operates on the configured fork in GitHub Actions")
    if args.action == "prepare":
        prepare(args.state)
    elif args.action == "package":
        package(args.state, args.directory)
    else:
        publish(args.state, args.directory)


if __name__ == "__main__":
    main()
