{ pkgs, inputs, ... }:
inputs.runner-nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.github-runner.overrideAttrs
  (old: {
    patches = old.patches ++ [ ../scripts/runner/guard.patch ];
    # Stock JobExtension tests deliberately use anonymous jobs. The policy tests
    # below exercise this fork's authentication boundary instead.
    dotnetTestFilters = (old.dotnetTestFilters or [ ]) ++ [
      "FullyQualifiedName!~GitHub.Runner.Common.Tests.Worker.JobExtensionL0"
    ];
    postPatch = old.postPatch + ''
      cp ${../scripts/runner/HomelabJobPolicy.cs} src/Runner.Worker/HomelabJobPolicy.cs
      cp ${../scripts/runner/HomelabJobPolicyL0.cs} src/Test/L0/Worker/HomelabJobPolicyL0.cs
    '';
  })
