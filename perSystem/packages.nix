{
  perSystem = { hsPkgs, ... }:
    let
      td  = hsPkgs.trace-dispatcher;
      htr = hsPkgs.hermod-trace-resources;
    in
    {
      packages.trace-dispatcher          = td.components.library;
      checks.trace-dispatcher-test       = td.components.tests.trace-dispatcher-test;
      packages.hermod-trace-resources    = htr.components.library;
      checks.hermod-trace-resources-test = htr.components.tests.trace-resources-test;
    };
}
