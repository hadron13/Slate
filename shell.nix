let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
  pkgs = import nixpkgs { config = {}; overlays = []; };
in

pkgs.mkShell.override { stdenv = pkgs.clangStdenv; }
{  
  packages = with pkgs; [
    libGL
    SDL2
    odin
    ols
  ];  
}
