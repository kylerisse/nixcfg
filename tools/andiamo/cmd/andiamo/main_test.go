package main

import "testing"

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
		{"trace:\tindented\x1b[31m red\x1b[0m", "trace: indented[31m red[0m"},
	}
	for _, c := range cases {
		if got := shortEvalLine(dir, c.in); got != c.want {
			t.Errorf("shortEvalLine(%q)\n got %q\nwant %q", c.in, got, c.want)
		}
	}
}
