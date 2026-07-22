package symlink

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

type ReconcileResult struct {
	Repaired bool
	Source   string
	Target   string
	Msg      string
}

func Reconcile(step manifest.Step, dotfilesDir string, vars map[string]string, expand func(string) string) ReconcileResult {
	if step.Type != "symlink" && step.Type != "template-symlink" {
		return ReconcileResult{Msg: "not a symlink step"}
	}

	expectedSrc := filepath.Join(dotfilesDir, step.From)
	if step.Type == "template-symlink" {
		expectedSrc = strings.Replace(expectedSrc, filepath.Ext(expectedSrc), ".rendered"+filepath.Ext(expectedSrc), 1)
	}
	dst := expand(step.To)

	linkTarget, err := os.Readlink(dst)
	if err != nil {
		if _, lstatErr := os.Lstat(dst); lstatErr == nil {
			return ReconcileResult{
				Repaired: false,
				Target:   dst,
				Msg:      dst + " exists but is not a symlink",
			}
		}
		if _, linkErr := LinkWithResult(expectedSrc, dst, dotfilesDir); linkErr != nil {
			return ReconcileResult{
				Repaired: false,
				Source:   expectedSrc,
				Target:   dst,
				Msg:      linkErr.Error(),
			}
		}
		return ReconcileResult{
			Repaired: true,
			Source:   expectedSrc,
			Target:   dst,
			Msg:      "created",
		}
	}

	if linkTarget == expectedSrc {
		return ReconcileResult{
			Repaired: false,
			Source:   expectedSrc,
			Target:   dst,
			Msg:      "already correct",
		}
	}

	linkResult, linkErr := LinkWithResult(expectedSrc, dst, dotfilesDir)
	if linkErr != nil {
		return ReconcileResult{
			Repaired: false,
			Source:   expectedSrc,
			Target:   dst,
			Msg:      linkErr.Error(),
		}
	}
	action := "repaired"
	if linkResult.SnapshotEntry != nil && linkResult.SnapshotEntry.Action != "" {
		action = linkResult.SnapshotEntry.Action
	}
	return ReconcileResult{
		Repaired: true,
		Source:   expectedSrc,
		Target:   dst,
		Msg:      action + ": was -> " + linkTarget,
	}
}
