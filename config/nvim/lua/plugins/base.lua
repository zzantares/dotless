-- TODO ideally we have a single plugin per file but rn I'll just use base.lua to cram lots of plugins
--   if for any reason some plugin configuration takes a lot of real-state then consider creating a
--   *.lua file for it in this directory, it will automatically be added to neovim's runtimepath.
return {
    {
        -- Plugin manager everyone loves but that changes my theme settings annoyingly
        "folke/lazydev.nvim",
        ft = "lua", -- only load on lua files
        opts = {
            library = {
                -- See the configuration section for more details
                -- Load luvit types when the `vim.uv` word is found
                { path = "${3rd}/luv/library", words = { "vim%.uv" } },
            },
        },
    },
    {
        -- For base LSP settings in neovim for several languages
        "neovim/nvim-lspconfig",
    },
    {
        "https://codeberg.org/andyg/leap.nvim.git",
        lazy = false, -- This plugin is already lazy
        config = function()
            vim.keymap.set({ "n", "x", "o" }, "s", "<Plug>(leap)")
            vim.keymap.set("n", "S", "<Plug>(leap-from-window)")
        end,
    },
    {
        -- Provides rules for indented blocks
        "saghen/blink.indent",
        --- @module 'blink.indent'
        --- @type blink.indent.Config
        opts = {
            -- I prefer a thiner line than the default one
            static = {
                char = "▏",
            },
            scope = {
                char = "▏",
                highlights = { "BlinkIndentScope" },
            },
        },
    },
    {
        -- Neovim completion sources for Lua
        -- so neovim objects show as completion candidates when auto complete is triggered on Lua files
        -- optional cmp completion source for require statements and module annotations
        "hrsh7th/nvim-cmp",
        opts = function(_, opts)
            opts.sources = opts.sources or {}
            table.insert(opts.sources, {
                name = "lazydev",
                group_index = 0, -- set group index to 0 to skip loading LuaLS completions
            })
        end,
    },
    {
        -- Completion engine
        -- optional blink completion source for require statements and module annotations
        "saghen/blink.cmp",
        dir = vim.fn.globpath(vim.o.packpath, "pack/*/opt/blink.cmp", 0, 1)[1],
        dependencies = { "rafamadriz/friendly-snippets", "saghen/blink.lib" },
        build = function() require('blink.cmp').build():wait(60000) end,
        opts = {
            keymap = { preset = "super-tab" },
            appearance = { nerd_font_variant = "mono" },
            completion = { documentation = { auto_show = true } },
            sources = {
                -- add lazydev to your completion providers
                default = { "lazydev", "lsp", "path", "snippets", "buffer" },
                providers = {
                    lazydev = {
                        name = "LazyDev",
                        module = "lazydev.integrations.blink",
                        -- make lazydev completions top priority (see `:h blink.cmp`)
                        score_offset = 100,
                    },
                },
            },
            fuzzy = { implementation = "prefer_rust_with_warning" },
        },
    },
    {
        "mrcjkb/haskell-tools.nvim",
        version = "^6", -- Recommended
        lazy = false, -- This plugin is already lazy
    },
    {
        -- Neovim Lua implementation of Pope's vim-surround
        "kylechui/nvim-surround",
        version = "3.*",
        event = "VeryLazy",
        opts = {},
    },
    {
        "sindrets/diffview.nvim",
        cmd = "DiffviewFileHistory",
    },
    {
        "lewis6991/gitsigns.nvim",
    },
    {
        -- Magit like client for git
        "NeogitOrg/neogit",
        lazy = true,
        dependencies = {
            "nvim-lua/plenary.nvim",
            "sindrets/diffview.nvim",
            "ibhagwan/fzf-lua",
        },
        cmd = "Neogit",
        keys = {
            { "<leader>gg", "<cmd>Neogit<cr>", desc = "Show Neogit UI" },
        },
        opts = {
            mappings = {
                status = {
                    ["h"] = "MoveUp",
                    ["k"] = "MoveDown",
                },
            },
        },
    },
    {
        "pmizio/typescript-tools.nvim",
        dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
        opts = {},
    },
    {
        -- JSON schemas to get lint checks on well-known JSON files
        "b0o/schemastore.nvim",
    },
}
