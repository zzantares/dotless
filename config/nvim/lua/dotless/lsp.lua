local M = {}

-- Enabling a server makes nvim source `lsp/<name>.lua` from every runtimepath
-- entry and merge them, later entries winning. dotless ships its own under
-- `lsp/`, nvim-lspconfig ships the base ones.
-- See: https://dev.to/vonheikemen/a-guide-on-neovims-lsp-client-mn0
M.servers = {
	"lua_ls",
	"jsonls",
	"tofu_ls",
	"nixd",
	"bashls",
}

function M.setup(opts)
	opts = opts or {}

	for _, server in ipairs(opts.servers or M.servers) do
		vim.lsp.enable(server)
	end
end

return M
