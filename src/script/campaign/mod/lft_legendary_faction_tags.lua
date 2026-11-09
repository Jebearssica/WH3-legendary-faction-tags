--[[
    传奇派系外交标注 / Legendary Faction Tags
    位置: script/campaign/mod/ (由原版 mod loader 自动加载, 无需任何注册)
    作用: 在外交界面给"传奇派系"(领袖为传奇领主的派系)的名称追加标记。

    判定依据: faction:faction_leader():character_details():is_unique()
    原版没有 faction:is_legendary(), factions 表也没有该字段; is_unique 即
    startpos 中 is_legendary 的运行时表现 (CA 自己的 wh3_campaign_subjugation.lua
    用它区分传奇领主与普通领主)。

    实现方式: 面板可见时轮询组件树, 用 GetStateText 读文本、SetText/SetStateText
    写回。不修改任何原版 .twui.xml, 因此与 UI 类 mod 基本不冲突。
]]

--============================ 可调参数 ============================--

-- 追加在名称后的标记。字体缺字时可换成:
--   " [[img:ui/skins/default/xxx.png]]"  (富文本内联图标, 需自带图片)
--   " *"                                  (绝对安全的 ASCII)
local MARKER = " ★"

local POLL_MS = 400        -- 面板可见时的刷新间隔(毫秒)
local DEBUG = false        -- true 时向脚本日志输出匹配结果

local PANEL_IDS = { "diplomacy_hud", "war_coordination", "ally_attacked" }
local RETRY_POLLS = 10     -- 未找到的面板每隔多少次轮询再找一遍

--==================================================================--

local legendary_names = {}   -- 派系显示名 -> true
local legendary_cqi = {}     -- 派系 cqi -> true (只累积, 领主暂时阵亡也不丢标记)
local panel_cache = {}       -- 面板名 -> uicomponent
local poll_count = 0

local function log(msg)
	if DEBUG then
		out("[lft] " .. tostring(msg))
	end
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--============================ 传奇判定 ============================--

local function is_legendary_faction(faction)
	if faction:is_null_interface() then
		return false
	end
	if not faction:has_faction_leader() then
		return false
	end
	local leader = faction:faction_leader()
	if leader:is_null_interface() then
		return false
	end
	local details = leader:character_details()
	if details:is_null_interface() then
		return false
	end
	return details:is_unique() == true
end

local function rebuild_cache()
	local names = {}
	local name_count = 0
	local list = cm:get_faction_list()
	if not list then
		return
	end
	local function consider(faction)
		if faction:is_null_interface() then
			return
		end
		local cqi = faction:command_queue_index()
		if not legendary_cqi[cqi] and is_legendary_faction(faction) then
			legendary_cqi[cqi] = true
			log("legendary faction: " .. tostring(faction:name()))
		end
		if legendary_cqi[cqi] then
			local name = faction:name()
			if name and name ~= "" and not names[name] then
				names[name] = true
				name_count = name_count + 1
			end
		end
	end
	if model_pairs then
		for _, faction in model_pairs(list) do
			consider(faction)
		end
	else
		for i = 1, list:count() do
			consider(list:item(i))
		end
	end
	legendary_names = names
	log("cache rebuilt, legendary names: " .. tostring(name_count))
end

--============================ 文本标注 ============================--

local function is_legendary_text(text)
	if legendary_names[text] then
		return true
	end
	-- 多人局常见格式: "Reikland (PlayerName)"
	local stripped = text:match("^(.-)%s+%b()$")
	return stripped ~= nil and legendary_names[stripped] == true
end

local function set_text(component, text)
	if not pcall(function()
		component:SetText(text, "")
	end) then
		pcall(function()
			component:SetStateText(text, "")
		end)
	end
end

local function apply_marker(component)
	local ok, text = pcall(function()
		return component:GetStateText()
	end)
	if not ok or type(text) ~= "string" or text == "" then
		return
	end
	local current = trim(text)
	if current:sub(-#MARKER) == MARKER then
		return
	end
	if not is_legendary_text(current) then
		return
	end
	log("patching: " .. current)
	set_text(component, current .. MARKER)
end

local function walk(component)
	apply_marker(component)
	for i = 0, component:ChildCount() - 1 do
		local address = component:Find(i)
		if address then
			local child = UIComponent(address)
			if child:IsValid() then
				walk(child)
			end
		end
	end
end

--============================ 面板定位 ============================--

local function find_by_id(component, id)
	if component:Id() == id then
		return component
	end
	for i = 0, component:ChildCount() - 1 do
		local address = component:Find(i)
		if address then
			local child = UIComponent(address)
			if child:IsValid() then
				local found = find_by_id(child, id)
				if found then
					return found
				end
			end
		end
	end
	return nil
end

local function get_panel(id)
	local cached = panel_cache[id]
	if cached and cached:IsValid() then
		return cached
	end
	if cached == nil and poll_count > 3 and poll_count % RETRY_POLLS ~= 0 then
		-- 还没找到过: 不必每次轮询都做全树搜索
		return nil
	end
	local panel = find_by_id(core:get_ui_root(), id)
	panel_cache[id] = panel
	return panel
end

local function poll()
	if not core:is_ui_created() then
		return
	end
	poll_count = poll_count + 1
	for _, id in ipairs(PANEL_IDS) do
		local panel = get_panel(id)
		if panel and panel:IsValid() and panel:Visible(true) then
			walk(panel)
		end
	end
end

local function safe_poll()
	local ok, err = pcall(poll)
	if not ok then
		log("poll error: " .. tostring(err))
	end
end

--============================ 生命周期 ============================--

cm:add_first_tick_callback(function()
	rebuild_cache()
	cm:repeat_real_callback(safe_poll, POLL_MS, "lft_marker_poll")

	-- 每回合刷新一次缓存, 覆盖联邦/合邦/更换领袖等情况
	core:add_listener(
		"lft_turn_refresh",
		"FactionTurnStart",
		function(context)
			local faction = context:faction()
			return faction:is_null_interface() == false and faction:is_human()
		end,
		function()
			rebuild_cache()
		end,
		true
	)

	-- 面板开关后延迟刷新, 让引擎先把列表内容填好
	core:add_listener(
		"lft_panel_refresh",
		"PanelOpenedCampaign",
		true,
		function()
			if next(legendary_names) == nil then
				rebuild_cache()
			end
			cm:real_callback(safe_poll, 50, "lft_panel_refresh_cb")
		end,
		true
	)
end)
