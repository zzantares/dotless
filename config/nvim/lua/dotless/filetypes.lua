local M = {}

M.filetypes = {
	extension = {
		tofu = "opentofu",
	},
	pattern = {
		[".*.nomad.tftpl"] = "hcl",
	},
}

function M.setup(opts)
	vim.filetype.add(vim.tbl_deep_extend("force", M.filetypes, opts or {}))
end

return M
