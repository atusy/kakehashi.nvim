-- Test runner: nvim -l tests/run.lua [pattern]
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local pattern = _G.arg[1] or "tests/test_*.lua"
local files = vim.fn.glob(pattern, false, true)
if #files == 0 then
	io.stderr:write("no test files match " .. pattern .. "\n")
	os.exit(1)
end

local failed = 0
local passed = 0
for _, file in ipairs(files) do
	local tests = dofile(file)
	for name, test in vim.spairs(tests) do
		local ok, err = pcall(test)
		if ok then
			passed = passed + 1
			print(("ok   %s :: %s"):format(file, name))
		else
			failed = failed + 1
			io.stderr:write(("FAIL %s :: %s\n  %s\n"):format(file, name, err))
		end
	end
end

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
