//go:build darwin

package main

import (
	"strings"
	"sync"
	"testing"
	"time"
)

func TestParseRule(t *testing.T) {
	tests := []struct {
		name    string
		line    string
		want    Rule
		wantErr bool
	}{
		{
			name: "disk free less than",
			line: "disk_free_gb < 10",
			want: Rule{
				Metric:    "disk_free_gb",
				Operator:  "<",
				Threshold: 10,
			},
		},
		{
			name: "cpu percent greater than",
			line: "cpu_percent > 90",
			want: Rule{
				Metric:    "cpu_percent",
				Operator:  ">",
				Threshold: 90,
			},
		},
		{
			name: "battery health less than",
			line: "battery_health < 80",
			want: Rule{
				Metric:    "battery_health",
				Operator:  "<",
				Threshold: 80,
			},
		},
		{
			name: "disk used percent greater than",
			line: "disk_used_percent > 90",
			want: Rule{
				Metric:    "disk_used_percent",
				Operator:  ">",
				Threshold: 90,
			},
		},
		{
			name: "decimal threshold",
			line: "disk_free_gb < 5.5",
			want: Rule{
				Metric:    "disk_free_gb",
				Operator:  "<",
				Threshold: 5.5,
			},
		},
		{
			name: "extra whitespace",
			line: "  cpu_percent   >   85  ",
			want: Rule{
				Metric:    "cpu_percent",
				Operator:  ">",
				Threshold: 85,
			},
		},
		{
			name:    "empty line",
			line:    "",
			wantErr: true,
		},
		{
			name:    "comment line",
			line:    "# this is a comment",
			wantErr: true,
		},
		{
			name:    "missing threshold",
			line:    "cpu_percent >",
			wantErr: true,
		},
		{
			name:    "invalid threshold",
			line:    "cpu_percent > abc",
			wantErr: true,
		},
		{
			name:    "invalid operator",
			line:    "cpu_percent = 90",
			wantErr: true,
		},
		{
			name:    "unknown metric",
			line:    "unknown_metric > 50",
			wantErr: true,
		},
		{
			name:    "too few tokens",
			line:    "cpu_percent",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseRule(tt.line)
			if tt.wantErr {
				if err == nil {
					t.Errorf("ParseRule(%q) expected error, got nil", tt.line)
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseRule(%q) unexpected error: %v", tt.line, err)
			}
			if got.Metric != tt.want.Metric {
				t.Errorf("Metric = %q, want %q", got.Metric, tt.want.Metric)
			}
			if got.Operator != tt.want.Operator {
				t.Errorf("Operator = %q, want %q", got.Operator, tt.want.Operator)
			}
			if got.Threshold != tt.want.Threshold {
				t.Errorf("Threshold = %v, want %v", got.Threshold, tt.want.Threshold)
			}
		})
	}
}

func TestParseRulesFromReader(t *testing.T) {
	input := `# Mole watch rules
disk_free_gb < 10
cpu_percent > 90

# Battery monitoring
battery_health < 80
disk_used_percent > 90
`
	rules, err := ParseRulesFromReader(strings.NewReader(input))
	if err != nil {
		t.Fatalf("ParseRulesFromReader() unexpected error: %v", err)
	}

	if len(rules) != 4 {
		t.Fatalf("got %d rules, want 4", len(rules))
	}

	expected := []struct {
		metric   string
		operator string
		thresh   float64
	}{
		{"disk_free_gb", "<", 10},
		{"cpu_percent", ">", 90},
		{"battery_health", "<", 80},
		{"disk_used_percent", ">", 90},
	}

	for i, e := range expected {
		if rules[i].Metric != e.metric {
			t.Errorf("rule[%d].Metric = %q, want %q", i, rules[i].Metric, e.metric)
		}
		if rules[i].Operator != e.operator {
			t.Errorf("rule[%d].Operator = %q, want %q", i, rules[i].Operator, e.operator)
		}
		if rules[i].Threshold != e.thresh {
			t.Errorf("rule[%d].Threshold = %v, want %v", i, rules[i].Threshold, e.thresh)
		}
	}
}

