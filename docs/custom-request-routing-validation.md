# Custom request routing: validation record

Date: 2026-10-22. Base: `8a99473ed90567da3a310c61440e8392dda41ba2`.

This is a development build, not a verified release. The user explicitly
prohibited writing any test code. No test source or fixtures were added or
edited; all executed tests were already in the repository.

## Passed

- Go 1.26.8 Windows/amd64 desktop build, with the official winres icon,
  version and DPI resources, CGO disabled.
- Windows `go vet ./...`; Linux `go vet -tags nogui ./...` and Linux
  `go build -tags nogui` cross-build.
- `gofmt -l` on the changed Go sources, `git diff --check`, Node syntax
  checks for the routing client and translations, and PowerShell parser
  validation for `build/update-custom.ps1`.
- The existing GUI behavior files `group-duplicate`, `group-share`,
  `group-editor-fits` and `routing-intent-fallback`: 52 passing cases on
  Chromium/WebKit, including their existing language and width variants.
- The existing `i18n-keys.test.cjs`: 3/3 after changing a new routing label
  to avoid colliding with core wording. The initial combined run was 54/55;
  its sole failure was that label, subsequently fixed and rechecked.
- The provider package's existing selected group/rule/classifier cases
  (`go test -tags nogui ./internal/provider` with the routing name filter).

## Failed or incomplete

The existing `go test -tags nogui ./...` did not pass. The agent package
reported failures including `TestAsideOfflineDisconnectRestoresWithoutDaemon`,
`TestClaudeDesktopCarriesTheLanguage`, `TestCodexSignInInKeychain`,
`TestCopilotFolderFromAnIDEPluginIsNotTheCLI`,
`TestQoderSettingsFromAnIDEPluginIsNotTheCLI`, and
`TestIsMagpieKeptWhileCatalogStays`, then hit its ten-minute timeout.
These failures involve native fixtures, filesystem expectations, sign-in
fixtures and allocation counts; their baseline status has not been proven.
They are not dismissed as harmless or attributed to the upstream without
verification. The stalled full-suite runner was stopped after recording
the failure.

A separate selected run over provider, CLI, GUI and gateway completed the
provider package, but did not produce completed results for the other
packages before the runner stalled and was stopped. Those packages are
not marked passing. Full logs are retained locally in `.git/existing-tests.log`
and `.git/final-routing-tests.log`.

Not run: the full GUI suite, race checks, a real Agent conversation with
multiple in-turn model changes, real supplier compatibility/cost checks,
or a deployment/rollback exercise. Existing checks do not specifically
prove the new request-mode guarantees. No account settings or running
production Magpie were changed.

The updater retains a `remainingChecks` gate. Do not deploy a candidate
until the required outstanding checks have been completed and recorded.
It does not automatically advance or push the source maintenance branch.

## Historical official-update protection follow-up

The fork now calls `update.ProtectCustomBuild` at executable startup. It
blocks the official desktop download/install/restart path, installation on
quit, the CLI installer, and low-level staging/install functions, regardless
of the version label. The desktop update row instead links to the custom
maintenance guide. Source updates remain the candidate updater's job.

For this follow-up, no test source was written or modified. Passed:

- Windows `go vet ./...` and production desktop build.
- The existing `internal/update` package tests (15.574s).
- Existing GUI files `i18n-keys`, `update-check`, `update-restart` and
  `update-hide`: 65/65, using their Chromium/WebKit and language variants.
- Node syntax, Go formatting, diff checks and local Markdown-link checks.
- A manual check of a separate portable executable deliberately labeled
  `999.0.0`: `update check` returned the custom guide with exit 0;
  `update` refused official installation with exit 1. Its configured feed
  pointed at an unavailable loopback endpoint, so neither command depended
  on a live official feed. No real account data or running app was used.

The preceding failed/incomplete full-suite record remains applicable; this
follow-up does not claim a green full suite or completed real-agent routing
and deployment/rollback validation.

## Fork release channel follow-up (2026-10-22)

The previous blanket binary-update block is superseded for published Windows
x64 GUI builds: they now use the fork-only channel. Developer builds and
unsupported platforms keep the manual-guide state. Source and release metadata,
exact fork URLs, trusted-feed checksums and a process-local staged-file recheck
protect installation; no official-feed fallback is enabled. The publisher and
workflow are production maintenance code, not new test code. No test source or
fixtures were added or modified.

Passed on the modified working tree:

- Windows `go vet ./...`, existing `internal/update` suite (15.659s), and
  production desktop build with Windows resources.
- Compilation of every existing Go package/suite with `go test -run '^$'
  -timeout 5m ./...` under an isolated HOME. This executes no test cases and is
  not a full-suite pass.
- Linux `go vet -tags nogui ./...` and nogui cross-build.
- Existing updater GUI and translation files: 65/65 on Chromium/WebKit with
  their existing language/width variants (97.8s).
- Official actionlint v1.7.12 on both new workflows, Python publisher syntax,
  Node syntax, Go formatting, diff checks and local Markdown links.

The original full-suite failures/incomplete runs remain unresolved and are not
relabeled passing. The release workflow deliberately publishes an experimental
channel with the check scope and remaining work in each `build.json`, not a
stable release certified under upstream's separate all-platform release rules.
Not run locally: GitHub's end-to-end authenticated publication, a native desktop
restart into a downloaded fork binary, configuration migration/rollback,
gateway race checks or real-provider model switching. Remote workflow and first
release status must be verified in Actions; committing the workflow alone does
not activate a working update feed. The installed application and production
account/configuration have not been changed.

## Default-branch consolidation (2026-10-22)

The default `main` now contains the previously published request-intent source,
its fork README and release automation. This is a history-preserving merge of
`e8bdc0008170e124938abb3614a0fb092d843371` and the published source
`dad0ae7ed3164ba5e952202b99882f01cccccadc`, not an upstream-only landing branch.
The publisher, workflow checkout/call, manual helper and current guide links all
use `main`. `request-update` remains the JSON channel, so installed fork clients
keep their feed URL. The old branch is retained as a compatibility link.

Relative to the published source, no test source or fixtures were authored or
changed. Inherited official-only workflows are repository-gated; the fork's
existing release checks remain active. Windows vet/production build, the
existing updater suite (15.815s), Python/PowerShell syntax and local links passed.
Actionlint passed for the changed workflows with one inherited, now-disabled
UI-preview input warning excluded (`allow-unsafe-pr-checkout` on checkout@v4).
No new routing behavior is introduced by this consolidation; previous incomplete
full-suite, native update/data rollback and real-provider evidence is unchanged.
