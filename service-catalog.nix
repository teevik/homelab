# Pure shared service catalog. HTTP overrides belong here, never in consumers.
{
  glance = {
    name = "Glance";
    url = "http://glance";
    target = "http://glance.glance.svc";
    icon = "si:glance";
    app = "glance";
    order = 0;
  };
  longhorn = {
    name = "Longhorn";
    url = "http://longhorn";
    target = "http://longhorn-tailscale.longhorn-system.svc";
    icon = "auto-invert https://raw.githubusercontent.com/cncf/artwork/main/projects/longhorn/icon/black/longhorn-icon-black.svg";
    app = "longhorn";
    order = 1;
  };
  immich = {
    name = "Immich";
    url = "http://immich";
    target = "http://immich-tailscale.immich.svc";
    icon = "si:immich";
    app = "immich";
    order = 2;
  };
  grafana = {
    name = "Grafana";
    url = "http://grafana";
    target = "http://grafana-tailscale.victoria-metrics.svc";
    icon = "si:grafana";
    app = "victoria-metrics";
    order = 3;
  };
  nix-cache = {
    name = "Nix Cache";
    url = "http://grafana/d/nix-cache";
    target = "http://192.168.1.225:8501/nix-cache-info";
    icon = "si:nixos";
    app = null;
    order = 4;
  };
  argocd = {
    name = "ArgoCD";
    url = "http://argocd";
    target = "http://argocd-tailscale.argocd.svc";
    icon = "si:argo";
    app = "argocd";
    order = 5;
  };
  kodekamp = {
    name = "KodeKamp";
    url = "https://kodekamp.teevik.no";
    target = "http://kodekamp-web.kodekamp.svc:3000";
    icon = "si:codewars";
    app = "kodekamp";
    order = 6;
  };
  paperless-ngx = {
    name = "Paperless-ngx";
    url = "http://paperless";
    target = "http://paperless-tailscale.paperless-ngx.svc";
    icon = "si:paperlessngx";
    app = "paperless-ngx";
    order = 7;
  };
  bentopdf = {
    name = "BentoPDF";
    url = "http://bentopdf";
    target = "http://bentopdf.bentopdf.svc";
    icon = "si:files";
    app = "bentopdf";
    order = 8;
  };
  amp = {
    name = "AMP";
    url = "http://amp";
    target = "http://amp.amp.svc";
    icon = "mdi:gamepad-variant";
    app = "amp";
    order = 9;
  };
  twitchdropsminer = {
    name = "TwitchDropsMiner";
    url = "http://twitchdropsminer";
    target = "http://twitchdropsminer.twitchdropsminer.svc";
    icon = "si:twitch";
    app = "twitchdropsminer";
    order = 10;
  };
  ntfy = {
    name = "ntfy";
    url = "http://ntfy";
    target = "http://ntfy.ntfy.svc";
    icon = "si:ntfy";
    app = "ntfy";
    order = 11;
  };
  immich-share = {
    name = "Immich Share";
    url = "https://immich-share.tail84b6c.ts.net";
    target = "http://immich-public-proxy.immich.svc:3000";
    icon = "si:immich";
    app = "immich";
    order = 12;
  };
  changedetection = {
    name = "Changedetection";
    url = "http://changedetection";
    target = "http://changedetection-tailscale.changedetection.svc";
    icon = "di:changedetection-io";
    app = "changedetection";
    order = 13;
  };
  registry = {
    name = "Registry";
    url = "https://registry.tail84b6c.ts.net";
    target = "http://zot.registry.svc:5000/v2/";
    icon = "si:opencontainersinitiative";
    app = "registry";
    order = 14;
  };
  reclip = {
    name = "Reclip";
    url = "http://reclip";
    target = "http://reclip-tailscale.reclip.svc";
    icon = "mdi:download";
    app = "reclip";
    order = 15;
  };
}
