{
  description = "Homelab NixOS configurations";

  inputs = {
    # Keep Argo CD independent from the shared chart catalog so Renovate
    # updates its chart, CRDs, templates, and default image together.
    nixhelm-argocd = {
      url = "github:nix-community/nixhelm/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    nixhelm = {
      url = "github:farcaller/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
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
      # renovate: datasource=helm depName=argo-cd registryUrl=https://argoproj.github.io/argo-helm
      argoCdChartVersion = "10.3.3";
      argoCdChart =
        assert inputs.nixhelm-argocd.chartsMetadata.argoproj.argo-cd.version == argoCdChartVersion;
        inputs.nixhelm-argocd.chartsDerivations.${system}.argoproj.argo-cd;
      nixhelmCharts = inputs.nixhelm.chartsDerivations.${system};
      charts = nixhelmCharts // {
        argoproj = nixhelmCharts.argoproj // {
          argo-cd = argoCdChart;
        };
      };
    in
    blueprintOutputs
    // {
      nixidyEnvs.${system} = inputs.nixidy.lib.mkEnvs {
        inherit pkgs;

        inherit charts;

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
        ];
      };
    };
}
