let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";


  pkgs = import nixpkgs { config = {}; overlays = [
    (final: prev: {
        ols = prev.ols.overrideAttrs (oldAttrs: {
           nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ pkgs.git ];
            installPhase = oldAttrs.installPhase + ''
              cp -r builtin $out/bin/
            '';
          });
        })
    ]; };

in

pkgs.mkShell.override { stdenv = pkgs.clangStdenv; }
{  
  packages = with pkgs; [
    libGL
    SDL2
    odin
    ols
    libcxx
  ];  
}
