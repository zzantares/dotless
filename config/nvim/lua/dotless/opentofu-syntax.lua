local M = {}

-- FIXME should be in ftplugin/opentofu.lua but it doesn't run it?
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "opentofu",
		callback = function()
			vim.opt_local.syntax = "terraform"
		end,
	})
end

return M
