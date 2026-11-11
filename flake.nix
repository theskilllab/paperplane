{
  description = "Paperplane development tools";

  # The shell's Flutter comes from this pin, not from .fvmrc (which CI reads).
  # When bumping Flutter in .fvmrc, check what this nixpkgs ships. nixos-unstable
  # ships 3.47.4; .fvmrc pins 3.47.9. No channel ships 3.47.9 yet.
  # The shell has no Android SDK: CI builds the APK. It covers format, analyze and test.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      # No x86_64-darwin: nixpkgs 26.11 dropped Intel Macs.
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            flutter # bundles Dart
            git
            gitleaks
            jq
            which # the Flutter tool shells out to it
          ];
        };
      });
    };
}
