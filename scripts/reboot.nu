#!/usr/bin/env nu

const longhorn_exclude_selector = "app!=csi-attacher,app!=csi-provisioner,longhorn.io/component!=instance-manager,app!=longhorn-admission-webhook,app!=longhorn-conversion-webhook,app!=longhorn-driver-deployer,app!=operator"
const longhorn_webhook_validator = "longhorn-webhook-validator"

def ssh_ok [host: string] {
  let result = (^ssh -o BatchMode=yes -o ConnectTimeout=5 $host true | complete)
  $result.exit_code == 0
}

def remote_boot_id [host: string] {
  let result = (^ssh -o BatchMode=yes -o ConnectTimeout=5 $host cat /proc/sys/kernel/random/boot_id | complete)

  if $result.exit_code != 0 {
    return null
  }

  $result.stdout | str trim
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
    ^ssh -o BatchMode=yes $host sudo $"KUBECONFIG=($kubeconfig)" kubectl ...$args
    0
  } catch {
    $env.LAST_EXIT_CODE? | default 1
  }
}

def wait_for_reboot [host: string, old_boot_id: string, timeout: duration] {
  let deadline = (date now) + $timeout
  mut saw_unreachable = false

  loop {
    let current_boot_id = (remote_boot_id $host)

    if $current_boot_id == null {
      $saw_unreachable = true
    } else if $current_boot_id != $old_boot_id {
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
      error make {msg: $"Timed out waiting for Kubernetes node ($node) to exist"}
    }

    sleep 5sec
  }

  remote_kubectl_streamed $host $kubeconfig [wait --for=condition=Ready $"node/($node)" $"--timeout=(kubectl_timeout $timeout)"]
}

def uncordon_best_effort [host: string, kubeconfig: string, node: string] {
  remote_kubectl_complete $host $kubeconfig [uncordon $node] | ignore
}

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

def longhorn_webhook_blocked [result: record] {
  let output = $"($result.stdout)\n($result.stderr)"
  ($output | str contains "validator.longhorn.io") or ($output | str contains "longhorn-admission-webhook")
}

def longhorn_webhook_failure_policy [host: string, kubeconfig: string] {
  let result = (remote_kubectl_complete $host $kubeconfig [get validatingwebhookconfiguration $longhorn_webhook_validator -o "jsonpath={.webhooks[0].failurePolicy}"])

  if $result.exit_code != 0 {
    return "Fail"
  }

  let policy = ($result.stdout | str trim)
  if $policy == "" {
    "Fail"
  } else {
    $policy
  }
}

def set_longhorn_webhook_failure_policy [host: string, kubeconfig: string, policy: string] {
  let patch = $"[{\"op\":\"replace\",\"path\":\"/webhooks/0/failurePolicy\",\"value\":\"($policy)\"}]"
  remote_kubectl_complete $host $kubeconfig [patch validatingwebhookconfiguration $longhorn_webhook_validator --type=json --patch $patch]
}

def uncordon [host: string, kubeconfig: string, node: string] {
  let result = (remote_kubectl_complete $host $kubeconfig [uncordon $node])

  if $result.exit_code == 0 {
    print_command_output $result
    return 0
  }

  print_command_output $result

  if not (longhorn_webhook_blocked $result) {
    return $result.exit_code
  }

  print "Longhorn validating webhook is not ready; temporarily setting failurePolicy=Ignore for uncordon"
  let previous_policy = (longhorn_webhook_failure_policy $host $kubeconfig)
  let ignore_result = (set_longhorn_webhook_failure_policy $host $kubeconfig Ignore)

  if $ignore_result.exit_code != 0 {
    print_command_output $ignore_result
    return $ignore_result.exit_code
  }

  let retry = (remote_kubectl_complete $host $kubeconfig [uncordon $node])
  let restore_result = (set_longhorn_webhook_failure_policy $host $kubeconfig $previous_policy)

  if $restore_result.exit_code != 0 {
    print "Failed to restore Longhorn validating webhook failurePolicy; restore it manually"
    print_command_output $restore_result
  }

  print_command_output $retry
  $retry.exit_code
}

