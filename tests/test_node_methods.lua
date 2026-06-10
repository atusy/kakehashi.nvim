local H = dofile("tests/helpers.lua")

local T = {}

---@return KakehashiNode, table fake client (with .calls)
local function root_node(responses)
	responses = responses or {}
	responses["kakehashi/node"] = { id = "root", kind = "document" }
	local client = H.fake_client(responses)
	local node = require("kakehashi.lsp.node").get({
		client = client,
		bufnr = H.scratch_buf(),
		position = { line = 0, character = 0 },
	})
	client.calls = {} -- only record accessor calls from here on
	return node, client
end

T["introspection methods unwrap their single-field result"] = function()
	local node = root_node({
		["kakehashi/node/kind"] = { kind = "function_definition" },
		["kakehashi/node/grammarName"] = { grammarName = "function_definition" },
		["kakehashi/node/isNamed"] = { isNamed = false },
		["kakehashi/node/hasError"] = { hasError = true },
		["kakehashi/node/startByte"] = { startByte = 12 },
		["kakehashi/node/childCount"] = { childCount = 3 },
		["kakehashi/node/toSexp"] = { sexp = "(document)" },
		["kakehashi/node/text"] = { text = "print('hi')" },
		["kakehashi/node/startPosition"] = { startPosition = { line = 1, character = 2 } },
	})
	H.eq("function_definition", node:kind())
	H.eq("function_definition", node:grammarName())
	H.eq(false, node:isNamed()) -- false must survive unwrapping, not collapse to nil
	H.eq(true, node:hasError())
	H.eq(12, node:startByte())
	H.eq(3, node:childCount())
	H.eq("(document)", node:toSexp())
	H.eq("print('hi')", node:text())
	H.eq({ line = 1, character = 2 }, node:startPosition())
end

T["byteRange and range return the whole result object"] = function()
	local node = root_node({
		["kakehashi/node/byteRange"] = { startByte = 1, endByte = 9 },
		["kakehashi/node/range"] = {
			start = { line = 0, character = 0 },
			["end"] = { line = 2, character = 0 },
		},
	})
	H.eq({ startByte = 1, endByte = 9 }, node:byteRange())
	H.eq({ start = { line = 0, character = 0 }, ["end"] = { line = 2, character = 0 } }, node:range())
end

T["parent() sends textDocument and id, returns a KakehashiNode"] = function()
	local node, client = root_node({
		["kakehashi/node/parent"] = { id = "parent-1", kind = "section" },
	})
	local parent = node:parent()
	H.eq("kakehashi/node/parent", client.calls[1].method)
	H.eq({
		textDocument = { uri = vim.uri_from_bufnr(node.bufnr) },
		id = "root",
	}, client.calls[1].params)
	H.eq("parent-1", parent.id)
	H.eq("grandparent", parent:parent() and "grandparent" or nil) -- chains: wrapper, not plain table
end

T["navigation methods pass their extra arguments by name"] = function()
	local node, client = root_node({
		["kakehashi/node/child"] = { id = "c", kind = "k" },
		["kakehashi/node/firstChildForByte"] = { id = "c", kind = "k" },
		["kakehashi/node/descendantForByteRange"] = { id = "c", kind = "k" },
		["kakehashi/node/childByFieldName"] = { id = "c", kind = "k" },
		["kakehashi/node/descendantForPointRange"] = { id = "c", kind = "k" },
	})
	node:child(2)
	H.eq(2, client.calls[1].params.index)
	node:firstChildForByte(7)
	H.eq(7, client.calls[2].params.byte)
	node:descendantForByteRange(3, 9)
	H.eq(3, client.calls[3].params.startByte)
	H.eq(9, client.calls[3].params.endByte)
	node:childByFieldName("body")
	H.eq("body", client.calls[4].params.name)
	node:descendantForPointRange({ line = 0, character = 1 }, { line = 0, character = 5 })
	H.eq({ line = 0, character = 1 }, client.calls[5].params.start)
	H.eq({ line = 0, character = 5 }, client.calls[5].params["end"])
end

T["children() wraps each NodeInfo in a KakehashiNode"] = function()
	local node = root_node({
		["kakehashi/node/children"] = {
			{ id = "a", kind = "x" },
			{ id = "b", kind = "y" },
		},
		["kakehashi/node/text"] = { text = "t" },
	})
	local children = node:children()
	H.eq(2, #children)
	H.eq("a", children[1].id)
	H.eq("t", children[2]:text())
end

T["fieldNameForChild unwraps fieldName and converts null to nil"] = function()
	local responses = {}
	local node, client = root_node(responses)
	responses["kakehashi/node/fieldNameForChild"] = { fieldName = "name" }
	H.eq("name", node:fieldNameForChild(0))
	H.eq(0, client.calls[1].params.index)
	responses["kakehashi/node/fieldNameForChild"] = { fieldName = vim.NIL }
	H.eq(nil, node:fieldNameForChild(1))
end

T["unresolvable id (null result) returns nil from any method"] = function()
	local node = root_node({}) -- every accessor answers null
	H.eq(nil, node:parent())
	H.eq(nil, node:children())
	H.eq(nil, node:kind())
end

T["json null (vim.NIL) result is treated as nil"] = function()
	local node = root_node({
		["kakehashi/node/parent"] = vim.NIL,
	})
	H.eq(nil, node:parent())
end

T["get() treats vim.NIL result as nil"] = function()
	local client = H.fake_client({ ["kakehashi/node"] = vim.NIL })
	local node = require("kakehashi.lsp.node").get({
		client = client,
		bufnr = H.scratch_buf(),
		position = { line = 0, character = 0 },
	})
	H.eq(nil, node)
end

return T
