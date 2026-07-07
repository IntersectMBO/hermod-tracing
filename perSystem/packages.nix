{
  perSystem = { hsPkgs, ... }:
    let
      tdo = hsPkgs.trace-dispatcher;
      tda = hsPkgs.hermod-tracing-api;
      td  = hsPkgs.hermod-tracing-core;
      tdp = hsPkgs.hermod-tracing-prometheus;
      hrf = hsPkgs.hermod-recon-framework;
      htr = hsPkgs.hermod-trace-resources;
    in
    {
      packages.trace-dispatcher               = tdo.components.library;
      checks.trace-dispatcher-test           = tdo.checks.trace-dispatcher-test;

      packages.hermod-tracing-api             = tda.components.sublibs.public;

      packages.hermod-tracing-core           = td.components.library;
      checks.hermod-tracing-core-test        = td.checks.hermod-tracing-core-test;

      packages.hermod-tracing-prometheus     = tdp.components.library;

      packages.hermod-recon                  = hrf.components.exes.hermod-recon;
      packages.hermod-recon-grep             = hrf.components.exes.hermod-recon-grep;
      checks.hermod-recon-test               = hrf.checks.hermod-recon-test;
      checks.hermod-recon-integration-test   = hrf.checks.hermod-recon-integration-test;

      packages.hermod-trace-resources        = htr.components.library;
      checks.hermod-trace-resources-test     = htr.checks.trace-resources-test;
    };
}
