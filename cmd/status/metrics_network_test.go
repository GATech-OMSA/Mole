package main

import (
	"strings"
	"testing"

	gopsutilnet "github.com/shirou/gopsutil/v4/net"
)

func TestParseConnectionCount(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  int
	}{
		{
			name: "multiple established connections",
			input: `Active Internet connections
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
tcp4       0      0  192.168.1.5.52341      17.253.144.10.443      ESTABLISHED
tcp4       0      0  192.168.1.5.52340      17.253.144.10.443      ESTABLISHED
tcp4       0      0  192.168.1.5.52339      142.250.80.46.443      ESTABLISHED
tcp4       0      0  192.168.1.5.52338      140.82.113.26.443      CLOSE_WAIT
tcp4       0      0  192.168.1.5.52337      151.101.1.69.443       TIME_WAIT
tcp4       0      0  *.80                   *.*                    LISTEN`,
			want: 3,
		},
		{
			name: "no established connections",
			input: `Active Internet connections
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
tcp4       0      0  *.80                   *.*                    LISTEN
tcp4       0      0  192.168.1.5.52338      140.82.113.26.443      CLOSE_WAIT`,
			want: 0,
		},
		{
			name:  "empty output",
			input: "",
			want:  0,
		},
		{
			name: "only established lines",
			input: `tcp4       0      0  192.168.1.5.1234       10.0.0.1.443           ESTABLISHED`,
			want: 1,
		},
		{
			name: "established in mixed case should not match",
			input: `tcp4       0      0  192.168.1.5.1234       10.0.0.1.443           established`,
			want: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseConnectionCount(tt.input)
			if got != tt.want {
				t.Errorf("parseConnectionCount() = %d, want %d", got, tt.want)
			}
		})
	}
}

func TestCollectProxyFromEnvSupportsAllProxy(t *testing.T) {
	env := map[string]string{
		"ALL_PROXY": "socks5://127.0.0.1:7890",
	}
	getenv := func(key string) string {
		return env[key]
	}

	got := collectProxyFromEnv(getenv)
	if !got.Enabled {
		t.Fatalf("expected proxy enabled")
	}
	if got.Type != "SOCKS" {
		t.Fatalf("expected SOCKS type, got %s", got.Type)
	}
	if got.Host != "127.0.0.1:7890" {
		t.Fatalf("unexpected host: %s", got.Host)
	}
}

func TestCollectProxyFromScutilOutputPAC(t *testing.T) {
	out := `
<dictionary> {
  ProxyAutoConfigEnable : 1
  ProxyAutoConfigURLString : http://127.0.0.1:6152/proxy.pac
}`
	got := collectProxyFromScutilOutput(out)
	if !got.Enabled {
		t.Fatalf("expected proxy enabled")
	}
	if got.Type != "PAC" {
		t.Fatalf("expected PAC type, got %s", got.Type)
	}
	if got.Host != "127.0.0.1:6152" {
		t.Fatalf("unexpected host: %s", got.Host)
	}
}

func TestCollectProxyFromScutilOutputHTTPHostPort(t *testing.T) {
	out := `
<dictionary> {
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : 7890
}`
	got := collectProxyFromScutilOutput(out)
	if !got.Enabled {
		t.Fatalf("expected proxy enabled")
	}
	if got.Type != "HTTP" {
		t.Fatalf("expected HTTP type, got %s", got.Type)
	}
	if got.Host != "127.0.0.1:7890" {
		t.Fatalf("unexpected host: %s", got.Host)
	}
}

func TestCollectIOCountersSafelyRecoversPanic(t *testing.T) {
	original := ioCountersFunc
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		panic("boom")
	}
	t.Cleanup(func() { ioCountersFunc = original })

	stats, err := collectIOCountersSafely(true)
	if err == nil {
		t.Fatalf("expected error from panic recovery")
	}
	if !strings.Contains(err.Error(), "panic collecting network counters") {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(stats) != 0 {
		t.Fatalf("expected empty stats when panic recovered")
	}
}

func TestCollectIOCountersSafelyReturnsData(t *testing.T) {
	original := ioCountersFunc
	want := []gopsutilnet.IOCountersStat{
		{Name: "en0", BytesRecv: 1, BytesSent: 2},
	}
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		return want, nil
	}
	t.Cleanup(func() { ioCountersFunc = original })

	got, err := collectIOCountersSafely(true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 || got[0].Name != "en0" {
		t.Fatalf("unexpected stats: %+v", got)
	}
}
