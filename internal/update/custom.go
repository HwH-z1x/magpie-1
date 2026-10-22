package update

import (
	"errors"
	"sync/atomic"
)

const CustomUpdateGuide = "https://github.com/HwH-z1x/magpie-1/blob/custom/request-intent/docs/custom-request-routing.zh-CN.md"

var ErrCustomUpdate = errors.New("official binary updates are disabled for this custom build; merge upstream source and rebuild: " + CustomUpdateGuide)

var customBuild atomic.Bool

// ProtectCustomBuild is called by this fork's executable before starting
// the CLI or GUI. The protection is independent of its version label.
func ProtectCustomBuild() { customBuild.Store(true) }

func CustomBuild() bool { return customBuild.Load() }
