{ ... }:
{
  perSystem = { hsPkgs, pkgs, ... }:
    let
      # hermod-tracing-api has only named sublibraries (internal, public); all others have a
      # conventional top-level library.
      haddockDocs = [
        hsPkgs.trace-dispatcher.components.library.haddock.doc
        # Only the public sublibrary: internal is not a stable API and both sublibs
        # share the same pkgId, causing a collision in the output directory.
        hsPkgs.hermod-tracing-api.components.sublibs.public.haddock.doc
        hsPkgs.hermod-tracing-core.components.library.haddock.doc
        hsPkgs.hermod-tracing-prometheus.components.library.haddock.doc
        hsPkgs.hermod-recon-framework.components.library.haddock.doc
        hsPkgs.hermod-trace-resources.components.library.haddock.doc
      ];
    in
    {
      packages.haddocks = pkgs.runCommand "haddocks"
        { buildInputs = [ pkgs.haskell-nix.compiler.ghc967 ]; }
        ''
          mkdir -p $out

          interfaceArgs=""
          for doc in ${toString haddockDocs}; do
            htmlDir=$(find "$doc/share/doc" -name "html" -type d | head -1)
            pkgId=$(basename "$(dirname "$htmlDir")")
            # Search recursively: sublibraries place the .haddock file one level
            # deeper (html/<sublibname>/<sublibname>.haddock) rather than directly
            # in html/.
            ifaceFile=$(find "$htmlDir" -name "*.haddock" | head -1)
            ifaceDir=$(dirname "$ifaceFile")
            # Relative path from html/ to the directory containing the iface file;
            # empty for regular libraries, "sublibname" for sublibraries.
            relPath="''${ifaceDir#$htmlDir/}"

            mkdir -p "$out/$pkgId"
            cp -r "$htmlDir/." "$out/$pkgId/"

            if [ "$relPath" = "$ifaceDir" ] || [ -z "$relPath" ]; then
              interfaceArgs="$interfaceArgs --read-interface=$pkgId,$ifaceFile"
            else
              interfaceArgs="$interfaceArgs --read-interface=$pkgId/$relPath,$ifaceFile"
            fi
          done

          haddock --gen-index --gen-contents $interfaceArgs -o $out
        '';
    };
}
