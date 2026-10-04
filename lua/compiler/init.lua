local M = {}

local MANAGERS = {
	cargo = function(command)
		if command == 'build' then
			return { 'cargo', 'build' }
		elseif command == 'clean' then
			return { 'cargo', 'clean' }
		elseif command == 'test' then
			return { 'cargo', 'test', '--', '--color=always' }
		end
		return nil
	end,
	go = function(command)
		if command == 'build' then
			return { 'go', 'build', '.' }
		elseif command == 'clean' then
			return { 'go', 'clean' }
		elseif command == 'test' then
			return { 'go', 'test', '.' }
		end
		return nil
	end,
	npm = function(command)
		if command == 'build' then
			return { 'npm', 'run', 'build' }
		elseif command == 'clean' then
			return { 'npm', 'ci' }
		elseif command == 'test' then
			return { 'npm', 'run', 'test' }
		end
		return nil
	end
}
local MESSAGES = {
	build = {
		starting = 'Building...',
		success = 'Built successfully.',
		error = 'Failed to build.',
	},
	clean = {
		starting = 'Cleaning...',
		success = 'Cleaned successfully.',
		error = 'Failed to clean.',
	},
	test = {
		starting = 'Testing...',
		success = 'Tests passed.',
		error = 'Tests failed.'
	}
}

local exists = function(path)
	return vim.uv.fs_stat(path) ~= nil
end

local function system(cmd, opts)
	return vim.async.await(function(done)
		return vim.system(cmd, opts, vim.schedule_wrap(done))
	end)
end

local resolve_manager = function()
	local dir = vim.uv.cwd()
	if exists(vim.fs.joinpath(dir, 'Cargo.toml')) then
		return 'cargo'
	elseif exists(vim.fs.joinpath(dir, 'go.mod')) then
		return 'go'
	elseif exists(vim.fs.joinpath(dir, 'package.json')) then
		return 'npm'
	end
	return nil
end

local echo_error = function(msg)
	vim.schedule(function()
		vim.api.nvim_echo({ { msg, "ErrorMsg" } }, true, {})
	end)
end


LAST_REPORT = ''

local open_report = function(cmd)
	vim.cmd("tabnew")
	local buf = vim.api.nvim_get_current_buf()
	vim.bo[buf].bufhidden = "wipe"

	-- terminal buffer renders ANSI colors; it needs CRLF line endings
	local chan = vim.api.nvim_open_term(buf, {})
	vim.api.nvim_chan_send(chan, (LAST_REPORT:gsub('\r?\n', '\r\n')))
end

local execute = function(cmd)
	local task = vim.async.run(function()
		local manager_name = resolve_manager()
		if manager_name == nil then
			vim.api.nvim_echo({ { "No manager detected.", "ErrorMsg" } }, false, {})
			return
		end

		local progress = {
			kind = 'progress',
			source = 'build.nvim',
			status = 'running',
			title = cmd,
		}

		local manager = MANAGERS[manager_name];
		local cmd_to_run = manager(cmd)
		if cmd_to_run == nil then
			vim.api.nvim_echo({ { manager_name .. " does not support '" .. cmd .. "'.", "ErrorMsg" } }, true,
				{})
			return
		end
		vim.api.nvim_echo({ { MESSAGES[cmd].starting, "DiagnosticOk" } }, false, progress);

		local ok, output = pcall(system, cmd_to_run, { text = true, env = { CARGO_TERM_COLOR = 'always' } })
		if not ok then
			progress.status = 'failed'
			vim.api.nvim_echo({ { MESSAGES[cmd].error, "ErrorMsg" } }, false, progress)
			vim.api.nvim_echo(
				{ { "Could not run '" .. cmd_to_run[1] .. "': " .. tostring(output), "ErrorMsg" } }, true,
				{})
			return
		end

		local text = (output.stdout or '') .. (output.stderr or '')
		if text == '' then
			text = table.concat(cmd_to_run, ' ') ..
			    ' exited with code ' .. output.code .. ' and no output.\n'
		end
		LAST_REPORT = text

		if output.code == 0 then
			progress.status = 'success'
			vim.api.nvim_echo({ { MESSAGES[cmd].success, "DiagnosticOk" } }, false, progress);
		else
			progress.status = 'failed'

			vim.api.nvim_echo({ { MESSAGES[cmd].error, "ErrorMsg" } }, false, progress)

			open_report()
		end
	end)

	-- top-level tasks don't raise on their own; surface anything unexpected
	task:on_complete(function(err)
		if err ~= nil then
			echo_error('build.nvim: ' .. task:traceback(err))
		end
	end)
end


M.setup = function(opts)
	vim.keymap.set('n', '<leader>bb', function()
		execute('build')
	end)
	vim.keymap.set('n', '<leader>bc', function()
		execute('clean')
	end)
	vim.keymap.set('n', '<leader>bt', function()
		execute('test')
	end)
	vim.keymap.set('n', '<leader>br', function()
		open_report()
	end)
end

return M
