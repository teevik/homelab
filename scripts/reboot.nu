#!/usr/bin/env nu

const maintenance_drain_policy = "allow-if-replica-is-stopped"
const longhorn_namespace = "longhorn-system"

def print_command_output [result: record] {
  let stdout = ($result.stdout | str trim)
  let stderr = ($result.stderr | str trim)

  if $stdout != "" {
    print $stdout
  }

  if $stderr != "" {
    print $stderr
  }
}

def ssh_complete [host: string, args: list<string>] {
  ^ssh -o BatchMode=yes -o ConnectTimeout=5 $host ...$args | complete
}

def ssh_ok [host: string] {
  let result = (ssh_complete $host ["true"])
  $result.exit_code == 0
}

def remote_hostname [host: string] {
  let result = (ssh_complete $host ["hostname" "-s"])

  if $result.exit_code != 0 {
    return null
  }

  $result.stdout | str trim
}

def remote_boot_id [host: string] {
  let result = (ssh_complete $host ["cat" "/proc/sys/kernel/random/boot_id"])

  if $result.exit_code != 0 {
    return null
  }

  $result.stdout | str trim
}
def remote_k3s_node_ip [host: string] {
  let result = (ssh_complete $host [
    "sudo"
    "systemctl"
    "show"
    "k3s"
    "--property=ExecStart"
    "--value"
  ])

  if $result.exit_code != 0 {
    return null
  }

  let matches = ($result.stdout | parse -r '--node-ip(?:=|\s+)(?P<ip>[0-9.]+)')
  if ($matches | is-empty) {
    return null
  }

  $matches.0.ip
}

def remote_ipv4_addresses [host: string] {
  let result = (ssh_complete $host ["ip" "-j" "address" "show"])
  if $result.exit_code != 0 {
    return []
  }

  try {
    $result.stdout
    | from json
    | each {|interface|
        $interface.addr_info
        | where family == "inet"
        | get local
      }
    | flatten
  } catch {
    []
  }
}

def remote_kubectl_command [host: string, kubeconfig: string, args: list<string>] {
  [
    ssh
    -o
    BatchMode=yes
    $host
    sudo
    $"KUBECONFIG=($kubeconfig)"
    kubectl
  ] | append $args
}

def remote_kubectl_complete [host: string, kubeconfig: string, args: list<string>] {
  ^ssh -o BatchMode=yes -o ConnectTimeout=5 $host sudo $"KUBECONFIG=($kubeconfig)" kubectl ...$args | complete
}

def remote_kubectl_streamed [host: string, kubeconfig: string, args: list<string>] {
  try {
    ^ssh -o BatchMode=yes -o ConnectTimeout=5 $host sudo $"KUBECONFIG=($kubeconfig)" kubectl ...$args
    0
  } catch {
    $env.LAST_EXIT_CODE? | default 1
  }
}

def remote_kubectl_json [host: string, kubeconfig: string, args: list<string>] {
  let result = (remote_kubectl_complete $host $kubeconfig ($args | append [-o json]))

  if $result.exit_code != 0 {
    print_command_output $result
    error make {msg: $"Remote kubectl command failed: (($args | str join ' '))"}
  }

  try {
    $result.stdout | from json
  } catch {
    error make {msg: $"Remote kubectl returned invalid JSON: (($args | str join ' '))"}
  }
}

def kubectl_timeout [timeout: duration] {
  $"(($timeout / 1sec | into int))s"
}

def drain_args [node: string, timeout: duration] {
  [
    drain
    $node
    --ignore-daemonsets
    --delete-emptydir-data
    --grace-period=-1
    $"--timeout=(kubectl_timeout $timeout)"
  ]
}

def node_drain_policy [host: string, kubeconfig: string] {
  let result = (remote_kubectl_complete $host $kubeconfig [
    "-n"
    $longhorn_namespace
    get
    settings.longhorn.io
    node-drain-policy
    -o
    "jsonpath={.value}"
  ])

  if $result.exit_code != 0 {
    print_command_output $result
    error make {msg: "Could not read Longhorn node drain policy"}
  }

  $result.stdout | str trim
}

def set_node_drain_policy [host: string, kubeconfig: string, policy: string] {
  let patch = ({value: $policy} | to json -r)
  $patch | ^ssh -o BatchMode=yes -o ConnectTimeout=5 $host sudo $"KUBECONFIG=($kubeconfig)" kubectl -n $longhorn_namespace patch settings.longhorn.io node-drain-policy --type=merge "--patch-file=/dev/stdin" | complete
}

