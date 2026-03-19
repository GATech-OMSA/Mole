package main

import (
	"testing"

	"github.com/shirou/gopsutil/v4/disk"
)

func TestParseSMARTStatus(t *testing.T) {
	tests := []struct {
		name string
		input string
		want string
	}{
		{
			name: "verified status",
			input: `   Device Identifier:         disk0
   Device Node:               /dev/disk0
   SMART Status:              Verified
   Disk Size:                 500.1 GB`,
			want: "Verified",
		},
		{
			name: "failing status",
			input: `   Device Identifier:         disk0
   Device Node:               /dev/disk0
   SMART Status:              Failing
   Disk Size:                 500.1 GB`,
			want: "Failing",
		},
		{
			name: "not supported",
			input: `   Device Identifier:         disk0
   Device Node:               /dev/disk0
   SMART Status:              Not Supported
   Disk Size:                 500.1 GB`,
			want: "Not Supported",
		},
		{
			name: "no smart line",
			input: `   Device Identifier:         disk0
   Device Node:               /dev/disk0
   Disk Size:                 500.1 GB`,
			want: "",
		},
		{
			name: "empty output",
			input: "",
			want: "",
		},
		{
			name: "smart status with extra whitespace",
			input: `   SMART Status:           Verified  `,
			want: "Verified",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseSMARTStatus(tt.input)
			if got != tt.want {
				t.Errorf("parseSMARTStatus() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestShouldSkipDiskPartition(t *testing.T) {
	tests := []struct {
		name string
		part disk.PartitionStat
		want bool
	}{
		{
			name: "keep local apfs root volume",
			part: disk.PartitionStat{
				Device:     "/dev/disk3s1s1",
				Mountpoint: "/",
				Fstype:     "apfs",
			},
			want: false,
		},
		{
			name: "skip macfuse mirror mount",
			part: disk.PartitionStat{
				Device:     "kaku-local:/",
				Mountpoint: "/Users/tw93/Library/Caches/dev.kaku/sshfs/kaku-local",
				Fstype:     "macfuse",
			},
			want: true,
		},
		{
			name: "skip smb share",
			part: disk.PartitionStat{
				Device:     "//server/share",
				Mountpoint: "/Volumes/share",
				Fstype:     "smbfs",
			},
			want: true,
		},
		{
			name: "skip system volume",
			part: disk.PartitionStat{
				Device:     "/dev/disk3s5",
				Mountpoint: "/System/Volumes/Data",
				Fstype:     "apfs",
			},
			want: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := shouldSkipDiskPartition(tt.part); got != tt.want {
				t.Fatalf("shouldSkipDiskPartition(%+v) = %v, want %v", tt.part, got, tt.want)
			}
		})
	}
}
