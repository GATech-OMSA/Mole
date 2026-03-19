//go:build darwin

package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCalculateGrowthRate(t *testing.T) {
	baseTime := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

	tests := []struct {
		name    string
		records []SizeRecord
		want    float64
	}{
		{
			name:    "empty records",
			records: []SizeRecord{},
			want:    0,
		},
		{
			name: "single record",
			records: []SizeRecord{
				{Path: "/", SizeBytes: 1000, Timestamp: baseTime},
			},
			want: 0,
		},
		{
			name: "two records one day apart",
			records: []SizeRecord{
				{Path: "/", SizeBytes: 1000, Timestamp: baseTime},
				{Path: "/", SizeBytes: 2000, Timestamp: baseTime.Add(24 * time.Hour)},
			},
			want: 1000, // 1000 bytes per day
		},
		{
			name: "two records ten days apart",
			records: []SizeRecord{
				{Path: "/", SizeBytes: 0, Timestamp: baseTime},
				{Path: "/", SizeBytes: 10000, Timestamp: baseTime.Add(10 * 24 * time.Hour)},
			},
			want: 1000, // 1000 bytes per day
		},
		{
			name: "shrinking disk usage",
			records: []SizeRecord{
				{Path: "/", SizeBytes: 5000, Timestamp: baseTime},
				{Path: "/", SizeBytes: 3000, Timestamp: baseTime.Add(2 * 24 * time.Hour)},
			},
			want: -1000, // negative growth
		},
		{
			name: "no time elapsed",
			records: []SizeRecord{
				{Path: "/", SizeBytes: 1000, Timestamp: baseTime},
				{Path: "/", SizeBytes: 2000, Timestamp: baseTime},
			},
			want: 0,
		},
		{
			name: "multiple records uses first and last",
			records: []SizeRecord{
				{Path: "/", SizeBytes: 1000, Timestamp: baseTime},
				{Path: "/", SizeBytes: 9999, Timestamp: baseTime.Add(12 * time.Hour)},
				{Path: "/", SizeBytes: 5000, Timestamp: baseTime.Add(4 * 24 * time.Hour)},
			},
			want: 1000, // (5000 - 1000) / 4 days
		},
		{
			name: "large values",
			records: []SizeRecord{
				{Path: "/", SizeBytes: 100_000_000_000, Timestamp: baseTime},
				{Path: "/", SizeBytes: 200_000_000_000, Timestamp: baseTime.Add(10 * 24 * time.Hour)},
			},
			want: 10_000_000_000, // 10GB per day
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CalculateGrowthRate(tt.records)
			if got != tt.want {
				t.Errorf("CalculateGrowthRate() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestPredictDaysTillFull(t *testing.T) {
	tests := []struct {
		name       string
		freeBytes  int64
		growthRate float64
		want       int
	}{
		{
			name:       "zero growth rate",
			freeBytes:  1_000_000,
			growthRate: 0,
			want:       -1,
		},
		{
			name:       "negative growth rate",
			freeBytes:  1_000_000,
			growthRate: -500,
			want:       -1,
		},
		{
			name:       "simple prediction",
			freeBytes:  10000,
			growthRate: 1000,
			want:       10,
		},
		{
			name:       "large free space slow growth",
			freeBytes:  100_000_000_000, // 100GB
			growthRate: 1_000_000_000,   // 1GB/day
			want:       100,
		},
		{
			name:       "almost full",
			freeBytes:  500,
			growthRate: 1000,
			want:       0,
		},
		{
			name:       "fractional days truncates",
			freeBytes:  1500,
			growthRate: 1000,
			want:       1,
		},
		{
			name:       "zero free bytes",
			freeBytes:  0,
			growthRate: 1000,
			want:       0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := PredictDaysTillFull(tt.freeBytes, tt.growthRate)
			if got != tt.want {
				t.Errorf("PredictDaysTillFull(%d, %v) = %d, want %d",
					tt.freeBytes, tt.growthRate, got, tt.want)
			}
		})
	}
}

func TestLoadHistory(t *testing.T) {
	dir := t.TempDir()

	t.Run("valid file", func(t *testing.T) {
		path := filepath.Join(dir, "valid.json")
		content := `[
  {"path": "/", "size_bytes": 1000, "timestamp": "2026-01-01T00:00:00Z"},
  {"path": "/", "size_bytes": 2000, "timestamp": "2026-01-02T00:00:00Z"}
]`
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatalf("failed to write test file: %v", err)
		}

		records, err := LoadHistory(path)
		if err != nil {
			t.Fatalf("LoadHistory() unexpected error: %v", err)
		}
		if len(records) != 2 {
			t.Fatalf("got %d records, want 2", len(records))
		}
		if records[0].SizeBytes != 1000 {
			t.Errorf("records[0].SizeBytes = %d, want 1000", records[0].SizeBytes)
		}
		if records[1].SizeBytes != 2000 {
			t.Errorf("records[1].SizeBytes = %d, want 2000", records[1].SizeBytes)
		}
	})

	t.Run("missing file", func(t *testing.T) {
		_, err := LoadHistory(filepath.Join(dir, "nonexistent.json"))
		if err == nil {
			t.Error("LoadHistory() expected error for missing file, got nil")
		}
	})

	t.Run("invalid json", func(t *testing.T) {
		path := filepath.Join(dir, "invalid.json")
		if err := os.WriteFile(path, []byte("not json"), 0644); err != nil {
			t.Fatalf("failed to write test file: %v", err)
		}

		_, err := LoadHistory(path)
		if err == nil {
			t.Error("LoadHistory() expected error for invalid JSON, got nil")
		}
	})

	t.Run("empty array", func(t *testing.T) {
		path := filepath.Join(dir, "empty.json")
		if err := os.WriteFile(path, []byte("[]"), 0644); err != nil {
			t.Fatalf("failed to write test file: %v", err)
		}

		records, err := LoadHistory(path)
		if err != nil {
			t.Fatalf("LoadHistory() unexpected error: %v", err)
		}
		if len(records) != 0 {
			t.Errorf("got %d records from empty array, want 0", len(records))
		}
	})
}

func TestSaveHistory(t *testing.T) {
	dir := t.TempDir()

	t.Run("save and reload", func(t *testing.T) {
		path := filepath.Join(dir, "save_test.json")
		records := []SizeRecord{
			{Path: "/Users/test", SizeBytes: 5000, Timestamp: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)},
			{Path: "/Users/test", SizeBytes: 6000, Timestamp: time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC)},
		}

		if err := SaveHistory(path, records); err != nil {
			t.Fatalf("SaveHistory() unexpected error: %v", err)
		}

		loaded, err := LoadHistory(path)
		if err != nil {
			t.Fatalf("LoadHistory() after save unexpected error: %v", err)
		}
		if len(loaded) != 2 {
			t.Fatalf("got %d records after round-trip, want 2", len(loaded))
		}
		if loaded[0].SizeBytes != 5000 {
			t.Errorf("loaded[0].SizeBytes = %d, want 5000", loaded[0].SizeBytes)
		}
		if loaded[1].Path != "/Users/test" {
			t.Errorf("loaded[1].Path = %q, want %q", loaded[1].Path, "/Users/test")
		}
	})

	t.Run("creates parent directories", func(t *testing.T) {
		path := filepath.Join(dir, "nested", "deep", "history.json")
		records := []SizeRecord{
			{Path: "/", SizeBytes: 100, Timestamp: time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)},
		}

		if err := SaveHistory(path, records); err != nil {
			t.Fatalf("SaveHistory() unexpected error: %v", err)
		}

		if _, err := os.Stat(path); os.IsNotExist(err) {
			t.Error("SaveHistory() did not create file")
		}
	})

	t.Run("empty records", func(t *testing.T) {
		path := filepath.Join(dir, "empty_save.json")
		if err := SaveHistory(path, []SizeRecord{}); err != nil {
			t.Fatalf("SaveHistory() unexpected error: %v", err)
		}

		loaded, err := LoadHistory(path)
		if err != nil {
			t.Fatalf("LoadHistory() after empty save: %v", err)
		}
		if len(loaded) != 0 {
			t.Errorf("got %d records, want 0", len(loaded))
		}
	})
}

func TestDefaultHistoryPath(t *testing.T) {
	path := defaultHistoryPath()
	if path == "" {
		t.Skip("could not determine home directory")
	}
	if !filepath.IsAbs(path) {
		t.Errorf("defaultHistoryPath() = %q, want absolute path", path)
	}
	if filepath.Base(path) != "size_history.json" {
		t.Errorf("defaultHistoryPath() basename = %q, want size_history.json", filepath.Base(path))
	}
}
