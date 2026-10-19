-- Shared helpers, mirroring doom's lisp/ztd.el
local M = {}

-- filetype -> package manifests, globs allowed. Add a language with a row here
M.package_files = {
	cabal = { "package.yaml", "*.cabal", "cabal.project", "stack.yaml" },
	haskell = { "package.yaml", "*.cabal", "cabal.project", "stack.yaml" },
	clojure = { "project.clj" },
	nix = { "flake.nix", "flake.lock", "shell.nix" },
}

local function matches(name, marker)
	if not marker:find("*", 1, true) then
		return name == marker
	end
	return name:match("^" .. vim.pesc(marker):gsub("%%%*", ".*") .. "$") ~= nil
end

-- nearest package file at or above the current buffer, the way
-- locate-dominating-file walks up. nil when there is nothing to find
function M.package_file()
	local markers = M.package_files[vim.bo.filetype]
	if markers == nil then
		vim.notify("No package files known for filetype " .. vim.bo.filetype, vim.log.levels.WARN)
		return nil
	end

	local name = vim.api.nvim_buf_get_name(0)
	local from = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()

	local found = vim.fs.find(function(entry)
		for _, marker in ipairs(markers) do
			if matches(entry, marker) then
				return true
			end
		end
		return false
	end, { path = from, upward = true, type = "file" })

	if found[1] == nil then
		vim.notify("No package file at or above " .. from, vim.log.levels.WARN)
		return nil
	end
	return found[1]
end

return M
