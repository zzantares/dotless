local M = {}

-- null-ls sources are the explicit choice, so they win over a formatter
-- bundled in a real server (nixd, lua_ls) on the same buffer.
local function null_ls_attached(bufnr)
	local clients = vim.lsp.get_clients({
		bufnr = bufnr,
		method = "textDocument/formatting",
	})
	return vim.iter(clients):any(function(client)
		return client.name == "null-ls"
	end)
end

-- HLS on a cold cradle blows the 1s default
M.timeout_ms = 3000

-- Format on save with whatever client offers it: HLS (fourmolu) for Haskell,
-- null-ls for every source listed in dotless/plugins/none-ls.lua.
function M.setup(opts)
	opts = opts or {}
	local timeout_ms = opts.timeout_ms or M.timeout_ms
	local format_group = vim.api.nvim_create_augroup("LspFormatOnSave", {})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = format_group,
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client or not client:supports_method("textDocument/formatting") then
				return
			end

			-- One autocmd per buffer; it re-picks the client on every save
			if vim.b[args.buf].lsp_format_on_save then
				return
			end
			vim.b[args.buf].lsp_format_on_save = true

			vim.api.nvim_create_autocmd("BufWritePre", {
				group = format_group,
				buffer = args.buf,
				desc = "Format buffer with the attached LSP formatter",
				callback = function()
					local prefer_null_ls = null_ls_attached(args.buf)
					vim.lsp.buf.format({
						bufnr = args.buf,
						async = false,
						timeout_ms = timeout_ms,
						filter = function(c)
							return not prefer_null_ls or c.name == "null-ls"
						end,
					})
				end,
			})
		end,
	})
end

return M
