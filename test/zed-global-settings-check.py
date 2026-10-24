# Asserts dotless's Zed base layer is JSONC that Zed can parse, and that it
# carries the expected keys. Zed ignores a file it cannot parse, silently.
import json
import re
import sys

src = open(sys.argv[1]).read()

# String-aware comment strip: a // inside a JSON string is data, not a comment.
out, i, n = [], 0, len(src)
while i < n:
    if src[i] == '"':
        j = i + 1
        while j < n:
            if src[j] == "\\":
                j += 2
                continue
            if src[j] == '"':
                break
            j += 1
        out.append(src[i : j + 1])
        i = j + 1
    elif src.startswith("//", i):
        i = src.find("\n", i)
        if i == -1:
            break
    elif src.startswith("/*", i):
        i = src.find("*/", i) + 2
    else:
        out.append(src[i])
        i += 1

cfg = json.loads(re.sub(r",(\s*[}\]])", r"\1", "".join(out)))

assert cfg["vim_mode"] is True, cfg.get("vim_mode")
assert cfg["theme"]["dark"] == "Modus Operandi Deuteranopia", cfg["theme"]
assert cfg["theme"]["light"] == "One Light", cfg["theme"]
assert cfg["theme"]["mode"] == "system", cfg["theme"]
assert cfg["ui_font_size"] == 16, cfg["ui_font_size"]
assert cfg["file_types"]["C"] == ["C", "H"], cfg["file_types"]
assert cfg["languages"]["C"]["format_on_save"] == "on", cfg["languages"]
assert cfg["vim"]["relative_line_numbers"] is True, cfg["vim"]

# Machine-specific settings belong in the consumer's settings.json.
assert "ssh_connections" not in cfg, "ssh_connections leaked into dotless"

# Comments are the reason for shipping JSONC rather than generated JSON.
assert "//" in src, "comments stripped from the shipped file"

print("global_settings.json: JSONC parsed, keys ok")
