{ applications ? { }, services ? import ./service-catalog.nix, ... }:
let
  ordered = builtins.sort (a: b: a.order < b.order) (
    builtins.attrValues (builtins.mapAttrs (id: service: {
      inherit id;
      statuses = [ 200 ];
      timeout = 3;
    } // service) services)
  );
  appNames = builtins.filter (name:
    name != "apps" && name != "__bootstrap" && (applications.${name}.enable or true)
  ) (builtins.attrNames applications);
in
assert builtins.all (s: s.timeout > 0 && builtins.isInt s.timeout && builtins.elem 200 s.statuses) ordered;
assert builtins.length ordered == builtins.length (builtins.attrNames (builtins.listToAttrs (map (s: { name = toString s.order; value = true; }) ordered)));
{
  dashboard = {
    version = 1;
    endpoints = map (s: { inherit (s) id name app; }) ordered;
    apps = appNames;
  };
  # Explicit configured namespace ownership; ambiguous namespaces are never guessed.
  namespaces = builtins.listToAttrs (map (name: {
    inherit name;
    value = applications.${name}.namespace;
  }) appNames);
  glance = map (s: {
    title = s.name;
    inherit (s) url icon;
    check-url = s.target;
    allow-insecure = false;
    timeout = "${toString s.timeout}s";
    alt-status-codes = builtins.filter (code: code != 200) s.statuses;
  }) ordered;
  blackbox.modules = builtins.listToAttrs (map (s: {
    name = s.id;
    value = {
      prober = "http";
      timeout = "${toString s.timeout}s";
      http = {
        method = "GET";
        valid_status_codes = s.statuses;
        follow_redirects = true;
        preferred_ip_protocol = "ip4";
        tls_config.insecure_skip_verify = false;
      };
    };
  }) ordered);
  probes = map (s: {
    apiVersion = "operator.victoriametrics.com/v1beta1";
    kind = "VMProbe";
    metadata = {
      name = "dashboard-${s.id}";
      namespace = "victoria-metrics";
      labels."homelab.teevik.dev/dashboard" = "true";
    };
    spec = {
      jobName = "dashboard-http";
      module = s.id;
      interval = "30s";
      scrapeTimeout = "${toString (s.timeout + 2)}s";
      vmProberSpec.url = "dashboard-blackbox.victoria-metrics.svc:9115";
      targets.staticConfig = {
        targets = [ s.target ];
        labels = { service_id = s.id; } // (
          if s.app == null then { } else { catalog_app = s.app; }
        );
      };
    };
  }) ordered;
}
