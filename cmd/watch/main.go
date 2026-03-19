//go:build darwin

// Package main provides the mo watch command for background threshold alerting.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

var (
	Version   = "dev"
	BuildTime = ""
)

func defaultConfigPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".config", "mole", "watch_rules")
}

func run() error {
	configPath := flag.String("config", defaultConfigPath(), "path to watch rules config file")
	interval := flag.Duration("interval", 60*time.Second, "check interval between metric collection")
	once := flag.Bool("once", false, "run once and exit (for testing)")
	flag.Parse()

	if *configPath == "" {
		return fmt.Errorf("could not determine config path; set --config explicitly")
	}

	rules, err := ParseRulesFromFile(*configPath)
	if err != nil {
		return fmt.Errorf("loading rules from %s: %w", *configPath, err)
	}

	if len(rules) == 0 {
		fmt.Fprintf(os.Stderr, "no rules found in %s\n", *configPath)
		return nil
	}

	fmt.Fprintf(os.Stderr, "mo watch: loaded %d rules, checking every %s\n", len(rules), *interval)

	cooldown := NewCooldown(15 * time.Minute)

	for {
		if err := checkRules(rules, cooldown); err != nil {
			fmt.Fprintf(os.Stderr, "mo watch: error: %v\n", err)
		}

		if *once {
			return nil
		}

		time.Sleep(*interval)
	}
}

func checkRules(rules []Rule, cooldown *Cooldown) error {
	snap, err := CollectWatchMetrics()
	if err != nil {
		return fmt.Errorf("collecting metrics: %w", err)
	}

	for _, rule := range rules {
		fired, desc := EvaluateRule(rule, snap)
		if !fired {
			continue
		}

		if cooldown.OnCooldown(rule) {
			continue
		}

		title, body := FormatNotification(rule, desc)
		if err := notify(title, body); err != nil {
			fmt.Fprintf(os.Stderr, "mo watch: notification failed for %s: %v\n", rule, err)
		} else {
			fmt.Fprintf(os.Stderr, "mo watch: alert - %s\n", desc)
		}

		cooldown.Record(rule)
	}

	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "mo watch: %v\n", err)
		os.Exit(1)
	}
}
