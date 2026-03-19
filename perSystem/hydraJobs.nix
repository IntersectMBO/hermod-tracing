{ inputs, ... }: {
  perSystem = { hsPkgs, pkgs, ... }:
    let
      td = hsPkgs.trace-dispatcher;
    in
    {
      legacyPackages.hydraJobs =
        pkgs.callPackages inputs.iohkNix.utils.ciJobsAggregates
          {
            ciJobs = {
              "trace-dispatcher:lib:trace-dispatcher" = td.components.library;
              "trace-dispatcher:test:trace-dispatcher-test" = td.components.tests.trace-dispatcher-test;
              revision = pkgs.writeText "revision" (inputs.self.rev or "dirty");
            };
          };
    };
}
