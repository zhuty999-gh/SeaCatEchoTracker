# EchoTracker 重构设计：从光环读取改为施法序列推算

## 1. 为什么必须换路子

原本的实现是「每 0.1 秒扫描全团光环，读出 Echo 的 `expirationTime`，算出剩余时间」。这条路在 12.1 已经彻底走不通。

12.1.0 的官方 API 变更原文：当光环处于保密状态时（**战斗、boss 战、大秘境、PvP**），所有 UnitAura 系列 API 对插件而言「要么返回完全 secret 的值，要么返回 nil」，并且「AuraData 结构现在始终是完全 secret 的」。

具体表现为两个阶段的失败，我们都实测撞到了：

| 阶段 | 现象 | 原因 |
| --- | --- | --- |
| 修复前 | 进战斗后每 0.1 秒报错，必须 reload | 对 secret 值做了比较、算术、`string.format` |
| 加了 `issecretvalue` 防御后 | 不报错，但图标完全消失 | `GetAuraDataBySpellName` 带 `RequiresNonSecretAuraSpellName` 约束，光环为 secret 时直接返回 nil |

暴雪论坛上对「有没有合法办法在战斗中按 spellID 检查某个 buff 是否存在」的回答是明确的「没有」。所以**任何基于读取光环的方案都是死路**，不需要再尝试其他 UnitAura 接口。

### 1.1 另一条已知可行但不适用的路

DandersFrames 走的是原生 `AuraContainer` 的「read-free」路线：

```lua
CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
  :SetUnit(unit)
  :AddAuraSlot(filter, initializeFrame)   -- includeSpellIDs = { [364343] = true }
  :SetEnabled(true)                        -- 必须最后调用
```

然后把区域交给引擎：`slot:SetIcon()` / `SetDurationCooldown()` / `SetDurationText()` / `SetApplicationCount()` / `SetDurationBar()`。之后 C 侧每帧直接往这些区域里写，Lua 全程不读数据，因此不受 secret 限制。

**这条路能显示，但无法计数。** slot 的显示/隐藏由引擎的 `Enum.SecretAspect.Shown` 控制，Lua 无法知道有几个 slot 正在亮着。EchoTracker 的核心卖点「总数 + 最短剩余时间」恰好需要这个数字，所以这条路做不出原本的形态。

另外两个坑记录在此以免重复踩：`CreateFrame("AuraContainer")` 在战斗锁定期间会导致**不可捕获的致命崩溃**（必须战斗外预建）；堆叠数的 formatter 是明确禁止的 secret 陷阱。

## 2. 新方案的核心原理

不读光环，改为**用自己的施法序列在插件内部维护一个 Echo 状态机**。

成立的关键依据是 `SecretWhenUnitSpellCastRestricted` 的规则原文：施法信息只在「被查询的单位**不是玩家或其宠物**」时才变成 secret。也就是说**玩家自己的施法是豁免的**。

活体验证：同目录的 `!WilduTools/ui/components/gcd_history.lua` 用
`RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")` 直接读 `spellID`，全程没有任何
`issecretvalue` 保护，而该模块在 12.x 下正常工作。

### 2.1 数据源白名单

这套方案只依赖以下输入，**全部是非 secret 的**：

| 数据 | 来源 | 是否 secret |
| --- | --- | --- |
| 我施放了哪个法术 | `UNIT_SPELLCAST_SUCCEEDED`（unit = `player`） | 否（玩家豁免） |
| 施放的目标 | `UNIT_SPELLCAST_SENT` 第 2 个参数 | 否（队友是玩家单位） |
| 施放的时刻 | `GetTime()` / `GetTimePreciseSec()` | 否（本地时钟） |
| Echo 的持续时间 | 战斗外校准后存入 SavedVariables | 否（战斗外光环可读） |
| 法术名称 / 图标 | `C_Spell.GetSpellInfo(spellID)` | 否 |
| 法术是否已学 | `C_SpellBook.IsSpellInSpellBook(spellID, 0/1)` | 否 |

### 2.2 绝对不能碰的东西

以下操作会立刻把我们打回原点，任何时候都不允许出现在战斗路径上：

- 读取 `AuraData` 的任何字段（`expirationTime`、`duration`、`sourceUnit`、`applications`、`spellId`）
- 调用 `C_UnitAuras.*` 的任何查询接口
- 监听 `UNIT_AURA`（12.1 起载荷完全 secret）
- 从已绑定原生 setter 的 widget 上 `GetText()` / `GetWidth()` 读回数值

