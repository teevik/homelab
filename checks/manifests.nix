{ pkgs, flake, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  manifests = flake.nixidyEnvs.${system}.homelab.environmentPackage;
  schemas = import ../tests/kubernetes-schemas.nix { inherit pkgs; };
  k3sVersion = flake.nixosConfigurations.homelab.config.services.k3s.package.version;
  python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
in
assert pkgs.lib.assertMsg (
  pkgs.lib.versions.majorMinor k3sVersion == pkgs.lib.versions.majorMinor schemas.version
) "Refresh tests/kubernetes-schemas.nix for the new Kubernetes minor version";
pkgs.runCommand "homelab-manifests-check"
  {
    nativeBuildInputs = [
      python
      pkgs.kubeconform
      pkgs.ripgrep
    ];
  }
  ''
    # Diff both directions, including new and deleted files; no worktree mutation.
    diff -ru --exclude=.revision ${../manifests/homelab} ${manifests}
    # kubeconform does not traverse nixidy's directory symlinks.
    cp -rL ${manifests} rendered

    cp ${../scripts/validate-manifests.py} validate-manifests.py
    cp ${../scripts/test-manifests.py} test-manifests.py
    python3 test-manifests.py
    cp ${../scripts/build-images.py} build-images.py
    cp ${../scripts/test-image-builds.py} test-image-builds.py
    python3 test-image-builds.py
    python3 validate-manifests.py ${manifests} --policy ${../tests/manifest-policy.json}

    mkdir schemas
    mapfile -t crds < <(rg --files "$PWD/rendered" -g 'CustomResourceDefinition-*.yaml')
    (
      cd schemas
      FILENAME_FORMAT='{kind}-{fullgroup}-{version}' \
        python3 ${pkgs.kubeconform.src}/scripts/openapi2jsonschema.py "''${crds[@]}"
    )
    python3 - <<'PY'
    import json
    import runpy
    from pathlib import Path
    strict = runpy.run_path("${pkgs.kubeconform.src}/scripts/openapi2jsonschema.py")["additional_properties"]
    for source, name in [
        ("${schemas.crd}", "customresourcedefinition-apiextensions.k8s.io-v1.json"),
        ("${schemas.definitions}", "_definitions.json"),
    ]:
        Path("schemas", name).write_text(json.dumps(strict(json.loads(Path(source).read_text()))))
    PY
    kubeconform -strict -summary -kubernetes-version ${schemas.version} \
      -schema-location '${schemas.source}/{{ .ResourceKind }}{{ .KindSuffix }}.json' \
      -schema-location "$PWD/schemas/{{ .ResourceKind }}-{{ .Group }}-{{ .ResourceAPIVersion }}.json" \
      rendered
    touch "$out"
  ''
