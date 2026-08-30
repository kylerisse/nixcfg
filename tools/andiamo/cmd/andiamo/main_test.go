package main

import (
	"testing"

	"github.com/kylerisse/nixcfg/tools/andiamo/internal/nixcmd"
)

func TestShortEvalLine(t *testing.T) {
	const dir = "/home/me/src/nixcfg"
	cases := []struct{ in, want string }{
		{"evaluating file '«github:nixos/nixpkgs/f4f698677b11021a8f84f452e23ae9ef2427bec3?narHash=sha256-MrkfE5hF5xx4L/0h5NyJ3xQkKVftwSuKSkFSrvlTxGY%3D»/nixos/modules/config/console.nix'",
			"nixpkgs/nixos/modules/config/console.nix"},
		{"evaluating file '«github:socallinuxexpo/scale-signs/04f81f0a?narHash=sha256-x»/flake.nix'", "scale-signs/flake.nix"},
		{"evaluating file '«nix-internal»/derivation-internal.nix'", "nix-internal/derivation-internal.nix"},
		{"evaluating file '«flakes-internal»/call-flake.nix'", "flakes-internal/call-flake.nix"},
		{"evaluating file '«path:/home/me/src/other»/default.nix'", "other/default.nix"},
		{"evaluating file '/nix/store/abc123-source/nixos/modules/config/console.nix'", "nixos/modules/config/console.nix"},
		{"evaluating file '" + dir + "/modules/nix-common/default.nix'", "modules/nix-common/default.nix"},
		{"evaluating file '" + dir + "/flake.nix'", "flake.nix"},
		{"evaluating file '" + dir + "-other/flake.nix'", dir + "-other/flake.nix"},
		{"evaluating file '<nix/fetchurl.nix>'", "<nix/fetchurl.nix>"},
		{"copying '«github:nixos/nixpkgs/f4f6»/lib' to the store", "copying '«github:nixos/nixpkgs/f4f6»/lib' to the store"},
		{"warning: Git tree '/home/me/src/nixcfg' is dirty", "warning: Git tree '/home/me/src/nixcfg' is dirty"},
		{"trace:\tindented\x1b[31m red\x1b[0m", "trace: indented red"}, // colour off in tests
	}
	for _, c := range cases {
		if got := shortEvalLine(dir, c.in); got != c.want {
			t.Errorf("shortEvalLine(%q)\n got %q\nwant %q", c.in, got, c.want)
		}
	}
}

func TestBuildDetail(t *testing.T) {
	const (
		nginxDrv = "/nix/store/150zykpi9v1hhm87yf1y1b3ail40s36w-nginx-1.27.3.drv"
		linux    = "/nix/store/wl6xbyf0k5b14izm59rfh9rvdyjh4n68-linux-7.2.0"
	)
	member := map[string][]string{nginxDrv: {"qube", "gibson"}, linux: {"pi3"}}
	acts := []nixcmd.Activity{ // newest first
		{Type: nixcmd.ActCopyPath, Path: linux, Bytes: 12_400_000, BytesTotal: 45_000_000, Seq: 3},
		{Type: nixcmd.ActBuild, Path: nginxDrv, LastLine: "gcc\t-O2 \x1bfoo.c", Seq: 2},
		{Type: nixcmd.ActQueryPathInfo, Path: linux, Seq: 1},
	}
	totals := nixcmd.Totals{Built: 3, BuildsExpected: 12, Fetched: 41, FetchesExpected: 120}
	cases := map[string]string{
		"qube":   "building nginx-1.27.3 › gcc -O2 foo.c",
		"gibson": "building nginx-1.27.3 › gcc -O2 foo.c",
		"pi3":    "fetching linux-7.2.0 12.4/45.0 MB",
		"muir":   "waiting · 3/12 built · 41/120 fetched",
	}
	for row, want := range cases {
		if got := buildDetail(row, acts, member, totals); got != want {
			t.Errorf("buildDetail(%s) = %q, want %q", row, got, want)
		}
	}
	if got := buildDetail("muir", nil, member, nixcmd.Totals{}); got != "waiting" {
		t.Errorf("empty totals = %q", got)
	}
	if got := buildDetail("pi3", []nixcmd.Activity{{Type: nixcmd.ActSubstitute, Path: linux}}, member, totals); got != "fetching linux-7.2.0" {
		t.Errorf("substitute without bytes = %q", got)
	}
}