唯一例外是**战斗外校准**（见第 4 节），它必须由 `C_RestrictedActions` 明确确认限制未生效时才执行。

## 3. 机制事实与法术表

以下由玩家实测确认，是整个状态机的基础：

- **所有活跃 Echo 一起被消耗**，没有例外。一个消耗类法术触发全部 Echo。
- **同一目标重复施放 Echo 是刷新**，不叠加。
- Echo 基础持续 **15 秒**；天赋 `376240` 每点 +15%，最多 2 点（满级 +30% → 19.5 秒）。

### 3.1 施加 Echo

| spellID | 法术 | 目标数 |
| --- | --- | --- |
| `364343` | Echo | 单目标 |
| `373861` | Temporal Anomaly | **最多 5 个盟友**，球飞行途中逐个施加 |

### 3.2 额外目标天赋（1242031）

施放 **Emerald Blossom（355913）** 会获得 buff `1242759`,每层使下一个 Echo 额外命中一个盟友。**最多 2 层,持续 15 秒。**

**所有层共享一个计时器**,每次施放 Emerald Blossom 都会把整个 buff 刷新回 15 秒——包括已经满 2 层时（此时层数不增,但时长照样刷新）。所以这里存的是「层数 + 单个到期时间」,不是每层各自的到期时间。消耗一层不会缩短剩余层的时长。

**Emerald Blossom 本身不消耗 Echo**（玩家确认）,所以它既不在 `APPLY_SPELLS` 也不在 `CONSUME_SPELLS` 里,而是在 `ResolveCast` 开头单独处理。

buff `1242759` 本身在战斗中读不到（和所有光环一样是 secret）,但**不需要读**:它的产生和消耗都绑定在自己的施法上,所以用同一套施法序列推算即可。实现为 `extraTargetStacks`(层数)加 `extraTargetExpiry`(共享到期时间);施放 Echo 时层数减一,并额外记一个匿名 Echo。

注意 `ClearAll()`（消耗 Echo）**不清空这些层数**——它们是独立资源,只有 Echo 施放才消耗。

> 当前假设:一次 Echo 消耗 **1 层**,额外 1 个目标。若实际是「一次消耗全部层数、额外 N 个目标」,需要改 `ResolveCast` 里那段弹栈逻辑。

### 3.3 消耗 Echo

| spellID | 法术 | 条件 |
| --- | --- | --- |
| `366155` | Reversion | 无条件 |
| `1256581` | 疑似 Merithra's Blessing（强化 Reversion） | 无条件，**名称待游戏内自检确认** |
| `360995` | Verdant Embrace | 无条件 |
| `355936` | Dream Breath | 无条件 |
| `361469` | Living Flame | **仅友方目标**（打敌人不消耗） |

`1256581` 在公开数据库里查不到确切条目。12.1 的攻略反复提到新 Apex 天赋 Merithra's Blessing 会把下一个 Reversion 转变为强化版，且明确建议用它来消耗 Echo，因此高度怀疑是它。**不靠猜**：插件启动时用 `C_Spell.GetSpellInfo` 把所有配置法术的名称打印出来，由玩家核对。

## 4. 状态机设计

### 4.1 数据结构

因为「一起消耗」，消耗逻辑退化为清空整个集合，不需要判断消耗哪一个。因为「同目标刷新」，施加 Echo 时需要按目标去重。

```lua
-- 单目标 Echo：key = 目标名，value = 到期时间（绝对时间）
local targeted = {}
-- Temporal Anomaly 批次：只记到期时间，数量未知
local batches = {}
```

显示的「最早到期」= `targeted` 和 `batches` 中所有到期时间的最小值。

不做 target 去重会导致什么：对同一个人连放两次 Echo，实际只有 1 个（刷新到更晚），但插件会保留第一次的较早到期时间 → 偏早、偏保守。保守本身安全，但既然 `UNIT_SPELLCAST_SENT` 能拿到目标，就没有理由不做准。

### 4.2 事件流

```
UNIT_SPELLCAST_SENT  (unit == "player")
    └─ 记下 castGUID → target 的映射（SUCCEEDED 不带目标，必须在这里存）

UNIT_SPELLCAST_SUCCEEDED  (unit == "player")
    ├─ 364343 (Echo)            → targeted[target] = now + duration
    ├─ 373861 (Temporal Anomaly)→ batches[#batches+1] = now + duration
    ├─ 361469 (Living Flame)    → 目标是友方才清空，否则忽略
    └─ 其他消耗类法术            → 清空 targeted 和 batches

OnUpdate (节流 0.1s)
    └─ 移除已过期条目，渲染最早到期的剩余时间
```

