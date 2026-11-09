# WH3 Legendary Faction Tags

在《全面战争：战锤 3》的战役外交界面里，给**传奇派系**（领袖为传奇领主的派系）的名称追加一个标记（默认 `★`）。

纯运行时 Lua 补丁：不覆盖任何原版 `.twui.xml`，因此不会与其他 UI 类 mod 抢布局。

> A runtime Lua patch that appends a marker to legendary faction names in the
> Total War: WARHAMMER III campaign diplomacy UI, without overriding any vanilla
> layout file.

## 覆盖范围

| 界面 | 组件（已从原版布局核对） |
|---|---|
| 外交主面板 · 派系列表 | `diplomacy_hud` → `faction_panel` → `sortable_list_factions` → `row` → `name` |
| 外交主面板 · 右侧派系标题 | `faction_title` / `dy_race_or_player_name` |
| 外交主面板 · 待处理谈判 | `label_faction_name` / `label_faction_name_sent` |
| 加入战争（`ComponentCreator` 动态生成的子面板） | `request_join_war` → `faction_list_item` |
| 战争协调 / 盟友被攻击 | `war_coordination`、`ally_attacked` |

脚本按组件 id 找到可见面板后遍历整棵子树，文本**恰好等于**某个传奇派系名的组件会被改写。多人局常见的 `派系名 (玩家名)` 形式也能识别。

## 判定依据

```lua
faction:faction_leader():character_details():is_unique()
```

- 原版没有 `faction:is_legendary()`，`factions` 表也没有 legendary 字段；
  `start_pos_factions_tables` 只有 `is_major`。
- `is_unique()` 正是 CA 自己在 `script/campaign/wh3_campaign_subjugation.lua`
  里区分传奇领主与普通领主用的判据。
- CCO 的 `CcoCampaignFaction` 同样没有 legendary 属性，列表行由引擎回调
  `DiplomacyFactionList` 生成、行内 `name` 没有 CCO 绑定 —— 所以只能运行时改文本。

## 安装

1. 运行 `python tools/build_pack.py` 生成 `build/legendary_faction_tags.pack`。
2. 把 `.pack` 放进 `<Steam>/steamapps/common/Warhammer 3/data/`。
3. 启动器 → 模组管理器里勾选并启用。

不需要 `modding.ini`、不需要缩略图、不需要任何注册文件：`script/campaign/mod/`
下的 Lua 会被原版 mod loader 自动执行。

## 开发

```powershell
python -m pip install lupa luaparser   # 首次
python tools/run_lua_tests.py          # 离线单测（mock cm/core/UIComponent）
python tools/build_pack.py             # 打包 + 逐文件回读自校验
```

- `src/` 直接镜像 `.pack` 内部路径。
- `tools/build_pack.py` 是纯 Python 的 PFH5 写入器，依据 `rpfm_lib` 的
  `write_pfh5`（header 28 字节、索引项为 `size + is_compressed + 路径`、
  不写依赖索引、不压缩）。无需 RPFM，也无需安装游戏。
- `tests/` 用 lupa 在真 Lua 里跑 mock 单测。
- `build/` 是产物目录，不纳入版本管理。

## 可调参数

`src/script/campaign/mod/lft_legendary_faction_tags.lua` 顶部：

| 变量 | 默认 | 说明 |
|---|---|---|
| `MARKER` | `" ★"` | 追加文本。字体缺字可换 `" *"`，或改用富文本 `[[img:ui/skins/default/xxx.png]]` |
| `POLL_MS` | `400` | 面板可见时的刷新间隔（毫秒） |
| `DEBUG` | `false` | `true` 时向脚本日志输出 `[lft] patching: ...` |
| `PANEL_IDS` | 见文件 | 需要扫描的顶层面板 id |

## 验证状态

**已完成的静态验证**

- `luaparser` 语法解析通过。
- mock 单测覆盖：传奇加标记、普通派系不动、多人局后缀识别、多次轮询不重复叠加、
  引擎重写文本后自动补回、面板不可见时不写入、回合刷新监听器可用。
- 产物格式：`build_pack.py` 自校验 + 第三方独立解析器读回，`flags=0x3`、
  单文件、未压缩，解包内容 SHA256 与源码一致。

**尚未验证（需要真机）**

本项目在**没有安装游戏**的机器上开发，以下三点只能进游戏确认：

1. `★` 在 `body_12` / `header_16` 字体里是否有字形（没有就改成 `" *"`）。
2. 引擎刷新列表时是否会覆盖行文本（脚本每 400ms 自愈，但可能出现闪烁）。
3. 面板 id 在运行时是否与布局文件一致。

### 游戏内验收清单

1. 新开帝国战役（卡尔·弗兰兹），打开外交面板 → Reikland 等应显示 `Reikland ★`。
2. 点选传奇派系 → 右侧标题名称带标记。
3. 切到战争协调 / 让盟友拉你参战 → 双方战争方名称带标记。
4. 关闭面板再打开、切换标签、鼠标悬停 → 标记不消失、不变成 `★★`。

## 已知限制

- 领袖暂时阵亡时，派系按 `cqi` 记住的传奇状态不会丢失（缓存只累积）。
- 若某 mod 改了外交布局的组件 id，该面板会被静默跳过，不影响其它面板。
- 纯 UI 文本修改是本机行为，不涉及战役模型，多人局不会因此不同步。

## 许可

MIT，见 [LICENSE](./LICENSE)。
