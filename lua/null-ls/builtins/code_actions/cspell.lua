local h = require("null-ls.helpers")
local methods = require("null-ls.methods")

local CODE_ACTION = methods.internal.CODE_ACTION
-- filter diagnostics generated by the cspell built-in
local cspell_diagnostics = function(bufnr, lnum, cursor_col)
    local diagnostics = {}
    for _, diagnostic in ipairs(vim.diagnostic.get(bufnr, { lnum = lnum })) do
        if diagnostic.source == "cspell" and cursor_col >= diagnostic.col and cursor_col < diagnostic.end_col then
            table.insert(diagnostics, diagnostic)
        end
    end
    return diagnostics
end

local CSPELL_CONFIG_FILES = {
    "cspell.json",
    ".cspell.json",
    "cSpell.json",
    ".Sspell.json",
    ".cspell.config.json",
}

-- find the first cspell.json file in the directory tree
local find_cspell_config = function(cwd)
    local cspell_json_file = nil
    for _, file in ipairs(CSPELL_CONFIG_FILES) do
        local path = vim.fn.findfile(file, (cwd or vim.loop.cwd()) .. ";")
        if path ~= "" then
            cspell_json_file = path
            break
        end
    end
    return cspell_json_file
end

return h.make_builtin({
    name = "cspell",
    meta = {
        url = "https://github.com/streetsidesoftware/cspell",
        description = "Injects actions to fix typos found by `cspell`.",
        notes = {
            "This source depends on the `cspell` built-in diagnostics source, so make sure to register it, too.",
        },
        usage = "local sources = { null_ls.builtins.diagnostics.cspell, null_ls.builtins.code_actions.cspell }",
    },
    method = CODE_ACTION,
    filetypes = {},
    generator = {
        fn = function(params)
            local actions = {}

            local config = params:get_config()
            local find_json = config.find_json or find_cspell_config

            local diagnostics = cspell_diagnostics(params.bufnr, params.row - 1, params.col)
            if vim.tbl_isempty(diagnostics) then
                return nil
            end
            for _, diagnostic in ipairs(diagnostics) do
                for _, suggestion in ipairs(diagnostic.user_data.suggestions) do
                    table.insert(actions, {
                        title = string.format("Use %s", suggestion),
                        action = function()
                            vim.api.nvim_buf_set_text(
                                diagnostic.bufnr,
                                diagnostic.lnum,
                                diagnostic.col,
                                diagnostic.end_lnum,
                                diagnostic.end_col,
                                { suggestion }
                            )
                        end,
                    })
                end

                -- add word to "words" in cspell.json
                table.insert(actions, {
                    title = "Add to cspell json file",
                    action = function()
                        local word = vim.api.nvim_buf_get_text(
                            diagnostic.bufnr,
                            diagnostic.lnum,
                            diagnostic.col,
                            diagnostic.end_lnum,
                            diagnostic.end_col,
                            {}
                        )[1]

                        local cspell_json_file = find_json(params.cwd)
                        if cspell_json_file == "" then
                            vim.notify("\nNo cspell json file found in the directory tree.\n", vim.log.levels.ERROR)
                            return
                        end

                        local ok, cspell = pcall(vim.json.decode, vim.fn.readfile(cspell_json_file)[1])

                        if not ok then
                            vim.notify("\nCannot parse cspell json file as JSON.\n", vim.log.levels.ERROR)
                            return
                        end

                        if not cspell.words then
                            cspell.words = {}
                        end

                        table.insert(cspell.words, word)

                        vim.fn.writefile({ vim.json.encode(cspell) }, cspell_json_file)

                        -- replace word in buffer to trigger cspell to update diagnostics
                        vim.api.nvim_buf_set_text(
                            diagnostic.bufnr,
                            diagnostic.lnum,
                            diagnostic.col,
                            diagnostic.end_lnum,
                            diagnostic.end_col,
                            { word }
                        )
                    end,
                })
            end
            return actions
        end,
    },
})
