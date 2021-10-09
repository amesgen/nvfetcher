{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.flake-compat = {
    url = "github:edolstra/flake-compat";
    flake = false;
  };
  outputs = { self, nixpkgs, flake-utils, flake-compat, ... }:
    with flake-utils.lib;
    # FIXME: ghc currently doesn't build on aarch64-darwin
    eachSystem (nixpkgs.lib.remove "aarch64-darwin" defaultSystems) (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlay ];
          config = { allowBroken = true; };
        };
      in with pkgs; rec {
        defaultPackage = nvfetcher-bin;
        devShell = with haskell.lib;
          (addBuildTools (haskellPackages.nvfetcher) [
            haskell-language-server
            cabal-install
            nvchecker
            nix-prefetch
            cabal2nix # cd nix && cabal2nix ../. > default.nix && ..
          ]).envFunc { };
        packages.nvfetcher-lib = with haskell.lib;
          overrideCabal (haskellPackages.nvfetcher) (drv: {
            haddockFlags = [
              "--html-location='https://hackage.haskell.org/package/$pkg-$version/docs'"
            ];
          });
        packages.ghcWithNvfetcher = mkShell {
          buildInputs = [
            nix-prefetch
            nvchecker
            (haskellPackages.ghcWithPackages (p: [ p.nvfetcher ]))
          ];
        };
        hydraJobs = { inherit packages; };
      }) // {
        overlay = final: prev: {

          haskellPackages = prev.haskellPackages.override (old: {
            overrides = final.lib.composeExtensions (old.overrides or (_: _: {})) (hself: hsuper: {
              nvfetcher = with final.haskell.lib;
                generateOptparseApplicativeCompletion "nvfetcher"
                (overrideCabal (prev.haskellPackages.callPackage ./nix { })
                  (drv: {
                    # test needs network
                    doCheck = false;
                    buildTools = drv.buildTools or [ ] ++ [ final.makeWrapper ];
                    postInstall = with final;
                      drv.postInstall or "" + ''
                        wrapProgram $out/bin/nvfetcher \
                          --prefix PATH ":" "${
                            lib.makeBinPath [ nvchecker nix-prefetch ]
                          }"
                      '';
                  }));
            });
          });
          nvfetcher-bin = with final;
            haskell.lib.justStaticExecutables haskellPackages.nvfetcher;
        };
      };
}
