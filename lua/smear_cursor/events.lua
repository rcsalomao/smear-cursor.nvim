local animation = require("smear_cursor.animation")
local color = require("smear_cursor.color")
local config = require("smear_cursor.config")
local screen = require("smear_cursor.screen")
local M = {}

local latest_mode = nil
local latest_row = nil
local latest_col = nil
local timer = nil
local cursor_namespace = vim.api.nvim_create_namespace("smear_cursor")

local EVENT_TRIGGER = nil
local AFTER_DELAY = 1

local function move_cursor(trigger, jump)
	-- Calls to this function must deferred for screen.get_screen_cursor_position() and vim.api.nvim.get_mode() to work
	trigger = trigger or EVENT_TRIGGER
	local row, col
	local mode = vim.api.nvim_get_mode().mode

	if mode == "i" and not config.smear_insert_mode then jump = true end
	if mode == "R" and not config.smear_replace_mode then jump = true end
	if mode == "t" and not config.smear_terminal_mode then jump = true end

	if mode ~= "c" then
		row, col = screen.get_screen_cursor_position()
	elseif config.smear_to_cmd then
		row, col = screen.get_screen_cmd_cursor_position()
	else
		return
	end

	if timer ~= nil and timer:is_active() then
		timer:stop()
		timer:close()
	end
	timer = nil

	if trigger == AFTER_DELAY and mode == latest_mode and row == latest_row and col == latest_col then
		if jump then
			animation.jump(row, col)
		else
			animation.change_target_position(row, col)
		end
	else -- try until the cursor stops moving
		latest_mode = mode
		latest_row = row
		latest_col = col

		timer = vim.uv.new_timer()
		timer:start(
			config.delay_event_to_smear,
			0,
			vim.schedule_wrap(function()
				move_cursor(AFTER_DELAY, jump)
			end)
		)
	end
end

local function move_cursor_from_event(replace_real_cursor, only_hide_real_cursor)
	if only_hide_real_cursor == nil then only_hide_real_cursor = false end
	if vim.tbl_contains(config.filetypes_disabled, vim.bo.filetype) or animation.disabled_in_buffer then return end

	if replace_real_cursor then animation.replace_real_cursor(only_hide_real_cursor) end
	vim.defer_fn(function()
		move_cursor(EVENT_TRIGGER, false)
	end, 0)
end

M.move_cursor = function()
	move_cursor_from_event(true, false)
end

local function on_key(key, typed)
	move_cursor_from_event(false)
end

M.jump_cursor = function()
	vim.defer_fn(function()
		move_cursor(EVENT_TRIGGER, true)
	end, 0)
end

M.re_enable = function()
	animation.disabled_in_buffer = false
end

-- Aliases for autocmds
M.update_color_at_cursor = color.update_color_at_cursor
M.clear_cache = color.clear_cache

M.listen = function()
	local group = vim.api.nvim_create_augroup("SmearCursor", { clear = true })
	local autocmds = {
		update_color_at_cursor = { "CursorMoved", "CursorMovedI" },
		move_cursor = { "CmdlineChanged", "CursorMoved", "CursorMovedI", "ModeChanged", "WinScrolled" },
		clear_cache = { "ColorScheme" },
		re_enable = { "BufEnter" },
	}

	for function_name, events in pairs(autocmds) do
		vim.api.nvim_create_autocmd(events, {
			group = group,
			callback = M[function_name],
		})
	end

	-- To catch changes that do not trigger events (e.g. opening/closing folds)
	vim.on_key(on_key, cursor_namespace)
end

M.unlisten = function()
	pcall(vim.api.nvim_clear_autocmds, { group = "SmearCursor" })
	vim.on_key(nil, cursor_namespace)
end

return M
