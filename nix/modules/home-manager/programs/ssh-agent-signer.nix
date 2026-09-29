{
  pkgs,
  lib,
  identityFile,
}:

# Shared by the git and jujutsu modules: both sign with the same SSH key and
# hit the same agent problem.
#
# We need a custom script to add the key to the agent when signing a commit
# because AddKeysToAgent in ssh config is not honored when signing (it's not a
# connection attempt)
pkgs.writeShellScriptBin "ssh-agent-signer" ''
  #!/usr/bin/env bash
  # Check if the signing key is already in the agent.
  # Uses ssh-add -l rather than -T: gpg-agent does not implement -T, causing
  # it to fall through to `ssh-add <pubkey>` which then fails with
  # "error in libcrypto: unsupported" (you cannot add a public key to an agent).
  fingerprint=$(ssh-keygen -lf "${identityFile}" 2>/dev/null | awk '{print $2}')
  ssh-add -l 2>/dev/null | grep -qF "$fingerprint" \
    || ssh-add "${lib.removeSuffix ".pub" identityFile}" 2>/dev/null \
    || true
  exec ssh-keygen "$@"
''
