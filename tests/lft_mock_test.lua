-- 离线单元测试: 用 mock 的 cm/core/UIComponent 跑 mod 主逻辑。
-- 由 tools/run_lua_tests.py 通过 lupa 执行, 不需要游戏。

local captured = { listeners = {}, log = {} }
_G.captured = captured

_G.out = function(msg)
	captured.log[#captured.log + 1] = tostring(msg)
end

function model_pairs(list)
	local i = 0
	return function()
		i = i + 1
		if i <= list:count() then
			return i, list:item(i)
		end
	end
end

--============================ UI mock ============================--

local function new_component(props)
	local c = {
		_id = props.id,
		_text = props.text or "",
		_children = props.children or {},
		_visible = props.visible ~= false,
		_valid = true,
	}
	function c:Id()
		return self._id
	end
	function c:IsValid()
		return self._valid
	end
	function c:ChildCount()
		return #self._children
	end
	function c:Find(i)
		return self._children[i + 1]
	end
	function c:Visible(recursive)
		return self._visible
	end
	function c:GetStateText()
		return self._text
	end
	function c:SetText(text, source)
		self._text = text
	end
	function c:SetStateText(text, source)
		self._text = text
	end
	return c
end

_G.new_component = new_component
_G.UIComponent = function(address)
	return address
end

--============================ 模型 mock ============================--

local null_interface = {
	is_null_interface = function()
		return true
	end,
}

local function character(legendary)
	return {
		is_null_interface = function()
			return false
		end,
		character_details = function()
			return {
				is_null_interface = function()
					return false
				end,
				is_unique = function()
					return legendary
				end,
			}
		end,
	}
end

local function faction(name, cqi, legendary, has_leader)
	local f = {}
	function f:is_null_interface()
		return false
	end
	function f:has_faction_leader()
		return has_leader ~= false
	end
	function f:faction_leader()
		if has_leader == false then
			return null_interface
		end
		return character(legendary)
	end
	function f:command_queue_index()
		return cqi
	end
	function f:name()
		return name
	end
	return f
end

local faction_list = {
	_items = {
		faction("Reikland", 1, true),
		faction("Marienburg", 2, false),
		faction("Karaz-a-Karak", 3, true),
		faction("Leaderless", 4, false, false),
	},
}
function faction_list:count()
	return #self._items
end
function faction_list:item(i)
	return self._items[i]
end

_G.cm = {}
function cm:get_faction_list()
	return faction_list
end
function cm:add_first_tick_callback(fn)
	fn()
end
function cm:repeat_real_callback(fn, interval, name)
	captured.poll = fn
	captured.poll_interval = interval
end
function cm:real_callback(fn, delay, name)
	captured.real_callback = fn
end

_G.core = {}
function core:is_ui_created()
	return true
end
function core:get_ui_root()
	return captured.root
end
function core:add_listener(name, event, condition, callback, persistent)
	captured.listeners[name] = callback
end

--============================ 运行测试 ============================--

local MOD = "src/script/campaign/mod/lft_legendary_faction_tags.lua"

local function build_tree(visible)
	local rows = {}
	for _, text in ipairs({
		"Reikland",
		"Marienburg",
		"Karaz-a-Karak",
		"Reikland (Alice)",
	}) do
		local label = new_component({ id = "name", text = text })
		rows[#rows + 1] = new_component({ id = "row", children = { label } })
	end
	return new_component({
		id = "diplomacy_hud",
		visible = visible,
		children = {
			new_component({
				id = "faction_panel",
				children = { new_component({ id = "sortable_list_factions", children = rows }) },
			}),
		},
	})
end

local function fail(msg)
	error("TEST FAILED: " .. msg, 2)
end

local function assert_eq(actual, expected, label)
	if actual ~= expected then
		fail(label .. " (expected '" .. tostring(expected) .. "', got '" .. tostring(actual) .. "')")
	end
end

local function rows_of(panel)
	return panel._children[1]._children[1]._children
end

local function label_text(panel, index)
	return rows_of(panel)[index]._children[1]:GetStateText()
end

local function run()
	-- 1) 面板可见: 传奇派系被标注, 普通派系不动, 多人局后缀能识别
	captured.root = new_component({ id = "root", children = { build_tree(true) } })
	dofile(MOD)
	local panel = captured.root._children[1]
	if type(captured.poll) ~= "function" then
		fail("repeat_real_callback 没有注册轮询函数")
	end
	captured.poll()
	assert_eq(label_text(panel, 1), "Reikland ★", "传奇派系应加星")
	assert_eq(label_text(panel, 2), "Marienburg", "普通派系不应改")
	assert_eq(label_text(panel, 3), "Karaz-a-Karak ★", "第二个传奇派系应加星")
	assert_eq(label_text(panel, 4), "Reikland (Alice) ★", "多人局后缀格式应加星")

	-- 2) 幂等: 多次轮询不会重复加星
	captured.poll()
	captured.poll()
	assert_eq(label_text(panel, 1), "Reikland ★", "重复轮询不应叠加标记")

	-- 3) 引擎重写文本后能恢复
	rows_of(panel)[1]._children[1]._text = "Reikland"
	captured.poll()
	assert_eq(label_text(panel, 1), "Reikland ★", "文本被重写后应重新标注")

	-- 4) 没有领袖的派系不崩、不加标记
	assert_eq(label_text(panel, 4), "Reikland (Alice) ★", "无领袖派系不应影响其它行")

	-- 5) 回合刷新监听器可用
	local refresh = captured.listeners["lft_turn_refresh"]
	if type(refresh) ~= "function" then
		fail("缺少 FactionTurnStart 监听器")
	end
	refresh({
		faction = function()
			return {
				is_null_interface = function()
					return false
				end,
				is_human = function()
					return true
				end,
			}
		end,
	})

	-- 6) 面板不可见时不写入 (先让缓存句柄失效, 强制重新查找)
	panel._valid = false
	local hidden = build_tree(false)
	captured.root = new_component({ id = "root", children = { hidden } })
	local hidden_label = rows_of(hidden)[1]._children[1]
	captured.poll()
	assert_eq(hidden_label:GetStateText(), "Reikland", "隐藏面板不应被写入")

	print("ALL TESTS PASSED")
end

run()
