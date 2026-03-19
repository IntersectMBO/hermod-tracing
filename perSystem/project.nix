{ inputs, ... }:

{
  perSystem = { pkgs, lib, ... }:
    let
      project = pkgs.haskell-nix.cabalProject' ({ config, pkgs, ... }: {
        src = ./..;
        name = "trace-dispatcher";
        compiler-nix-name = lib.mkDefault "ghc967";

        inputMap = {
          "https://chap.intersectmbo.org/" = inputs.CHaP;
        };

        modules = [{
          packages.trace-dispatcher.ghcOptions = [ "-Werror" "-fno-ignore-asserts" ];
        }];
      });
    in
    {
      _module.args.hsPkgs = project.hsPkgs;
      _module.args.shellFor = args: project.shellFor args;
    };
}
