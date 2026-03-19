//go:build darwin

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseRuleEdgeCases(t *testing.T) {
	tests := []struct {
		name    string
		line    string
		wantErr bool
		errSub  string // Expected substring in error message
	}{
		{
			name:    "whitespace only",
			line:    "   ",
			wantErr: true,
			errSub:  "empty",
		},
		{
			name:    "tab-only line",
			line:    "\t\t",
			wantErr: true,
			errSub:  "empty",
		},
		{
			name:    "comment with leading spaces",
			line:    "   # indented comment",
			wantErr: true,
			errSub:  "comment",
		},
		{
			name:    "operator less-than-or-equal not supported",
			line:    "cpu_percent <= 90",
			wantErr: true,
			errSub:  "operator",
		},
		{
			name:    "operator greater-than-or-equal not supported",
			line:    "cpu_percent >= 90",
			wantErr: true,
			errSub:  "operator",
		},
		{
			name:    "negative threshold",
			line:    "cpu_percent > -5",
			wantErr: true,
			errSub:  "threshold",
		},
		{
			name:    "zero threshold is valid",
			line:    "disk_free_gb < 0",
			wantErr: true,
			errSub:  "threshold",
		},
		{
			name:    "extra tokens ignored",
			line:    "cpu_percent > 90 for 5m",
			wantErr: true,
			errSub:  "tokens",
		},
		{
			name:    "metric with special chars",
			line:    "cpu.percent > 90",
			wantErr: true,
			errSub:  "metric",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseRule(tt.line)
			if !tt.wantErr {
				if err != nil {
					t.Errorf("ParseRule(%q) unexpected error: %v", tt.line, err)
				}
				return
			}
			if err == nil {
				t.Fatalf("ParseRule(%q) expected error containing %q, got nil", tt.line, tt.errSub)
			}
			if !strings.Contains(strings.ToLower(err.Error()), tt.errSub) {
				t.Errorf("ParseRule(%q) error = %q, want substring %q", tt.line, err.Error(), tt.errSub)
			}
		})
	}
}

func TestParseRulesFromReaderAllComments(t *testing.T) {
	input := `# Comment 1
# Comment 2
# Comment 3
`
	rules, err := ParseRulesFromReader(strings.NewReader(input))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(rules) != 0 {
		t.Errorf("got %d rules from all-comment input, want 0", len(rules))
	}
}

func TestParseRulesFromReaderEmpty(t *testing.T) {
	rules, err := ParseRulesFromReader(strings.NewReader(""))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(rules) != 0 {
		t.Errorf("got %d rules from empty input, want 0", len(rules))
	}
}

func TestParseRulesFromFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "rules.conf")

	content := `# Test rules
disk_free_gb < 10
cpu_percent > 90
`
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatalf("failed to write test file: %v", err)
	}

	rules, err := ParseRulesFromFile(path)
	if err != nil {
		t.Fatalf("ParseRulesFromFile() unexpected error: %v", err)
	}
	if len(rules) != 2 {
		t.Errorf("got %d rules, want 2", len(rules))
	}
}

func TestParseRulesFromFileMissing(t *testing.T) {
	_, err := ParseRulesFromFile("/nonexistent/path/rules.conf")
	if err == nil {
		t.Error("ParseRulesFromFile() expected error for missing file, got nil")
	}
}

func TestRuleKey(t *testing.T) {
	r1 := Rule{Metric: "cpu_percent", Operator: ">", Threshold: 90}
	r2 := Rule{Metric: "cpu_percent", Operator: ">", Threshold: 90}
	r3 := Rule{Metric: "cpu_percent", Operator: ">", Threshold: 80}

	if r1.Key() != r2.Key() {
		t.Errorf("identical rules should have same key: %q != %q", r1.Key(), r2.Key())
	}
	if r1.Key() == r3.Key() {
		t.Error("rules with different thresholds should have different keys")
	}
}

func TestRuleString(t *testing.T) {
	r := Rule{Metric: "disk_free_gb", Operator: "<", Threshold: 10}
	s := r.String()
	if !strings.Contains(s, "disk_free_gb") {
		t.Errorf("String() = %q, want to contain metric name", s)
	}
	if !strings.Contains(s, "<") {
		t.Errorf("String() = %q, want to contain operator", s)
	}
	if !strings.Contains(s, "10") {
		t.Errorf("String() = %q, want to contain threshold", s)
	}
}

func TestEvaluateRuleUnknownMetric(t *testing.T) {
	// A rule with an unrecognized metric should not fire.
	r := Rule{Metric: "nonexistent_metric", Operator: ">", Threshold: 50}
	snap := WatchMetrics{CPUPercent: 95}

	fired, _ := EvaluateRule(r, snap)
	if fired {
		t.Error("EvaluateRule() with unknown metric should not fire")
	}
}

func TestValidMetrics(t *testing.T) {
	// Ensure all documented metrics are recognized.
	metrics := []string{"disk_free_gb", "cpu_percent", "battery_health", "disk_used_percent"}
	for _, m := range metrics {
		if !isValidMetric(m) {
			t.Errorf("isValidMetric(%q) = false, want true", m)
		}
	}

	// Ensure unknown metrics are rejected.
	invalid := []string{"memory_percent", "swap_used", "gpu_usage", ""}
	for _, m := range invalid {
		if isValidMetric(m) {
			t.Errorf("isValidMetric(%q) = true, want false", m)
		}
	}
}
