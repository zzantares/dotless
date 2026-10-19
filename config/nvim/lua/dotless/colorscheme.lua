local M = {}

M.name = "minimum"

function M.setup(opts)
	opts = opts or {}
	vim.cmd.colorscheme(opts.name or M.name)
end

return M
