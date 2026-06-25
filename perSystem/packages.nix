{
  perSystem = { hsPkgs, ... }:
    let
      tda = hsPkgs.hermod-tracing-api;
      td  = hsPkgs.hermod-tracing-core;
      tdp = hsPkgs.hermod-tracing-prometheus;
      hrf = hsPkgs.hermod-recon-framework;
      htr = hsPkgs.hermod-trace-resources;
    in
    {
      packages.hermod-tracing-api             = tda.components.library;

      packages.hermod-tracing-core           = td.components.library;
      checks.hermod-tracing-core-test        = td.components.tests.hermod-tracing-core-test;

      packages.hermod-tracing-prometheus     = tdp.components.library;

      packages.hermod-recon                  = hrf.components.exes.hermod-recon;
      packages.hermod-recon-grep             = hrf.components.exes.hermod-recon-grep;
      checks.hermod-recon-test               = hrf.components.tests.hermod-recon-test;
      checks.hermod-recon-integration-test   = hrf.components.tests.hermod-recon-integration-test;

      packages.hermod-trace-resources        = htr.components.library;
      checks.hermod-trace-resources-test     = htr.components.tests.trace-resources-test;
    };
}