def print_node_pods [host: string, kubeconfig: string, node: string] {
  remote_kubectl_streamed $host $kubeconfig [get pods -A --field-selector $"spec.nodeName=($node)" -o wide] | ignore
}

def finish_with_uncordon [host: string, kubeconfig: string, node: string, msg: string, exit_code: int] {
  print $msg
  uncordon_best_effort $host $kubeconfig $node
  exit $exit_code
}

def kubectl_timeout [timeout: duration] {
  $"(($timeout / 1sec | into int))s"
}

def drain_args [node: string, timeout: duration, force_delete_pods: bool] {
  let args = [
    drain
    $node
    --ignore-daemonsets
    --delete-emptydir-data
    --force
    --grace-period=-1
    $"--timeout=(kubectl_timeout $timeout)"
    $"--pod-selector=($longhorn_exclude_selector)"
  ]

  if $force_delete_pods {
    $args | append "--disable-eviction"
  } else {
    $args
  }
}

def main [
  node: string = "homelab" # Kubernetes node name to drain and uncordon
  --host: string = "homelab" # SSH host to reboot
  --kubeconfig: string = "/etc/rancher/k3s/k3s.yaml" # Kubeconfig path on the SSH host
  --drain-timeout: duration = 15min # Maximum time allowed for kubectl drain
  --reboot-timeout: duration = 10min # Maximum time allowed for the host to return with a new boot id
  --ready-timeout: duration = 10min # Maximum time allowed for the Kubernetes node to become Ready
  --force-delete-pods # Bypass PodDisruptionBudgets by deleting pods instead of using evictions
  --dry-run # Print the drain command and exit without changing anything
] {
  let drain_args = (drain_args $node $drain_timeout $force_delete_pods)

  if $dry_run {
    print (remote_kubectl_command $host $kubeconfig $drain_args | str join " ")
    return
  }

  print $"Reading current boot id from ($host)"
  let old_boot_id = (remote_boot_id $host)

  if $old_boot_id == null {
    error make {msg: $"Could not read boot id from ($host) over SSH"}
  }

  print $"Draining Kubernetes node ($node)"
  if $force_delete_pods {
    print "Bypassing pod evictions with --disable-eviction; this ignores PodDisruptionBudgets"
  }
  # TODO: When GTNH is live, run `save-all flush` through RCON before draining.
  let drain_exit_code = (remote_kubectl_streamed $host $kubeconfig $drain_args)

  if $drain_exit_code != 0 {
    print $"Pods still scheduled on ($node):"
    print_node_pods $host $kubeconfig $node
    finish_with_uncordon $host $kubeconfig $node $"Drain failed; uncordoning ($node) and leaving host untouched" $drain_exit_code
  }

  print $"Rebooting ($host)"
  let reboot = (^ssh -o BatchMode=yes $host sudo systemctl reboot --no-block | complete)

  if $reboot.exit_code != 0 and (ssh_ok $host) {
    print $reboot.stdout
    print $reboot.stderr
    finish_with_uncordon $host $kubeconfig $node $"Reboot command failed before the host went away; uncordoning ($node)" $reboot.exit_code
  }

  print $"Waiting for ($host) to return with a new boot id"
  let new_boot_id = try {
    wait_for_reboot $host $old_boot_id $reboot_timeout
  } catch {|err|
    finish_with_uncordon $host $kubeconfig $node $"($err.msg); uncordoning ($node)" 1
  }
  print $"Host rebooted: ($old_boot_id) -> ($new_boot_id)"

  print $"Waiting for Kubernetes node ($node) to become Ready"
  let ready_exit_code = (wait_for_node_ready $host $kubeconfig $node $ready_timeout)
  if $ready_exit_code != 0 {
    finish_with_uncordon $host $kubeconfig $node $"Node did not become Ready; uncordoning ($node) before exiting" $ready_exit_code
  }

  print $"Uncordoning ($node)"
  let uncordon_exit_code = (uncordon $host $kubeconfig $node)
  if $uncordon_exit_code != 0 {
    exit $uncordon_exit_code
  }

  remote_kubectl_streamed $host $kubeconfig [get pods -A] | ignore
}
