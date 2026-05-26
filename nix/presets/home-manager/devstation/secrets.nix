{ config, lib, ... }:

{
  sops.secrets = {
    openrouter_api_key = { };
    github_auth_token = { };
  };

  # Only required when the Forgejo MCP server in the claude-code module is active
  sops.secrets.forgejo_mcp_token = lib.mkIf config.programs.claude-code.enable { };

  sops.templates = {
    env = {
      content = ''
        export GITHUB_TOKEN="${config.sops.placeholder.github_auth_token}";
        export OPENAI_API_KEY="${config.sops.placeholder.openrouter_api_key}"; # qwen-code specific
        export OPENROUTER_API_KEY="${config.sops.placeholder.openrouter_api_key}";
      '' + lib.optionalString config.programs.claude-code.enable ''
        export FORGEJO_ACCESS_TOKEN="${config.sops.placeholder.forgejo_mcp_token}";
      '';
    };
  };

  # Load the env secrets into the shell environment
  programs.zsh.initContent = lib.mkBefore ''
    # source externally supplied env vars
    if [[ -f "${config.sops.templates.env.path}" ]]; then
      source "${config.sops.templates.env.path}"
    fi
  '';
}
