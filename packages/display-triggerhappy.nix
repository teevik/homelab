{ pkgs, ... }:
# Triggerhappy normally forks commands, which can reorder rapid explicit actions.
# On our action-only device, execute each fixed request before reading the next.
pkgs.triggerhappy.overrideAttrs (old: {
  pname = "display-triggerhappy";
  postPatch = (old.postPatch or "") + ''
    substituteInPlace trigger.c \
      --replace-fail 'int pid = fork();' 'int pid = 0;' \
      --replace-fail 'exit(0);' 'return;'
  '';
})
