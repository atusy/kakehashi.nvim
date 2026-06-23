local H = dofile("tests/helpers.lua")

local util = require("kakehashi.lsp.util")

local T = {}

T["reap_on_detach() reaps a buffer-specific subscriber only when its own buffer detaches"] = function()
	local client = H.fake_client({})
	client.attached_buffers = { [7] = true } -- irrelevant: the buffer it follows decides
	H.eq(true, util.reap_on_detach(client, 7, 7), "its buffer left")
	H.eq(false, util.reap_on_detach(client, 7, 9), "a different buffer left")
end

T["reap_on_detach() keeps an all-buffer subscriber while the client still serves buffers"] = function()
	local client = H.fake_client({})
	-- nvim fires LspDetach before dropping the buffer, so 7 is still listed
	client.attached_buffers = { [7] = true, [9] = true }
	H.eq(false, util.reap_on_detach(client, nil, 7), "buffer 9 still keeps it working")
end

T["reap_on_detach() reaps an all-buffer subscriber when its last buffer detaches"] = function()
	local client = H.fake_client({})
	-- the detaching buffer is still listed when LspDetach fires; it must be
	-- excluded, or the last buffer leaving would never be recognized
	client.attached_buffers = { [7] = true }
	H.eq(true, util.reap_on_detach(client, nil, 7))
end

T["reap_on_detach() reaps an all-buffer subscriber once the client has stopped"] = function()
	local client = H.fake_client({})
	client.stopped = true
	client.attached_buffers = { [7] = true } -- a stopped client's bookkeeping is moot
	H.eq(true, util.reap_on_detach(client, nil, 7))
end

return T
