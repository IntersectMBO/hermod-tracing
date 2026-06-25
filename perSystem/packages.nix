{
  perSystem = { hsPkgs, ... }:
    let
      tda = hsPkgs.hermod-tracing-api;
      td  = hsPkgs.trace-dispatcher;
      hrf = hsPkgs.hermod-recon-framework;
      htr = hsPkgs.hermod-trace-resources;
    in
    {
      packages.hermod-tracing-api             = tda.components.library;


      packages.trace-dispatcher              = td.components.library;
      checks.trace-dispatcher-test           = td.components.tests.trace-dispatcher-test;

      packages.hermod-recon                  = hrf.components.exes.hermod-recon;
      packages.hermod-recon-grep             = hrf.components.exes.hermod-recon-grep;
      checks.hermod-recon-test               = hrf.components.tests.hermod-recon-test;
      checks.hermod-recon-integration-test   = hrf.components.tests.hermod-recon-integration-test;

      packages.hermod-trace-resources        = htr.components.library;
      checks.hermod-trace-resources-test     = htr.components.tests.trace-resources-test;
    };
}
