# Canonical, harness-agnostic agent knowledge, shared across every coding agent
# in this environment (Claude Code, Codex, opencode, Pi). Author skills, rules,
# instructions, and MCP servers ONCE here; each harness module maps them into its
# own native option layout. This is what carries our hard-earned Claude Code setup
# over to the other agents with no copy-paste drift.
#
# Imported as `import ../agentic/knowledge.nix { inherit pkgs inputs lib; }` from
# each consuming module (they already receive pkgs / inputs / lib).
{
  pkgs,
  inputs,
  lib ? pkgs.lib,
}:

rec {
  # Skills are SKILL.md directories. This exact attribute set is accepted as-is by
  # the `skills` option of programs.claude-code, programs.codex, and
  # programs.opencode (name -> directory / store path). Pi reads the same dirs via
  # `skillsDir`.
  skills = {
    changelog = ./skills/changelog;
    explain = ./skills/explain;
    # ASD-STE100 Simplified Technical English, from the pinned SimpleEnglish input.
    simple-english = "${inputs.simple-english}/skills/simple-english";
  };

  # A single directory with one subdirectory per skill, for tools (Pi) that want a
  # real directory path rather than an attribute set.
  skillsDir = pkgs.linkFarm "agent-skills" (
    lib.mapAttrsToList (name: path: { inherit name path; }) skills
  );

  # Global, tool-agnostic rule files. Only genuinely universal rules belong here;
  # repo-mechanics rules stay in each repo's own CLAUDE.md / AGENTS.md. Values are
  # paths, accepted directly by the `rules` option of programs.claude-code and
  # programs.codex.
  rules = {
    comments = ./rules/comments.md;
    brevity = ./rules/brevity.md;
    writing-mechanics = ./rules/writing-mechanics.md;
  };

  # The global rules concatenated into one string, for harnesses that read a
  # single AGENTS.md instead of per-rule files (Codex, opencode, Pi -> their
  # `context` / ~/.pi/AGENTS.md). These are the tools' GLOBAL config files, the
  # counterpart to Claude Code's ~/.claude/rules; a project's own AGENTS.md /
  # CLAUDE.md stays the downstream user's to set and takes precedence. Just the
  # rule bodies, no preamble. Claude Code consumes `rules` directly, not this.
  agentsMd = lib.concatMapStringsSep "\n" builtins.readFile (lib.attrValues rules);

  # Forgejo MCP server, single source of truth as primitives. Each harness inlines
  # these into its own MCP schema (the schemas differ per tool).
  forgejo = rec {
    bin = "${pkgs.forgejo-mcp}/bin/forgejo-mcp";
    url = "https://git.gutimore.net";
    tokenEnv = "FORGEJO_ACCESS_TOKEN";
    args = [
      "--transport"
      "stdio"
      "--url"
      url
    ];
  };
}
