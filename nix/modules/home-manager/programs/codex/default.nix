{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  # Shared, harness-agnostic agent knowledge - the same skills, rules, and MCP
  # server Claude Code uses. See ../agentic/knowledge.nix.
  knowledge = import ../agentic/knowledge.nix { inherit pkgs inputs lib; };
in
{
  programs.codex = {
    enable = lib.mkDefault true;
    package = lib.mkDefault pkgs.codex;

    # Skills shared verbatim with Claude Code / opencode (same SKILL.md format)
    # -> $CODEX_HOME/skills/<name>/.
    skills = knowledge.skills;

    # Global rules via AGENTS.md (Codex reads $CODEX_HOME/AGENTS.md). One mechanism,
    # so the rule set is not duplicated into a separate rules/ tree.
    context = knowledge.agentsMd;

    # config.toml. Native OpenAI: Codex uses its built-in `openai` provider and
    # reads OPENAI_API_KEY (exported from sops in the devstation preset). The model
    # is intentionally left unpinned so Codex tracks its own current default; pin it
    # here (e.g. model = "gpt-5.6";) if you want a fixed one.
    settings = {
      # Forgejo MCP, the same server Claude Code uses. No `env` block: the
      # forgejo-mcp child inherits FORGEJO_ACCESS_TOKEN from Codex's environment,
      # which the sops-sourced shell exports.
      mcp_servers.forgejo = {
        command = knowledge.forgejo.bin;
        args = knowledge.forgejo.args;
      };
    };
  };
}