### 3.2 事件流

```
UNIT_SPELLCAST_SENT  (unit == "player")
    └─ 记下 castGUID → target 的映射（SUCCEEDED 不带目标，必须在这里存）

UNIT_SPELLCAST_SUCCEEDED  (unit == "player")
    ├─ spellID == ECHO_SPELL_ID
    │     └─ echoes[target] = { expiry = now + ECHO_DURATION, castAt = now }
    │
    └─ spellID ∈ 消耗列表
          └─ 按策略移除一个或多个 echoes 条目

OnUpdate (节流 0.1s)
    └─ 清掉 expiry <= now 的条目，渲染剩余时间
```

`UNIT_SPELLCAST_SENT` 的参数顺序和 `SUCCEEDED` 不同，这是个容易写错的地方：

```
UNIT_SPELLCAST_SENT:      unit, target, castGUID, spellID
UNIT_SPELLCAST_SUCCEEDED: unit, castGUID, spellID, castBarID
```

WilduTools 用重命名参数的方式处理这个差异（`gcd_history.lua:545-552`），但它**丢弃了 target**。我们需要 target，所以要单独写一个 handler，不能照抄。

另外 `UNIT_SPELLCAST_SENT` 无法用 `RegisterUnitEvent` 过滤（WilduTools 也是用 `RegisterEvent` 后在 handler 里判断 `unit ~= "player"` 就返回）。

## 4. 战斗外自动校准

这是整个设计里最有价值的一环：**战斗外光环数据是明文的**，所以可以用真实数据反过来校准推算参数，不需要硬编码任何数字。

### 4.1 校准持续时间

战斗外施放 Echo 后读一次真实的 `duration`，存进 SavedVariables。这样天赋改动、等级变化、后续平衡调整都自动跟上。

**不要硬编码 Echo 的持续时间。** 当前代码里的 `ECHO_SPELL_ID = 364343` 是可靠的，但持续时间必须靠校准得到，第一次运行前没有可信的默认值。

### 4.2 自学习消耗列表

同理，哪些法术消耗 Echo 也不该硬编码。战斗外流程：施放某法术前后各读一次真实 Echo 数量，如果减少了，就把该 spellID 记进消耗列表。跑几场日常就能自动学全，而且天然适配后续的技能改动。

### 4.3 自我验证（精度自检）

战斗外可以同时拿到「推算值」和「真实值」，所以能直接算出误差并展示给用户。这让「这个插件准不准」从玄学变成可量化的东西，也是发现消耗规则遗漏的最快途径。

## 5. 精度边界（必须诚实告知用户）

因为「一起消耗、无例外」，消耗判定不再是启发式——它是确定的。这让精度边界比最初设想的窄得多。

**准确的部分**：最早 Echo 的剩余时间。消耗时机确定（自己的施法事件），施加时机确定，时长确定（校准得到）。

**仍然存在的误差来源**：

- **Temporal Anomaly 的施加延迟**。球飞行途中才逐个施加，插件按施放时刻计算。第一个被经过的盟友几乎立即获得 Echo，所以对「最早到期」的影响小于 1 秒，且方向偏保守（真实到期比显示的更晚）。
- **Echo 总数是估算值,默认只在团队副本内显示**。TA 一次给最多 5 个盟友上 Echo,插件不知道球实际经过了谁。0.4.1 曾整体移除计数,0.5.0 以「团队副本内按固定 5 计算」的形式恢复——20 人团里球几乎必然清满 5 个,这个近似站得住。

  默认在副本外隐藏,因为小队里队伍分散、球经常碰不到 5 个,数字会偏高。但注意**大秘境的 `instanceType` 是 `party` 而不是 `raid`**,所以默认设置下大秘境里也看不到计数。0.5.2 因此加了「在团队副本外也显示计数」开关(`countOutsideRaid`),让玩家自己权衡。

  残余误差:那 5 个 Echo 的归属是匿名的,所以之后对某人施放 Echo 时无法判断这个人是否已在其中。如果在,实际是刷新、总数不变,但插件会算 +1。**偏差方向朝上**,和倒计时的偏保守方向相反,所以计数不能当精确值用。
