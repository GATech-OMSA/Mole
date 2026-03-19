//go:build darwin

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// SizeRecord represents a single disk usage measurement at a point in time.
type SizeRecord struct {
	Path      string    `json:"path"`
	SizeBytes int64     `json:"size_bytes"`
	Timestamp time.Time `json:"timestamp"`
}

// LoadHistory reads size history records from a JSON file at the given path.
func LoadHistory(path string) ([]SizeRecord, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading history file: %w", err)
	}

	var records []SizeRecord
	if err := json.Unmarshal(data, &records); err != nil {
		return nil, fmt.Errorf("parsing history file: %w", err)
	}

	return records, nil
}

// SaveHistory writes size history records to a JSON file at the given path.
func SaveHistory(path string, records []SizeRecord) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return fmt.Errorf("creating history directory: %w", err)
	}

	data, err := json.MarshalIndent(records, "", "  ")
	if err != nil {
		return fmt.Errorf("marshaling history: %w", err)
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("writing history file: %w", err)
	}

	return nil
}

// CalculateGrowthRate computes the average growth rate in bytes per day
// using a simple linear regression between the first and last records.
// Returns 0 if there are fewer than 2 records or if no time has elapsed.
func CalculateGrowthRate(records []SizeRecord) float64 {
	if len(records) < 2 {
		return 0
	}

	first := records[0]
	last := records[len(records)-1]

	elapsed := last.Timestamp.Sub(first.Timestamp)
	if elapsed <= 0 {
		return 0
	}

	days := elapsed.Hours() / 24
	if days == 0 {
		return 0
	}

	sizeChange := float64(last.SizeBytes - first.SizeBytes)
	return sizeChange / days
}

// PredictDaysTillFull estimates how many days until disk space runs out
// given the current free bytes and a growth rate in bytes per day.
// Returns -1 if growth rate is zero or negative (disk is not growing).
func PredictDaysTillFull(freeBytes int64, growthRate float64) int {
	if growthRate <= 0 {
		return -1
	}

	days := float64(freeBytes) / growthRate
	return int(days)
}

// defaultHistoryPath returns the default path for the size history file.
func defaultHistoryPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".config", "mole", "size_history.json")
}
