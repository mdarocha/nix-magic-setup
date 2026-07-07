{
  description = "nix-magic-setup CI fixture flake (used to exercise the action end-to-end)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          # Marker variable the E2E workflow asserts on, to prove the
          # .envrc -> direnv -> $GITHUB_ENV export chain worked on a real runner.
          NIX_MAGIC_SETUP_E2E = "ok";
        };
      });
    };
}
