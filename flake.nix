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
    in
    blueprintOutputs
    // {
      nixidyEnvs.${system} = inputs.nixidy.lib.mkEnvs {
        inherit pkgs;

        charts = inputs.nixhelm.chartsDerivations.${system};

        envs.homelab.modules = [
          ./kubernetes/homelab.nix
          ./kubernetes/longhorn.nix
          ./kubernetes/glance.nix
          ./kubernetes/glance-agent.nix
          ./kubernetes/immich.nix
        ];
      };
    };
}
