{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  # Shared, harness-agnostic agent knowledge - the same skills and rules Claude
  # Code / Codex / opencode use. See ../agentic/knowledge.nix.
  knowledge = import ../agentic/knowledge.nix { inherit pkgs inputs lib; };
  jsonFormat = pkgs.formats.json { };

  # ~/.pi/agent/models.json. Hosted Qwen3.8-27B via OpenRouter, reusing the
  # OPENROUTER_API_KEY the devstation preset exports from sops. Pi resolves the
  # "$VAR" apiKey form at runtime. To self-host later, add an `ollama` provider
  # (baseUrl http://localhost:11434/v1) and pick its model with /model - no other
  # change needed.
  models = {
    providers.openrouter = {
      baseUrl = "https://openrouter.ai/api/v1";
      api = "openai-completions";
      apiKey = "$OPENROUTER_API_KEY";
      models = [
        { id = "qwen/qwen3.8-27b"; }
        { id = "qwen/qwen3-coder-next"; }
      ];
    };
  };

  # ~/.pi/agent/settings.json. Point Pi at the shared skills directory (the same
  # SKILL.md dirs the other agents load); Pi's `skills` takes directory paths.
  settings = {
    skills = [ "${knowledge.skillsDir}" ];
  };
in
{
  home.packages = [ pkgs.pi-coding-agent ];

  home.file = {
    ".pi/agent/models.json".source = jsonFormat.generate "pi-models.json" models;
    ".pi/agent/settings.json".source = jsonFormat.generate "pi-settings.json" settings;

    # Shared global rules + preamble. Pi reads AGENTS.md; keep the global copy in
    # its config root. (MCP wiring for Pi is a follow-up: its settings schema has
    # no documented mcp key yet - see the agentic epic.)
    ".pi/AGENTS.md".text = knowledge.agentsMd;
  };
}
