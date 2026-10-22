package update

import (
	"encoding/hex"
	"errors"
	"fmt"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
)

const CustomUpdateGuide = "https://github.com/HwH-z1x/magpie-1/blob/custom/request-intent/docs/custom-request-routing.zh-CN.md"
const CustomRepository = "https://github.com/HwH-z1x/magpie-1"
const customFeedRoot = "https://raw.githubusercontent.com/HwH-z1x/magpie-1/request-update/"
const customChannel = "request-intent"

var ErrCustomUpdate = errors.New("only verified request-intent fork updates are allowed; see " + CustomUpdateGuide)

var customBuild atomic.Bool
var customStaged sync.Map // absolute download path -> checksum from the fork feed
var customVersion = regexp.MustCompile(`^1\.0\.[1-9][0-9]*$`)
var commitSHA = regexp.MustCompile(`^[0-9a-f]{40}$`)

// These identify the source of published builds, independently of their
// monotonically increasing fork version. The release workflow sets them.
var UpstreamVersion, UpstreamCommit, SourceCommit string

// ProtectCustomBuild is called by this fork's executable before starting
// the CLI or GUI. The protection is independent of its version label.
func ProtectCustomBuild() { customBuild.Store(true) }

func CustomBuild() bool { return customBuild.Load() }

// CustomUpdates leaves unsupported platforms and developer builds on the
// manual guide. Merely giving a binary a release-looking version is not enough.
func CustomUpdates(version string) bool {
	return CustomBuild() && runtime.GOOS == "windows" && runtime.GOARCH == "amd64" && GUI &&
		customVersion.MatchString(version) && commitSHA.MatchString(SourceCommit) &&
		commitSHA.MatchString(UpstreamCommit) && strings.HasPrefix(UpstreamVersion, "v")
}

func checkCustomRelease(rel *Release) error {
	if !CustomBuild() {
		return nil
	}
	if runtime.GOOS != "windows" || runtime.GOARCH != "amd64" || !GUI ||
		rel == nil || rel.Channel != customChannel || !customVersion.MatchString(rel.Version) ||
		!commitSHA.MatchString(rel.SourceCommit) || !commitSHA.MatchString(rel.UpstreamCommit) ||
		!strings.HasPrefix(rel.UpstreamVersion, "v") {
		return ErrCustomUpdate
	}
	tag := "request-v" + rel.Version
	if rel.URL != CustomRepository+"/releases/tag/"+tag {
		return ErrCustomUpdate
	}
	if len(rel.Assets) != 1 {
		return ErrCustomUpdate
	}
	a, ok := rel.Assets["magpie-windows-amd64.exe"]
	hash, err := hex.DecodeString(a.SHA256)
	if !ok || err != nil || len(hash) != 32 || a.Size <= 0 ||
		a.URL != CustomRepository+"/releases/download/"+tag+"/magpie-windows-amd64.exe" {
		return ErrCustomUpdate
	}
	return nil
}

func rememberCustomStage(path, hash string) {
	if CustomBuild() {
		customStaged.Store(filepath.Clean(path), strings.ToLower(hash))
	}
}

// A .new left by an official build (or a file changed after download) must
// not enter any replacement path, including installation with elevation.
func checkCustomStage(path string) error {
	if !CustomBuild() {
		return nil
	}
	want, ok := customStaged.Load(filepath.Clean(path))
	if !ok || fileHash(path) != want {
		return fmt.Errorf("%w: unverified staged binary", ErrCustomUpdate)
	}
	return nil
}