- **Living Flame 的友方判定**。`UNIT_SPELLCAST_SENT` 给的是名字字符串而非 unit token，需要在队伍/团队里匹配名字来判断是否友方。非 PvP 场景下队友名字可读（`SecretWhenUnitIdentityRestricted` 对 party/raid 成员豁免），但跨服同名、宠物、以及不产生 SENT 事件的施法方式会导致判定失败。判定失败时的默认行为选择**不消耗**,即偏向保守。
- **不产生 SENT 事件的施法路径**。此时拿不到目标，Echo 会退化成无目标条目（无法去重刷新），影响同上：偏早、偏保守。

结论：这是一个**准确度足够高、且误差方向一致偏保守**的倒计时。所有已知误差都让它「显得比实际更早过期」，对「我该不该续 Echo」这个决策是安全的一侧。

### 5.1 蓄力法术（Dream Breath）

`355936` 是 empowered 法术。**它的 `UNIT_SPELLCAST_SUCCEEDED` 在按下、开始蓄力的瞬间就触发,而不是松手释放时**（玩家实测）。所以不能在 SUCCEEDED 里处理它——蓄力中途取消会导致 Echo 被误消耗。

正确做法是改用 `UNIT_SPELLCAST_EMPOWER_STOP`：

```
UNIT_SPELLCAST_EMPOWER_STOP: unitTarget, castGUID, spellID, complete, interruptedBy, castBarID
```

`complete` 是布尔值（11.0.0 加入）,取消或被打断时为 false。暴雪自己的
`CastingBarFrame.lua` 就是用它来区分正常结束和打断的。

实现上 `EMPOWERED_SPELLS` 表标记哪些法术走这条路：这些法术在 SUCCEEDED 里直接跳过,且**故意不清除 castGUID → target 的映射**,留给 EMPOWER_STOP 取用。

> ⚠ 以后往 `APPLY_SPELLS` 或 `CONSUME_SPELLS` 里加任何 empowered 法术（例如 Spiritbloom）,必须同时加进 `EMPOWERED_SPELLS`,否则取消蓄力仍会消耗 Echo。

**曾经的错误结论记录在此以免重复**：`!WilduTools/ui/components/gcd_history.lua` 的注释声称「Empowered spells (Evoker) also look like channels but fire SUCCEEDED on release with no CHANNEL_STOP」。这条注释是不可靠的——该插件从未注册过任何 `UNIT_SPELLCAST_EMPOWER_*` 事件（grep 零匹配）,所以那是作者的推断而非实测。不要再引用它。

## 6. 实现阶段

分三步，每步都能独立跑起来验证。

**阶段一：纯倒计时（零误差，先跑通）**
只做「上次施放 Echo 的倒计时」，不做任何消耗判定。这一步验证事件监听和渲染链路是否正常，风险最低。

**阶段二：战斗外校准**
加持续时间校准和自我验证。此时插件已经可用且数据可信。

**阶段三：消耗判定**
加自学习消耗列表和 per-target 追踪，把「当前有几个 Echo」也做出来。这一步引入误差，需要配合阶段二的自我验证来调。

## 7. 现有代码的复用情况

`EchoTracker.lua` 里可以整段保留的部分（这些和光环读取无关）：

- 全部本地化表（含这次补的简中/繁中三条）
- 设置面板、页签、滑块、颜色选择器、小地图按钮、斜杠命令
- 图标 / 环形 / 文字的渲染和样式逻辑，以及 `SetRadialCooldown()`
- 之前修的四个真实缺陷：TOC `120100`、隐藏时不吞鼠标点击、面板不吞按键、`atan2` 与字体兜底

需要**整体替换**的只有 `frame:SetScript("OnUpdate", ...)` 里那段扫描逻辑（当前的 `CheckUnit` / `ScanEchoes`），以及随之失效的 `IsSecret` 防御分支。

设置面板里有几项在新方案下语义变了，需要复查：警报阈值仍然可用（因为剩余时间重新变成明文了），但「始终显示」和层数相关的显示需要根据阶段三的进度调整。

## 8. 待确认事项

- Echo 的真实持续时间 —— 交由 4.1 的校准流程得到，不猜
- 消耗 Echo 的法术清单 —— 交由 4.2 的自学习得到，不猜
- 群体治疗一次消耗几个 Echo 的具体规则 —— 需要在战斗外用自我验证观察
- 显示形态 —— 用户尚未决定（沿用现有图标+环形，还是简化为纯数字）
