# Copilot 指令 — WH3 外交界面传奇派系标注

需求真源是仓库根目录的 [AGENTS.MD](../AGENTS.MD)，动手前先读它。

## 仓库现状

- 已有实现：`src/script/campaign/mod/lft_legendary_faction_tags.lua`（运行时给外交界面的传奇派系名称追加标记）。
- 布局：`src/` 直接镜像 `.pack` 内部路径（`src/script/`、`src/ui/`、`src/text/`），`tools/` 放构建与校验脚本，`tests/` 放离线 mock 测试，`build/` 放产物且不纳入版本管理。
- 新增工具时把入口放在 `tools/`，并在此文件登记命令；本文档没有登记的命令视为不存在。

## 已登记命令

```powershell
# 离线单测（mock 掉 cm/core/UIComponent，不需要游戏）
python -m pip install lupa          # 首次
python tools/run_lua_tests.py

# 打包：纯 Python 写 PFH5，产物 build/legendary_faction_tags.pack，写完后自校验
python tools/build_pack.py
```

## 不可绕过的环境约束

- 本机没有安装《全面战争：战锤3》，也无法运行。任何"进游戏看一眼"的验证都不可用，改动只能靠静态证据支撑。
- 引擎 API 的名称与签名**不得凭记忆断言**，必须对照下列来源之一：
  - `Shazbot/WH3-Dump`：游戏 `db/`、`script/`、`ui/`、`text/`、`documentation/` 的导出镜像，含 CA 自带的脚本与 UI 脚本说明。
  - RPFM 的 WH3 schema（表结构真源）。
  - 已发布到创意工坊、且源码公开的 mod（例如 `esnqduke/WH3-Equipment-Presets` 的原生 UI 实现）。

## 领域结构（需要跨多个来源才能拼出的部分）

- 交付物是单个 `.pack`，包内路径必须与游戏数据树一一对应：`db/`、`script/`、`ui/`、`text/`。
- 战役入口必须位于 `script/campaign/mod/`：引擎会执行该目录下**所有** `.lua`，所以入口文件名要全局唯一（如 `<mod>_main.lua`），不要用 `main.lua`。
- 外交界面布局在 `ui/campaign ui/diplomacy_*.twui.xml`。覆盖同名布局会与其他 UI mod 冲突，**优先在运行时改文本**而不是改布局。
- 运行时 UI 访问模式：`find_uicomponent(core:get_ui_root(), '父组件id', '子组件id', ...)`；面板打开走监听器
  `core:add_listener(id, 'PanelOpenedCampaign', function(context) return context.string == 'diplomacy_...' end, true)`，
  用 `context.string` 区分具体是哪个面板。
- 派系名是运行时解析的本地化字符串，靠 `.loc` 覆盖无法只改某一个派系；做法是先取本地化名（如 `cm:get_local_faction_name`，签名先在 dump 的 `documentation/script/` 中确认），拼接后再用 `component:SetText(text, '')` 写回。
- 已核实的负面结论：`factions_tables` 没有 legendary 类字段，`start_pos_factions_tables` 只有 `is_major`。所以"传奇派系"必须由角色级数据（`is_legendary` 一类字段）或人工维护名单推导；下结论前先在 schema 或 dump 里确认字段真实存在。
- 已核实的正面结论：原版没有 `faction:is_legendary()`，但 `faction:faction_leader():character_details():is_unique()` 可用——CA 自己的 `script/campaign/wh3_campaign_subjugation.lua` 正是用 `is_unique()` 区分传奇领主与普通领主。CCO 的 `CcoCampaignFaction` 也没有 legendary 属性，所以纯 XML/CCO 绑定做不到，只能运行时改文本。

## 约定

- 引擎是 Lua 5.1：没有 `goto`、位运算符和 `//`。
- 全局变量、监听器 id、自建 uicomponent id 一律加 mod 前缀，避免与其他 mod 撞名。
- 每次取到的 uicomponent 都可能为 `nil`（面板未打开、被其他 mod 改过布局），必须判空，UI 操作建议包在 `pcall` 中，避免单点失败拖垮整段脚本。
- 日志用 `out(...)`，不要 `print`。
- 本地化文本至少覆盖 `en` 与 `zh`。

## 静态校验（本机当前能做的）

本机有 Python 3.12 与 Node；没有 `lua` / `luac`，也没有 RPFM。

```powershell
# Lua 语法（首次需 pip install luaparser）
python -c "from luaparser import ast; ast.parse(open(r'<file>.lua', encoding='utf-8').read())"

# twui.xml 结构
python -c "import xml.etree.ElementTree as ET; ET.parse(r'<file>.twui.xml')"
```

打包有两条路：`tools/build_pack.py` 直接写 PFH5（依据 rpfm_lib 的 `write_pfh5`，写完后逐文件回读校验，并用第三方 `pack_tool.py` 交叉验证过）；RPFM 可脱离游戏运行，但需要 WH3 schema。两者都只是**格式**校验，在真机验证之前，对外只能说"格式已静态校验"，不能说"mod 已可用"。
