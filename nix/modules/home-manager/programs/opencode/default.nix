{
  lib,
  pkgs,
  ...
}:

{
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
}
