//go:build darwin

package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

// validMetrics defines the set of recognized metric names.
var validMetrics = map[string]bool{
	"disk_free_gb":      true,
	"cpu_percent":       true,
	"battery_health":    true,
	"disk_used_percent": true,
}

// isValidMetric reports whether the given name is a recognized metric.
func isValidMetric(name string) bool {
	return validMetrics[name]
}

// Rule represents a single threshold alert rule.
type Rule struct {
	Metric    string  // e.g. "disk_free_gb", "cpu_percent"
	Operator  string  // "<" or ">"
	Threshold float64 // Numeric threshold value
}

// Key returns a unique string key for this rule, used for cooldown tracking.
func (r Rule) Key() string {
	return fmt.Sprintf("%s %s %g", r.Metric, r.Operator, r.Threshold)
}

// String returns a human-readable representation of the rule.
func (r Rule) String() string {
	return fmt.Sprintf("%s %s %g", r.Metric, r.Operator, r.Threshold)
}

// ParseRule parses a single rule from a config line.
// Lines starting with '#' are treated as comments.
// Format: metric operator threshold (e.g. "disk_free_gb < 10").
func ParseRule(line string) (Rule, error) {
	line = strings.TrimSpace(line)
	if line == "" {
		return Rule{}, fmt.Errorf("empty line")
	}
	if strings.HasPrefix(line, "#") {
		return Rule{}, fmt.Errorf("comment line")
	}

	fields := strings.Fields(line)
	if len(fields) < 3 {
		return Rule{}, fmt.Errorf("expected 3 tokens (metric operator threshold), got %d", len(fields))
	}
	if len(fields) > 3 {
		return Rule{}, fmt.Errorf("expected 3 tokens (metric operator threshold), got %d extra tokens", len(fields))
	}

	metric := fields[0]
	operator := fields[1]
	threshStr := fields[2]

	if !isValidMetric(metric) {
		return Rule{}, fmt.Errorf("unknown metric %q", metric)
	}

	if operator != "<" && operator != ">" {
		return Rule{}, fmt.Errorf("unsupported operator %q (use < or >)", operator)
	}

	threshold, err := strconv.ParseFloat(threshStr, 64)
	if err != nil {
		return Rule{}, fmt.Errorf("invalid threshold %q: %w", threshStr, err)
	}
	if threshold <= 0 {
		return Rule{}, fmt.Errorf("threshold must be positive, got %g", threshold)
	}

	return Rule{
		Metric:    metric,
		Operator:  operator,
		Threshold: threshold,
	}, nil
}

// ParseRulesFromReader parses all rules from a reader, skipping comments and blank lines.
func ParseRulesFromReader(r io.Reader) ([]Rule, error) {
	var rules []Rule
	scanner := bufio.NewScanner(r)
	lineNum := 0

	for scanner.Scan() {
		lineNum++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		rule, err := ParseRule(line)
		if err != nil {
			return nil, fmt.Errorf("line %d: %w", lineNum, err)
		}
		rules = append(rules, rule)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("reading rules: %w", err)
	}

	return rules, nil
}

// ParseRulesFromFile reads and parses rules from a file path.
func ParseRulesFromFile(path string) ([]Rule, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("opening rules file: %w", err)
	}
	defer f.Close()

	return ParseRulesFromReader(f)
}

// EvaluateRule checks whether a rule's threshold is violated for the given metrics.
// Returns (fired, description). If the rule doesn't fire, description is empty.
func EvaluateRule(rule Rule, snap WatchMetrics) (bool, string) {
	var value float64
	var unit string

	switch rule.Metric {
	case "disk_free_gb":
		value = snap.DiskFreeGB
		unit = "GB"
	case "disk_used_percent":
		value = snap.DiskUsedPercent
		unit = "%"
	case "cpu_percent":
		value = snap.CPUPercent
		unit = "%"
	case "battery_health":
		value = float64(snap.BatteryHealth)
		unit = "%"
	default:
		return false, ""
	}

	var fired bool
	switch rule.Operator {
	case "<":
		fired = value < rule.Threshold
	case ">":
		fired = value > rule.Threshold
	}

	if !fired {
		return false, ""
	}

	desc := fmt.Sprintf("%s is %s%s (threshold: %s %g)",
		rule.Metric, formatValue(value), unit, rule.Operator, rule.Threshold)
	return true, desc
}

// formatValue formats a metric value for display.
func formatValue(v float64) string {
	if v == float64(int(v)) {
		return fmt.Sprintf("%d", int(v))
	}
	return fmt.Sprintf("%.1f", v)
}

// FormatNotification returns a notification title and body for a fired rule.
func FormatNotification(rule Rule, desc string) (string, string) {
	title := "Mole Alert"
	return title, desc
}

// Cooldown tracks when rules last fired to prevent repeated notifications.
type Cooldown struct {
	mu       sync.Mutex
	duration time.Duration
	fired    map[string]time.Time
}

// NewCooldown creates a cooldown tracker with the given duration.
func NewCooldown(d time.Duration) *Cooldown {
	return &Cooldown{
		duration: d,
		fired:    make(map[string]time.Time),
	}
}

// OnCooldown reports whether the rule has fired within the cooldown period.
func (c *Cooldown) OnCooldown(rule Rule) bool {
	c.mu.Lock()
	defer c.mu.Unlock()

	last, ok := c.fired[rule.Key()]
	if !ok {
		return false
	}
	return time.Since(last) < c.duration
}

// Record marks a rule as having just fired.
func (c *Cooldown) Record(rule Rule) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.fired[rule.Key()] = time.Now()
}
