{
  description = "Homelab NixOS configurations";

  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    blueprint = {
      url = "github:numtide/blueprint";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # KodeKamp source, pinned here so the cluster builds its images from an
    # exact commit (kubernetes/kodekamp.nix). Renovate bumps it.
    kodekamp = {
      url = "github:teevik/KodeKamp";
      flake = false;
    };

  };

  outputs =
    inputs:
    let
      system = "x86_64-linux";

      blueprintOutputs = inputs.blueprint {
        inherit inputs;
        systems = [ system ];
      };

      pkgs = inputs.nixpkgs.legacyPackages.${system};
      chartTree = inputs.nixidy.packages.${system}.mkChartAttrs ./charts;
      updateCharts = inputs.nixidy.packages.${system}.mkChartsUpdateScript chartTree;

    in
    blueprintOutputs
    // {
      apps.${system}.updateCharts = {
        type = "app";
        program = pkgs.lib.getExe updateCharts;
      };

      nixidyEnvs.${system} = inputs.nixidy.lib.mkEnvs {
        inherit pkgs;

        envs.homelab.modules = [
          ./kubernetes/homelab.nix
          ./kubernetes/argocd.nix
          ./kubernetes/longhorn.nix
          ./kubernetes/glance.nix
          ./kubernetes/glance-agent.nix
          ./kubernetes/immich.nix
          ./kubernetes/kodekamp.nix
          ./kubernetes/cloudflare-tunnel.nix
          ./kubernetes/victoriametrics.nix
          ./kubernetes/paperless-ngx.nix
          ./kubernetes/bentopdf.nix
          ./kubernetes/crafty.nix
          ./kubernetes/twitchdropsminer.nix
          ./kubernetes/kavita.nix
          ./kubernetes/amd-device-plugin.nix
          ./kubernetes/ntfy.nix
          ./kubernetes/changedetection.nix
          ./kubernetes/registry.nix
          { _module.args.kodekampSrc = inputs.kodekamp; }
        ];
      };
    };
}
