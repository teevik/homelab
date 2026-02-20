install TARGET-IP HOST:
  # Run disko and install nixos
  nix run github:numtide/nixos-anywhere -- \
    --build-on remote \
    --phases kexec,disko,install \
    --generate-hardware-config nixos-generate-config ./hosts/{{HOST}}/hardware.nix \
    --flake '.#{{HOST}}' \
    root@{{TARGET-IP}}

  # Copy ssh keys over
  # ssh teevik@{{TARGET-IP}} "mkdir -p /mnt/home/teevik/.ssh"
  # scp /home/teevik/.ssh/id_rsa teevik@{{TARGET-IP}}:/mnt/home/teevik/.ssh/id_rsa
  # scp /home/teevik/.ssh/id_rsa.pub teevik@{{TARGET-IP}}:/mnt/home/teevik/.ssh/id_rsa.pub

  # Copy sops age key for secret decryption
  ssh root@{{TARGET-IP}} "mkdir -p /mnt/home/teevik/.config/sops/age"
  scp /home/teevik/.config/sops/age/keys.txt root@{{TARGET-IP}}:/mnt/home/teevik/.config/sops/age/keys.txt
  ssh root@{{TARGET-IP}} "chown -R 1000:100 /mnt/home/teevik"

  # Reboot
  # ssh root@{{TARGET-IP}} "reboot"

deploy NAME:
  nixos-rebuild switch --flake .#{{NAME}} --target-host {{NAME}} --use-remote-sudo

[parallel]
deploy-all: (deploy "homelab-1") (deploy "homelab-2") (deploy "homelab-3")
