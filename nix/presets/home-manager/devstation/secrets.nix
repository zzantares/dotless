{ config, lib, ... }:

let
  # Agents whose Forgejo MCP needs the token. claude-code's MCP wraps its binary
  # (dies when package is null), so gate on that; Codex ships its own binary.
  usesForgejoMcp = config.programs.claude-code.package != null || config.programs.codex.enable;
in
{
  # opencode (OpenRouter provider) + pi
  sops.secrets.openrouter_api_key = lib.mkIf config.programs.opencode.enable { };

  # GitHub API access alongside AI tooling
  sops.secrets.github_auth_token = lib.mkIf config.programs.opencode.enable { };

  # Native OpenAI key for Codex. Add it with `sops secrets/<profile>/secrets.yaml`.
  sops.secrets.openai_api_key = lib.mkIf config.programs.codex.enable { };

  sops.secrets.forgejo_mcp_token = lib.mkIf usesForgejoMcp { };

  sops.templates.env.content =
    lib.optionalString config.programs.opencode.enable ''
      export GITHUB_TOKEN="${config.sops.placeholder.github_auth_token}";
      export OPENROUTER_API_KEY="${config.sops.placeholder.openrouter_api_key}"; # opencode, pi
    ''
    + lib.optionalString config.programs.codex.enable ''
      export OPENAI_API_KEY="${config.sops.placeholder.openai_api_key}"; # Codex
    ''
    + lib.optionalString usesForgejoMcp ''
      export FORGEJO_ACCESS_TOKEN="${config.sops.placeholder.forgejo_mcp_token}";
    '';

  # Load the env secrets into the shell environment
  programs.zsh.initContent = lib.mkBefore ''
    # source externally supplied env vars
    if [[ -f "${config.sops.templates.env.path}" ]]; then
      source "${config.sops.templates.env.path}"
    fi
  '';
}
