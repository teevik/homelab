{ pkgs }:
let
  baseUrl = "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/f7d855e49c34b039c9ef2196444910275e31e09e/v1.36.5-local";
in
{
  version = "1.36.5";
  source = pkgs.fetchFromGitHub {
    owner = "yannh";
    repo = "kubernetes-json-schema";
    rev = "f7d855e49c34b039c9ef2196444910275e31e09e";
    sparseCheckout = [ "v1.36.5-standalone-strict" ];
    rootDir = "v1.36.5-standalone-strict";
    hash = "sha256-WG2b2k2kuv2fRjsWDdg6uB3hjSXDjKPS4lktnU2wNmg=";
  };
  # Recursive CRD schemas cannot be emitted as standalone schemas. Keep the
  # schema and its local references together instead of skipping CRDs.
  crd = pkgs.fetchurl {
    url = "${baseUrl}/customresourcedefinition-apiextensions-v1.json";
    hash = "sha256-leEO+BrnDlExhnleIdSycX+7704tTqwwhVec+qDVke0=";
  };
  definitions = pkgs.fetchurl {
    url = "${baseUrl}/_definitions.json";
    hash = "sha256-qemM3GqwmYDyO16Yel8R0OwfyDgYfvuS80fM847Y/WU=";
  };
}
