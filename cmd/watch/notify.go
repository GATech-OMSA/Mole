//go:build darwin

package main

import (
	"context"
	"fmt"
	"os/exec"
	"time"
)

// notify sends a macOS notification via osascript.
func notify(title, message string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	script := fmt.Sprintf(`display notification %q with title %q`, message, title)
	return exec.CommandContext(ctx, "osascript", "-e", script).Run()
}
