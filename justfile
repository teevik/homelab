install TARGET-IP:
    # Run disko and install nixos
    nix run github:numtide/nixos-anywhere -- \
      --build-on remote \
      --phases kexec,disko,install \
      --generate-hardware-config nixos-generate-config ./hosts/homelab/hardware.nix \
      --flake '.#homelab' \
      root@{{ TARGET-IP }}

    # Copy sops age key for secret decryption
    ssh root@{{ TARGET-IP }} "mkdir -p /mnt/home/teevik/.config/sops/age"
    scp /home/teevik/.config/sops/age/keys.txt root@{{ TARGET-IP }}:/mnt/home/teevik/.config/sops/age/keys.txt
    ssh root@{{ TARGET-IP }} "chown -R 1000:100 /mnt/home/teevik"

deploy:
    nixos-rebuild switch --flake .#homelab --target-host homelab --sudo

apply:
    nixidy apply .#homelab

check-images:
    nixidy build .#homelab
    python3 ./scripts/check-images.py ./result
