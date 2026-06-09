{
  perSystem = { hsPkgs, ... }:
    let
      td  = hsPkgs.trace-dispatcher;
      hrf = hsPkgs.hermod-recon-framework;
    in
    {
      packages.trace-dispatcher          = td.components.library;
      checks.trace-dispatcher-test       = td.components.tests.trace-dispatcher-test;

      packages.hermod-recon              = hrf.components.exes.hermod-recon;
      packages.hermod-recon-grep         = hrf.components.exes.hermod-recon-grep;
      checks.hermod-recon-test           = hrf.components.tests.hermod-recon-test;
      checks.hermod-recon-integration-test = hrf.components.tests.hermod-recon-integration-test;
    };
}