def uncordon [host: string, kubeconfig: string, node: string] {
  let result = (remote_kubectl_complete $host $kubeconfig [uncordon $node])
  print_command_output $result
  $result.exit_code
}

def uncordon_best_effort [host: string, kubeconfig: string, node: string] {
  let exit_code = try {
    uncordon $host $kubeconfig $node
  } catch {
    1
  }

  if $exit_code != 0 {
    print $"Could not uncordon ($node); run `kubectl uncordon ($node)` manually"
  }
}

def recover_before_reboot [
  host: string,
  kubeconfig: string,
  node: string,
  original_policy: string,
  message: string,
  exit_code: int,
] {
  print $message
  print $"Restoring Longhorn node drain policy to ($original_policy)"
  let restore = (set_node_drain_policy $host $kubeconfig $original_policy)
  if $restore.exit_code != 0 {
    print_command_output $restore
    print $"WARNING: restore node-drain-policy to ($original_policy) manually"
  }

  print $"Uncordoning ($node)"
  uncordon_best_effort $host $kubeconfig $node
  exit $exit_code
}

def wait_for_reboot [host: string, old_boot_id: string, timeout: duration] {
  let deadline = (date now) + $timeout

  loop {
    let current_boot_id = (remote_boot_id $host)

    if $current_boot_id != null and $current_boot_id != $old_boot_id {
      return $current_boot_id
    }

    if (date now) > $deadline {
      error make {msg: $"Timed out waiting for ($host) to reboot"}
    }

    sleep 5sec
  }
}

def wait_for_node_ready [host: string, kubeconfig: string, node: string, timeout: duration] {
  let deadline = (date now) + $timeout

  loop {
    let get_node = (remote_kubectl_complete $host $kubeconfig [get node $node])
    if $get_node.exit_code == 0 {
      break
    }

    if (date now) > $deadline {
      error make {msg: $"Timed out waiting for the Kubernetes API and node ($node)"}
    }

    sleep 5sec
  }

  let remaining = $deadline - (date now)
  if $remaining <= 0sec {
    error make {msg: $"Timed out waiting for Kubernetes node ($node) to become Ready"}
  }

  remote_kubectl_streamed $host $kubeconfig [
    wait
    --for=condition=Ready
    $"node/($node)"
    $"--timeout=(kubectl_timeout $remaining)"
  ]
}

def wait_for_volumes_detached [host: string, kubeconfig: string, timeout: duration] {
  let deadline = (date now) + $timeout

  loop {
    let volumes = (remote_kubectl_json $host $kubeconfig ["-n" $longhorn_namespace get volumes.longhorn.io]).items
    let attached = ($volumes | where {|volume|
      ($volume.status.state? | default "") != "detached"
    })

    if ($attached | is-empty) {
      return
    }

    print $"Waiting for (($attached | length)) Longhorn volume(s) to detach"

    if (date now) > $deadline {
      let names = ($attached | get metadata.name | str join ", ")
      error make {msg: $"Timed out waiting for Longhorn volumes to detach: ($names)"}
    }

    sleep 5sec
  }
}

def wait_for_attached_volumes [
  host: string,
  kubeconfig: string,
  volume_names: list<string>,
  timeout: duration,
] {
  if ($volume_names | is-empty) {
    return
  }

  let deadline = (date now) + $timeout

  loop {
    let volumes = (remote_kubectl_json $host $kubeconfig ["-n" $longhorn_namespace get volumes.longhorn.io]).items
    let current_names = ($volumes | each {|volume| $volume.metadata.name})
    let missing_names = ($volume_names | where {|name| $name not-in $current_names})
    let pending = ($volumes | where {|volume|
      ($volume.metadata.name in $volume_names) and (
        ($volume.status.state? | default "") != "attached" or
        ($volume.status.robustness? | default "") != "healthy"
      )
    })
    let pending_names = ($pending | each {|volume| $volume.metadata.name})
    let unresolved_names = ($missing_names | append $pending_names)

    if ($unresolved_names | is-empty) {
      return
    }

    print $"Waiting for (($unresolved_names | length))/($volume_names | length) Longhorn volume(s) to reattach healthy"

    if (date now) > $deadline {
      error make {msg: $"Timed out waiting for Longhorn volumes to recover: ($unresolved_names | str join ', ')"}
    }

    sleep 10sec
  }
}

