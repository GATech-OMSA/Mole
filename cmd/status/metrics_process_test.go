package main

import (
	"testing"
)

func TestParseProcessRSS(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		wantCount int
		wantFirst ProcessInfo
	}{
		{
			name: "standard ps output with rss",
			input: `  %CPU %MEM   RSS COMMAND
  25.0  3.2 524288 Google Chrome
  12.5  1.8 294912 Safari
   5.0  0.5  81920 Terminal
   2.0  0.3  49152 Finder
   1.0  0.1  16384 loginwindow
   0.5  0.0   8192 cfprefsd`,
			wantCount: 5,
			wantFirst: ProcessInfo{
				Name:   "Chrome",
				CPU:    25.0,
				Memory: 3.2,
				RSS:    524288 * 1024,
			},
		},
		{
			name: "command with path",
			input: `  %CPU %MEM   RSS COMMAND
  10.0  2.0 131072 /usr/local/bin/node`,
			wantCount: 1,
			wantFirst: ProcessInfo{
				Name:   "node",
				CPU:    10.0,
				Memory: 2.0,
				RSS:    131072 * 1024,
			},
		},
		{
			name:      "empty output",
			input:     "",
			wantCount: 0,
		},
		{
			name:      "header only",
			input:     `  %CPU %MEM   RSS COMMAND`,
			wantCount: 0,
		},
		{
			name: "fewer than 3 fields",
			input: `  %CPU %MEM   RSS COMMAND
  10.0  2.0`,
			wantCount: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseProcessRSS(tt.input)
			if len(got) != tt.wantCount {
				t.Fatalf("parseProcessRSS() returned %d procs, want %d", len(got), tt.wantCount)
			}
			if tt.wantCount == 0 {
				return
			}
			p := got[0]
			if p.Name != tt.wantFirst.Name {
				t.Errorf("Name = %q, want %q", p.Name, tt.wantFirst.Name)
			}
			if p.CPU != tt.wantFirst.CPU {
				t.Errorf("CPU = %v, want %v", p.CPU, tt.wantFirst.CPU)
			}
			if p.Memory != tt.wantFirst.Memory {
				t.Errorf("Memory = %v, want %v", p.Memory, tt.wantFirst.Memory)
			}
			if p.RSS != tt.wantFirst.RSS {
				t.Errorf("RSS = %d, want %d", p.RSS, tt.wantFirst.RSS)
			}
		})
	}
}
