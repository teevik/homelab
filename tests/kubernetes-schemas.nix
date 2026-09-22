{ pkgs }:
let
  baseUrl = "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/491f6d0bac338516572de67fbd5ec4c510f7e657/v1.35.7-local";
in
{
  version = "1.35.7";
  source = pkgs.fetchFromGitHub {
    owner = "yannh";
    repo = "kubernetes-json-schema";
    rev = "491f6d0bac338516572de67fbd5ec4c510f7e657";
    sparseCheckout = [ "v1.35.7-standalone-strict" ];
    rootDir = "v1.35.7-standalone-strict";
    hash = "sha256-fUZijoJ60vnRnY13VIqHpte4KpBw+c/FqCQIVzNMK78=";
  };
  # Recursive CRD schemas cannot be emitted as standalone schemas. Keep the
  # schema and its local references together instead of skipping CRDs.
  crd = pkgs.fetchurl {
    url = "${baseUrl}/customresourcedefinition-apiextensions-v1.json";
    hash = "sha256-leEO+BrnDlExhnleIdSycX+7704tTqwwhVec+qDVke0=";
  };
  definitions = pkgs.fetchurl {
    url = "${baseUrl}/_definitions.json";
    hash = "sha256-g5BZMgnAqn11nBS0+GCfL3seywENG5nPHOKWQ6FIcLs=";
  };
}