def preflight [host: string, kubeconfig: string, node: string] {
  let hostname = (remote_hostname $host)
  if $hostname == null {
    error make {msg: $"Could not connect to ($host) over SSH"}
  }
  if $hostname != $node {
    error make {msg: $"SSH host ($host) is machine ($hostname), not Kubernetes node ($node)"}
  }

  let node_info = (remote_kubectl_json $host $kubeconfig [get node $node])
  let configured_node_ip = (remote_k3s_node_ip $host)
  if $configured_node_ip == null {
    error make {msg: "K3s has no explicit --node-ip; refusing to reboot a dual-NIC etcd node"}
  }
  let internal_addresses = ($node_info.status.addresses | where type == "InternalIP")
  if ($internal_addresses | is-empty) {
    error make {msg: $"Kubernetes node ($node) has no InternalIP"}
  }
  let node_internal_ip = $internal_addresses.0.address
  if $node_internal_ip != $configured_node_ip {
    error make {msg: $"Kubernetes InternalIP ($node_internal_ip) does not match configured K3s node IP ($configured_node_ip)"}
  }
  let host_addresses = (remote_ipv4_addresses $host)
  if $configured_node_ip not-in $host_addresses {
    error make {msg: $"Configured K3s node IP ($configured_node_ip) is not assigned to ($host)"}
  }

  if ($node_info.spec.unschedulable? | default false) {
    error make {msg: $"Kubernetes node ($node) is already cordoned; refusing to take ownership of its state"}
  }
  let node_ready = ($node_info.status.conditions | any {|condition|
    $condition.type == "Ready" and $condition.status == "True"
  })
  if not $node_ready {
    error make {msg: $"Kubernetes node ($node) is not Ready"}
  }

  let volumes = (remote_kubectl_json $host $kubeconfig ["-n" $longhorn_namespace get volumes.longhorn.io]).items
  if ($volumes | is-empty) {
    error make {msg: "No Longhorn volumes found"}
  }
  let unhealthy = ($volumes | where {|volume|
    ($volume.status.robustness? | default "") != "healthy"
  })
  if not ($unhealthy | is-empty) {
    let names = ($unhealthy | get metadata.name | str join ", ")
    error make {msg: $"Longhorn volumes are not healthy: ($names)"}
  }

  let backup_target = (remote_kubectl_json $host $kubeconfig [
    "-n"
    $longhorn_namespace
    get
    backuptargets.longhorn.io
    default
  ])
  if not ($backup_target.status.available? | default false) {
    error make {msg: "Longhorn backup target `default` is unavailable"}
  }

  let system_backups = (remote_kubectl_json $host $kubeconfig ["-n" $longhorn_namespace get systembackups.longhorn.io]).items
  let ready_system_backups = ($system_backups | where {|backup|
    ($backup.status.state? | default "") == "Ready"
  })
  let active_system_backups = ($system_backups | where {|backup|
    ($backup.status.state? | default "") not-in ["Ready" "Error"]
  })
  if not ($active_system_backups | is-empty) {
    error make {msg: $"($active_system_backups | length) Longhorn SystemBackup operation(s) are still active"}
  }
  if ($ready_system_backups | is-empty) {
    error make {msg: "No Ready Longhorn SystemBackup exists"}
  }

  let backups = (remote_kubectl_json $host $kubeconfig ["-n" $longhorn_namespace get backups.longhorn.io]).items
  let active_backups = ($backups | where {|backup|
    ($backup.status.state? | default "") not-in ["Completed" "Error"]
  })
  if not ($active_backups | is-empty) {
    error make {msg: $"($active_backups | length) Longhorn volume backup(s) are still active"}
  }

  let policy = (node_drain_policy $host $kubeconfig)
  let attached_volumes = ($volumes | where {|volume|
    ($volume.status.state? | default "") == "attached"
  } | get metadata.name)

  print $"Preflight passed: ($volumes | length) healthy volumes, ($attached_volumes | length) attached"
  print $"Ready SystemBackups: ($ready_system_backups | length); backup target: available"
  print $"Longhorn node drain policy: ($policy)"

  {
    drain_policy: $policy
    attached_volumes: $attached_volumes
  }
}

