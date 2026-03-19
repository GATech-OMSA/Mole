//go:build darwin

package main

import (
	"context"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/shirou/gopsutil/v4/disk"
)

// WatchMetrics holds the minimal set of metrics needed for rule evaluation.
type WatchMetrics struct {
	DiskFreeGB      float64 // Free disk space in GB on root volume
	DiskUsedPercent float64 // Disk usage percentage on root volume
	CPUPercent      float64 // Overall CPU usage percentage
	BatteryHealth   int     // Battery maximum capacity percentage (e.g. 85 = 85% of original)
}

// CollectWatchMetrics gathers the metrics needed for threshold evaluation.
func CollectWatchMetrics() (WatchMetrics, error) {
	var m WatchMetrics
	var firstErr error

	// Disk metrics for root volume.
	usage, err := disk.Usage("/")
	if err != nil {
		firstErr = fmt.Errorf("disk: %w", err)
	} else {
		m.DiskFreeGB = float64(usage.Free) / (1 << 30) // bytes to GB
		m.DiskUsedPercent = usage.UsedPercent
	}

	// CPU usage (brief sample).
	percents, err := cpu.Percent(500*time.Millisecond, false)
	if err != nil {
		if firstErr == nil {
			firstErr = fmt.Errorf("cpu: %w", err)
		}
	} else if len(percents) > 0 {
		m.CPUPercent = percents[0]
	}

	// Battery health via ioreg (macOS-specific).
	m.BatteryHealth = collectBatteryHealth()

	return m, firstErr
}

// collectBatteryHealth reads battery maximum capacity from ioreg.
// Returns 100 if battery info is unavailable (e.g. desktop Mac).
func collectBatteryHealth() int {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, "ioreg", "-rc", "AppleSmartBattery").Output()
	if err != nil {
		return 100
	}

	output := string(out)
	maxCap := extractIORegInt(output, "\"MaxCapacity\"")
	designCap := extractIORegInt(output, "\"DesignCapacity\"")

	if designCap <= 0 || maxCap <= 0 {
		return 100
	}

	health := (maxCap * 100) / designCap
	if health > 100 {
		health = 100
	}
	return health
}

// extractIORegInt extracts an integer value from ioreg output for the given key.
func extractIORegInt(output, key string) int {
	for _, line := range strings.Split(output, "\n") {
		if strings.Contains(line, key) {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) == 2 {
				val, err := strconv.Atoi(strings.TrimSpace(parts[1]))
				if err == nil {
					return val
				}
			}
		}
	}
	return 0
}
