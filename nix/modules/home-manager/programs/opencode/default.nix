{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  # Shared agent knowledge - the same SKILL.md dirs and global rules Claude Code
  # uses. See ../agentic/knowledge.nix.
  knowledge = import ../agentic/knowledge.nix { inherit pkgs inputs lib; };
in
{
  programs.opencode = {
    enable = lib.mkDefault true;
    package = pkgs.opencode;
    enableMcpIntegration = true;

    # Skills shared verbatim with Claude Code / Codex (opencode reads the same
    # SKILL.md format) -> ~/.config/opencode/skills/<name>/.
    skills = knowledge.skills;

    # opencode has no rules mechanism, so the shared preamble + global rule bodies
    # ride in `context`, rendered to ~/.config/opencode/AGENTS.md.
    context = knowledge.agentsMd;

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
  };
}