def main [
  node: string = "homelab" # Kubernetes node name to drain and uncordon
  --host: string = "homelab" # SSH host to reboot
  --kubeconfig: string = "/etc/rancher/k3s/k3s.yaml" # Kubeconfig path on the SSH host
  --drain-timeout: duration = 30min # Maximum time allowed for kubectl drain and volume detachment
  --reboot-timeout: duration = 10min # Maximum time allowed for the host to return with a new boot id
  --ready-timeout: duration = 10min # Maximum time allowed for the Kubernetes node to become Ready
  --workload-timeout: duration = 20min # Maximum time allowed for previously attached volumes to recover
  --yes # Skip the interactive destructive-action confirmation
  --dry-run # Run read-only preflight checks and print the planned drain command
] {
  print $"Reading current boot id from ($host)"
  let old_boot_id = (remote_boot_id $host)
  if $old_boot_id == null {
    error make {msg: $"Could not read boot id from ($host) over SSH"}
  }

  print "Running reboot safety preflight"
  let state = (preflight $host $kubeconfig $node)
  let args = (drain_args $node $drain_timeout)

  if $dry_run {
    print $"Would temporarily set node-drain-policy=($maintenance_drain_policy)"
    print (remote_kubectl_command $host $kubeconfig $args | str join " ")
    print $"Would restore node-drain-policy=($state.drain_policy), reboot ($host), wait for recovery, and uncordon ($node)"
    return
  }

  if not $yes {
    let answer = (input $"Drain all workloads and reboot ($host)? This causes full-cluster downtime. [y/N] " | str lowercase)
    if $answer not-in ["y" "yes"] {
      print "Cancelled without changing the cluster"
      return
    }
  }

  print $"Temporarily setting Longhorn node drain policy to ($maintenance_drain_policy)"
  let set_policy = (set_node_drain_policy $host $kubeconfig $maintenance_drain_policy)
  if $set_policy.exit_code != 0 {
    print_command_output $set_policy
    error make {msg: "Failed to set maintenance node drain policy; host was not touched"}
  }

  print $"Draining Kubernetes node ($node)"
  let drain_exit_code = (remote_kubectl_streamed $host $kubeconfig $args)
  if $drain_exit_code != 0 {
    recover_before_reboot $host $kubeconfig $node $state.drain_policy $"Drain failed; leaving ($host) untouched" $drain_exit_code
  }

  try {
    wait_for_volumes_detached $host $kubeconfig $drain_timeout
  } catch {|err|
    recover_before_reboot $host $kubeconfig $node $state.drain_policy $"($err.msg); leaving ($host) untouched" 1
  }

  print $"Restoring Longhorn node drain policy to ($state.drain_policy) before reboot"
  let restore_policy = (set_node_drain_policy $host $kubeconfig $state.drain_policy)
  if $restore_policy.exit_code != 0 {
    print_command_output $restore_policy
    recover_before_reboot $host $kubeconfig $node $state.drain_policy "Could not restore node drain policy; leaving host untouched" $restore_policy.exit_code
  }

  print $"Rebooting ($host)"
  let reboot = (^ssh -o BatchMode=yes $host sudo systemctl reboot --no-block | complete)
  if $reboot.exit_code != 0 {
    print_command_output $reboot
    print "Reboot command returned non-zero; verifying the boot id before taking recovery action"
  }

  print $"Waiting for ($host) to return with a new boot id"
  let new_boot_id = try {
    wait_for_reboot $host $old_boot_id $reboot_timeout
  } catch {|err|
    print $err.msg
    if (ssh_ok $host) {
      print $"Host is reachable; uncordoning ($node)"
      uncordon_best_effort $host $kubeconfig $node
    } else {
      print $"Host is unreachable; ($node) remains cordoned for manual recovery"
    }
    exit 1
  }
  print $"Host rebooted: ($old_boot_id) -> ($new_boot_id)"

  print $"Waiting for Kubernetes node ($node) to become Ready"
  let ready_exit_code = try {
    wait_for_node_ready $host $kubeconfig $node $ready_timeout
  } catch {|err|
    print $err.msg
    1
  }
  if $ready_exit_code != 0 {
    print $"Node did not become Ready; leaving ($node) cordoned for manual recovery"
    exit $ready_exit_code
  }

  print $"Uncordoning ($node)"
  let uncordon_exit_code = (uncordon $host $kubeconfig $node)
  if $uncordon_exit_code != 0 {
    exit $uncordon_exit_code
  }

  print "Waiting for previously attached Longhorn volumes to recover"
  try {
    wait_for_attached_volumes $host $kubeconfig $state.attached_volumes $workload_timeout
  } catch {|err|
    print $err.msg
    exit 1
  }

  print "Reboot completed successfully"
  remote_kubectl_streamed $host $kubeconfig [get pods -A] | ignore
  remote_kubectl_streamed $host $kubeconfig ["-n" $longhorn_namespace get volumes.longhorn.io] | ignore
  remote_kubectl_streamed $host $kubeconfig ["-n" $longhorn_namespace get instancemanagers.longhorn.io] | ignore
}