func TestEvaluateRule(t *testing.T) {
	snap := WatchMetrics{
		DiskFreeGB:      8.5,
		DiskUsedPercent: 92.3,
		CPUPercent:      75.0,
		BatteryHealth:   85,
	}

	tests := []struct {
		name     string
		rule     Rule
		want     bool
		wantDesc string
	}{
		{
			name: "disk free below threshold - fires",
			rule: Rule{Metric: "disk_free_gb", Operator: "<", Threshold: 10},
			want: true,
		},
		{
			name: "disk free above threshold - does not fire",
			rule: Rule{Metric: "disk_free_gb", Operator: "<", Threshold: 5},
			want: false,
		},
		{
			name: "cpu below threshold - does not fire",
			rule: Rule{Metric: "cpu_percent", Operator: ">", Threshold: 90},
			want: false,
		},
		{
			name: "cpu above threshold - fires",
			rule: Rule{Metric: "cpu_percent", Operator: ">", Threshold: 50},
			want: true,
		},
		{
			name: "disk used above threshold - fires",
			rule: Rule{Metric: "disk_used_percent", Operator: ">", Threshold: 90},
			want: true,
		},
		{
			name: "disk used below threshold - does not fire",
			rule: Rule{Metric: "disk_used_percent", Operator: ">", Threshold: 95},
			want: false,
		},
		{
			name: "battery health below threshold - fires",
			rule: Rule{Metric: "battery_health", Operator: "<", Threshold: 90},
			want: true,
		},
		{
			name: "battery health above threshold - does not fire",
			rule: Rule{Metric: "battery_health", Operator: "<", Threshold: 80},
			want: false,
		},
		{
			name: "exact threshold with less-than - does not fire",
			rule: Rule{Metric: "disk_free_gb", Operator: "<", Threshold: 8.5},
			want: false,
		},
		{
			name: "exact threshold with greater-than - does not fire",
			rule: Rule{Metric: "cpu_percent", Operator: ">", Threshold: 75.0},
			want: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fired, _ := EvaluateRule(tt.rule, snap)
			if fired != tt.want {
				t.Errorf("EvaluateRule() = %v, want %v", fired, tt.want)
			}
		})
	}
}

func TestEvaluateRuleDescription(t *testing.T) {
	snap := WatchMetrics{
		DiskFreeGB:      8.5,
		DiskUsedPercent: 92.3,
		CPUPercent:      95.0,
		BatteryHealth:   70,
	}

	tests := []struct {
		name     string
		rule     Rule
		wantSub  string // Substring that should appear in description
	}{
		{
			name:    "disk free description includes value",
			rule:    Rule{Metric: "disk_free_gb", Operator: "<", Threshold: 10},
			wantSub: "8.5",
		},
		{
			name:    "cpu description includes value",
			rule:    Rule{Metric: "cpu_percent", Operator: ">", Threshold: 90},
			wantSub: "95",
		},
		{
			name:    "battery description includes value",
			rule:    Rule{Metric: "battery_health", Operator: "<", Threshold: 80},
			wantSub: "70",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fired, desc := EvaluateRule(tt.rule, snap)
			if !fired {
				t.Fatal("expected rule to fire")
			}
			if !strings.Contains(desc, tt.wantSub) {
				t.Errorf("description %q does not contain %q", desc, tt.wantSub)
			}
		})
	}
}

func TestFormatNotification(t *testing.T) {
	tests := []struct {
		name     string
		rule     Rule
		desc     string
		wantSub  []string
	}{
		{
			name:    "disk alert message",
			rule:    Rule{Metric: "disk_free_gb", Operator: "<", Threshold: 10},
			desc:    "disk_free_gb is 8.5 GB (threshold: < 10)",
			wantSub: []string{"disk_free_gb", "8.5"},
		},
		{
			name:    "cpu alert message",
			rule:    Rule{Metric: "cpu_percent", Operator: ">", Threshold: 90},
			desc:    "cpu_percent is 95.0% (threshold: > 90)",
			wantSub: []string{"cpu_percent", "95.0"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			title, body := FormatNotification(tt.rule, tt.desc)
			if title == "" {
				t.Error("FormatNotification() title is empty")
			}
			for _, sub := range tt.wantSub {
				if !strings.Contains(body, sub) {
					t.Errorf("notification body %q does not contain %q", body, sub)
				}
			}
		})
	}
}

func TestCooldown(t *testing.T) {
	cd := NewCooldown(15 * time.Minute)

	rule := Rule{Metric: "cpu_percent", Operator: ">", Threshold: 90}

	// First check: should not be on cooldown.
	if cd.OnCooldown(rule) {
		t.Error("rule should not be on cooldown initially")
	}

	// Record the alert.
	cd.Record(rule)

	// Immediately after: should be on cooldown.
	if !cd.OnCooldown(rule) {
		t.Error("rule should be on cooldown after recording")
	}

	// Different rule: should not be on cooldown.
	otherRule := Rule{Metric: "disk_free_gb", Operator: "<", Threshold: 10}
	if cd.OnCooldown(otherRule) {
		t.Error("different rule should not be on cooldown")
	}
}

func TestCooldownExpiry(t *testing.T) {
	// Use a very short cooldown for testing.
	cd := NewCooldown(50 * time.Millisecond)

	rule := Rule{Metric: "cpu_percent", Operator: ">", Threshold: 90}
	cd.Record(rule)

	if !cd.OnCooldown(rule) {
		t.Error("rule should be on cooldown immediately after recording")
	}

	// Wait for cooldown to expire.
	time.Sleep(60 * time.Millisecond)

	if cd.OnCooldown(rule) {
		t.Error("rule should no longer be on cooldown after duration elapsed")
	}
}

func TestCooldownConcurrency(t *testing.T) {
	cd := NewCooldown(1 * time.Minute)
	rule := Rule{Metric: "cpu_percent", Operator: ">", Threshold: 90}

	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			cd.OnCooldown(rule)
			cd.Record(rule)
		}()
	}
	wg.Wait()

	// After concurrent access, the rule should be on cooldown.
	if !cd.OnCooldown(rule) {
		t.Error("rule should be on cooldown after concurrent Record calls")
	}
}
