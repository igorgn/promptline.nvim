local M = {}

local ui = require("promptline.ui")
local backend = require("promptline.backend")
local replace = require("promptline.replace")

M.config = {
	backend = "claude_cli", -- "claude_cli" | "anthropic_api"
	model = "claude-haiku-4-5", -- used by anthropic_api backend
	max_tokens = 8096,
	api_key = nil, -- falls back to ANTHROPIC_API_KEY env var
	default_prompt = "Improve this",
	system_prompt = "You are a precise code and text editor. When given text and an instruction, you apply the instruction and return only the edited result.",
	keymap = "<leader>p",
	float_width = 60,
	format_on_apply = true,  -- run LSP formatter after replacement
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	vim.keymap.set("v", M.config.keymap, function()
		M.trigger()
	end, { desc = "Promptline: edit selection with AI" })
end

-- Capture the visual selection (marks '< and '>) before opening the float,
-- because opening a float exits visual mode and clears the marks.
local function get_visual_selection()
	-- Force update of '< '> marks
	local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	vim.api.nvim_feedkeys(esc, "x", false)

	local buf = vim.api.nvim_get_current_buf()
	local start_pos = vim.api.nvim_buf_get_mark(buf, "<")
	local end_pos = vim.api.nvim_buf_get_mark(buf, ">")

	local start_line = start_pos[1]
	local start_col = start_pos[2]
	local end_line = end_pos[1]
	local end_col = end_pos[2]

	-- nvim_buf_get_text end_col is exclusive, but '> col is the last selected byte.
	-- For characterwise visual, end_col from mark is the last byte index (inclusive).
	-- We need to pass end_col+1 to nvim_buf_get_text.
	local lines = vim.api.nvim_buf_get_text(buf, start_line - 1, start_col, end_line - 1, end_col + 1, {})
	local text = table.concat(lines, "\n")

	-- Collect LSP diagnostics that overlap the selected line range
	local diag_lines = {}
	local all_diags = vim.diagnostic.get(buf)
	for _, d in ipairs(all_diags) do
		local dline = d.lnum + 1 -- diagnostic lines are 0-indexed
		if dline >= start_line and dline <= end_line then
			local severity = vim.diagnostic.severity[d.severity] or "HINT"
			table.insert(diag_lines, string.format("  line %d [%s]: %s", dline, severity, d.message))
		end
	end

	return {
		buf = buf,
		start_line = start_line,
		start_col = start_col,
		end_line = end_line,
		end_col = end_col + 1, -- exclusive end col for set_text
		text = text,
		diagnostics = #diag_lines > 0 and table.concat(diag_lines, "\n") or nil,
	}
end

function M.trigger()
	local sel = get_visual_selection()

	if sel.text == "" then
		vim.notify("promptline: no text selected", vim.log.levels.WARN)
		return
	end

	ui.prompt({
		title = "promptline",
		placeholder = M.config.default_prompt,
		width = M.config.float_width,
	}, function(user_prompt, float_win, float_buf)
		if user_prompt == "" then
			user_prompt = M.config.default_prompt
		end

		-- Reuse the prompt float as a spinner — keeps it visible during the call
		local stop_spinner = ui.show_working(float_win, float_buf, "thinking…")

		backend.run(M.config, sel.text, user_prompt, sel.diagnostics, function(result, err)
			vim.schedule(function()
				stop_spinner()
				ui.close_float(float_win)

				if err then
					vim.notify("promptline error: " .. err, vim.log.levels.ERROR)
					return
				end

				if not result or result == "" then
					vim.notify("promptline: empty response", vim.log.levels.WARN)
					return
				end

				replace.replace_selection(sel.buf, sel.start_line, sel.start_col, sel.end_line, sel.end_col, result)

				if M.config.format_on_apply then
					vim.lsp.buf.format({ bufnr = sel.buf, async = false })
				end

				vim.api.nvim_buf_call(sel.buf, function()
					vim.cmd("silent! write")
				end)

				vim.notify("promptline: done  (u to undo)", vim.log.levels.INFO)
			end)
		end)
	end, function()
		-- on_cancel: nothing to do
	end)
end

return M
