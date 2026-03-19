{
  perSystem = { hsPkgs, ... }:
    let
      td = hsPkgs.trace-dispatcher;
    in
    {
      packages.default = td.components.library;
      checks.trace-dispatcher-test = td.components.tests.trace-dispatcher-test;
    };
}
