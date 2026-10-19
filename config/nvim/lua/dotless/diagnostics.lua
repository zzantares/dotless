local M = {}

M.config = {
	virtual_text = true,
	signs = true,
	underline = true,
	update_in_insert = false,
	severity_sort = false,
}

function M.setup(opts)
	vim.diagnostic.config(vim.tbl_deep_extend("force", M.config, opts or {}))
end

return M
