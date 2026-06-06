{
  config,
  lib,
  pkgs,
  ...
}:

{
  programs.claude-code = {
    enable = lib.mkDefault (
      builtins.elem pkgs.stdenv.hostPlatform.system pkgs.claude-code.meta.platforms
    );
    package = lib.mkDefault pkgs.claude-code;
    skills = ./skills;
    settings = {
      autoUpdates = false;
      env = {
        "DISABLE_AUTOUPDATER" = "1";
      };

      hooks = {
        # This is the hook that runs whenever a task is completed
        Stop = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = "~/.local/bin/claude-notify complete 'Claude - Task Completed'";
              }
            ];
          }
        ];

        # This is the hook that runs whenever user input is requested
        Notification = [
          {
            matcher = "";
            hooks = [
              # This will make Claude to issue a Tmux notification whenever it requires user attention
              # In our configuration Tmux is configured to display it in the status bar when it gets issued
              {
                type = "command";
                command = "tmux set-option @claude_attention 1";
              }
              {
                type = "command";
                command = "~/.local/bin/claude-notify message 'Claude - Needs Input'";
              }
            ];
          }
        ];
      };
    };

    # See the HomeManager module docs for extra options they all look very interesting
    # settings = {}; # settings.json
    # agents = {};
    # agentsDir = ./;
    # hooksDir = ./;
    # skills = {};
    mcpServers = {
      forgejo = {
        type = "stdio";
        command = "${pkgs.forgejo-mcp}/bin/forgejo-mcp";
        args = [
          "--transport"
          "stdio"
          "--url"
          "https://git.gutimore.net"
        ];
        env = {
          FORGEJO_ACCESS_TOKEN = "\${FORGEJO_ACCESS_TOKEN}";
        };
      };

      # github = {
      #   type = "remote";
      #   url = "https://api.githubcopilot.com/mcp/";
      #   headers = {
      #     Authorization = "Bearer {file:${config.sops.secrets.github_auth_token.path}}";
      #   };
      # };

      # memory = {
      #   command = [
      #     "podman"
      #     "run"
      #     "-i"
      #     "-v"
      #     "claude-memory:/app/dist"
      #     "--rm"
      #     "mcp/memory"
      #   ];
      #   type = "local";
      # };
    };
  };

  programs.opencode = {
    enable = lib.mkDefault true;
    package = pkgs.opencode;
    enableMcpIntegration = true;
    settings = {
      autoupdate = false;
      instructions = [ "CLAUDE.md" ]; # Compatibility with claude-code
      model = "anthropic/claude-opus-4-5";
      # github-agent = {
      #   description = "Handles github.com tasks";
      #   mode = "subagent";
      #   tools = {
      #     "github*" = true;
      #   };
      # };
    };
    # themes = {};
    # agents = {};
    # commands = {};
    # rules = {};
  };

  # programs.mcp = {
  #   enable = true;

  #   servers = {
  #     github = {
  #       type = "remote";
  #       url = "https://api.githubcopilot.com/mcp/";
  #       headers = {
  #         Authorization = "Bearer {file:${config.sops.secrets.github_auth_token.path}}";
  #       };
  #     };

  #     memory = {
  #       command = [
  #         "podman"
  #         "run"
  #         "-i"
  #         "-v"
  #         "claude-memory:/app/dist"
  #         "--rm"
  #         "mcp/memory"
  #       ];
  #       type = "local";
  #     };

  #   };
  # };
}
