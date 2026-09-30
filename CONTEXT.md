# Homelab

A single-node Kubernetes homelab and the laptop that runs it. It includes a health dashboard on the laptop's own console.

## Language

### Services and inventory

**Service catalog**:
The single list of services, keyed by stable service identity, that Glance, HTTP checks and the dashboard all derive from.
_Avoid_: inventory file, site list

**Endpoint**:
A catalog entry's human-facing URL and its internal HTTP check target. It is not necessarily an Argo application.
_Avoid_: site, monitor

**App**:
An Argo CD Application. An endpoint may map to a shared app, a differently named app or none, and some apps have no endpoint.
_Avoid_: deployment (for the Argo object)

### Health dashboard

**Signal**:
One observed problem: a failing HTTP check, an unhealthy/out-of-sync app, restarts or an active alert. Several signals may come from one underlying incident, so counts are always of signals.
_Avoid_: incident, issue, error count

**Coverage gap**:
A catalog endpoint or app that is expected but has no data. It withholds all-clear but is not a signal.
_Avoid_: missing signal, failure

**Source**:
One collector input (host, HTTP checks, Argo CD, alerts), with a freshness of waiting, current, stale (newest sample older than 3 minutes) or unavailable.
_Avoid_: feed, datasource

**Status**:
The dashboard's overall verdict: ATTENTION (at least one signal), UNKNOWN (no signals, but a source is not current or there is a coverage gap) or ALL CLEAR.
_Avoid_: health score, degraded (as a status)

**Attention row**:
One affected service in the attention slot, marked by its worst signal and ordered by tier, then catalog order.
_Avoid_: alert row, incident

**Recovery**:
A service whose signals cleared within the last 15 minutes. It is shown for information only and never affects the status.
_Avoid_: resolved incident
