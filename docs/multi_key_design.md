# 多密钥卡片设计方案（一张卡片承载同一供应商的多把密钥）

> 状态：设计定稿，待评审后实施
> 关联需求：主界面卡片下拉切换、配置表单支持多密钥、工具页与实际使用联动、详情抽屉仅切换/复制

---

## 1. 目标与范围

让**一张密钥卡片 = 一个供应商条目**，内部承载 **N 把密钥值（子密钥）**，同一卡片的子密钥共享该卡片的全部其他配置（请求地址 / Base URL / 模型 / 工具开关 / 标签 / 过期时间 / 备注等），**仅密钥值及其附属信息不同**。

词表（全文统一）：

| 词 | 含义 |
| --- | --- |
| 卡片 / 条目 | `ai_keys` 表的一行，主界面一个 `KeyCard` |
| 子密钥 / 密钥项 | 卡片内的一把密钥值（entry） |
| 当前密钥 | 卡片内被标记为 `active` 的密钥项，`key_value` 镜像它的值 |
| 生效中 | 某工具配置文件里实际写入的密钥值，正好匹配该卡片的某个密钥项 |

**本次范围**：同卡片内多密钥。**不做**：跨卡片（不同供应商）的分组折叠——同供应商需要独立配置时，仍然新增独立卡片。

**已与用户确认的三条语义**（实现依据）：

1. 主界面下拉切换「当前密钥」时，若该卡片正被某工具使用（生效中），**立即用新密钥改写该工具的配置文件**（与现有「编辑密钥值后自动刷新生效工具配置」行为一致）。
2. 工具页卡片上**先选子密钥、再点卡片应用**：卡片要显示实际生效的那把，可在卡片上切换选中，点击卡片把选中的那把写入该工具。
3. 每把子密钥拥有独立字段：**别名、独立校验状态、独立最后使用时间、独立备注**。

---

## 2. 现状（实现所依赖的关键事实）

| 位置 | 事实 |
| --- | --- |
| `lib/models/ai_key.dart` | `AIKey` 单值 `keyValue`；`keyNonce`；`isValidated`；`lastUsedAt` 均为卡片级 |
| `lib/services/database_service.dart` | `schemaVersion = 22`（第 45 行）；`ai_keys` 建表在 `_onCreate`（第 186 行）；`_onUpgrade` 用 `_addColumnIfNotExists(db, table, col, def)`（第 324 行）；`_onDowngrade` 拒绝打开更高版本库 |
| 加密 | 设置主密码后 `key_value` 为密文 JSON（以 `{` 开头，nonce 在密文内），明文时直接存原文；`CryptService.encrypt/decrypt`；`KeyManagerViewModel.decryptKeyValue(String)` |
| 掩码 | `lib/utils/key_mask.dart`：`KeyMaskCache` 按 **key id(int)** 存掩码；`isEncryptedKeyValue(AIKey)`；`maskKeyForCard(AIKey)` |
| 工具当前密钥检测 | `KeyManagerViewModel.getCurrentClaudeCodeKey/Codex/Gemini/ClaudeDesktop`：读工具配置里的 API Key → 遍历候选卡片 → **逐值解密比对**（第 913/995/1195/1467 行） |
| 生效状态出口 | `currentKeyIds`（`Map<AiToolType,int?>`，第 54 行）→ 被 `main_screen`(344/407/728/764/1080)、`key_form_page`(1408)、`key_details_dialog`(421)、`app_switcher`(291/304)、`key_card`(61/86/1111/1444/1456/1702/1709/1719/1773/1787) 消费 |
| 工具切换入口 | `switchClaudeCodeProvider/switchCodexProvider/switchGeminiProvider/switchClaudeDesktopProvider(int keyId)`；`applyKeyToTool(tool, keyId)` + `ToolProviderService`；`OpenClawConfigService.applyProviderKey` |
| 编辑后刷新 | `_refreshActiveConfigIfNeeded(key, {previous})`（第 1312 行）+ `_refreshToolProvidersIfApplied`（第 1634 行） |
| 复制 / 最后使用 | `copyKeyToClipboard(int id)`（第 649 行）内含 `_databaseService.updateLastUsed(id)` |
| 缓存 | `KeyCacheService` 按 key id 存 **模型列表 / 余额 / 校验状态**（`key_models_<id>` 等） |
| 卡片 UI | `key_card.dart`：主界面用 v3 卡片（`_buildV3Content`，第 1045 行，**头部只显示名称+平台，不显示密钥**）；工具页用 lens 卡片（第 950 行，头部第二行显示 `平台 · 掩码`）。v3 底栏是**定宽五槽位**（58/28/28/28/28，第 1130 行），**不可再插入槽位** |
| 详情抽屉 | `key_details_dialog.dart` `_body`（第 417 行）：`API 密钥` 字段（显示/复制）+ 工具开关表 |
| 表单 | `key_form_page.dart`：单个 `_keyValueController`（第 165 行建、第 805 行渲染、第 831 行粘贴、校验用 `_handleValidate`）；保存时 6 处 `keyValue: _keyValueController.text...`（约 1708/1751/1820/1912/2635/2766 行） |
| 导出 / 导入 | `export_service.dart` `exportKeys`(27) 与 `exportKeysPlain`(210)：每张卡片产出 `{..., 'key_value': <明文>}`，包在 `{version, key_count, keys:[...], official_api_keys}` 中 |

---

## 3. 数据模型

### 3.1 新增列 `key_entries`（单列 JSON）

沿用 `tool_configs` / `claude_code_config` 的 JSON 列先例，在 `ai_keys` 增加一列：

```sql
ALTER TABLE ai_keys ADD COLUMN key_entries TEXT   -- 可空
```

内容为**单一 JSON 对象**（而非裸数组，便于放 `active`）：

```jsonc
{
  "active": 1,                  // 当前密钥下标；0 表示第一把
  "items": [
    {
      "label": "主号",           // 别名（可空 → UI 回退显示「密钥 1」）
      "value": "<与 key_value 相同形态：明文 或 加密JSON字符串>",
      "notes": "购买渠道 xx",     // 可空
      "validated": true,        // 该把的独立校验状态
      "lastUsedAt": "2026-10-15T10:00:00.000Z", // 可空
      "createdAt": "2026-10-15T09:00:00.000Z"
    }
  ]
}
```

### 3.2 `key_value` 继续镜像当前密钥（关键设计）

**`key_value` 列保持"当前密钥的值"语义不变**，由 `key_entries.items[active].value` 决定。

这样做的收益：`switchXxxProvider`、`ToolProviderService`、`OpenClawConfigService`、状态栏菜单、统计、`getAllKeys`、导出、导入等**十几处基于「行 + 单一 key_value」的链路基本零改动**。

一致性由模型层保证（唯一写入口）：

- `AIKey.copyWith(activeKeyIndex: n)` → 同时改 `keyEntries.active` 与 `keyValue = items[n].value`；
- `AIKey.withKeyEntries(items, active)` → 同上；
- 任何写 DB 的路径都只经由这两个方法产出 `AIKey`，禁止单独改 `keyValue`。

**兼容性**：`key_entries` 为空/NULL 时，等价于「只有一把密钥」，`key_value` 即那唯一一把 → 老数据零迁移成本，老代码路径全部照常。

### 3.3 模型层 `AIKey` 扩展

```dart
class KeyEntry {
  final String value;      // 与 key_value 同形态（明文或密文 JSON）
  final String? label;
  final String? notes;
  final bool validated;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;
  // copyWith / toJson / fromJson
}

// AIKey 新增
final List<KeyEntry> keyEntries;   // 长度 >= 1（无该列时构造为 [KeyEntry(value: keyValue)]）
final int activeKeyIndex;          // 0..len-1

KeyEntry get activeEntry => keyEntries[activeKeyIndex];
bool get hasMultipleKeys => keyEntries.length > 1;

// 解析（与 parseToolConfigs 同风格，容错返回）
static (List<KeyEntry>, int) parseKeyEntries(Object? raw, String fallbackValue);
```

同时把卡片级 `isValidated` / `lastUsedAt` 定义为**当前密钥的镜像**（`toMap()` 时取 `activeEntry` 的值），保证老 UI（徽章、排序）行为不变。`props` 加入 `keyEntries`、`activeKeyIndex`。

### 3.4 加密与掩码

- 加密粒度 = **每把子密钥各自加密**。`items[i].value` 与现在的 `key_value` 完全同形态（明文，或以 `{` 开头、内含 nonce 的密文）。新增 `isEncryptedValue(String v) => v.trimLeft().startsWith('{')`。
- 迁移后 `keyNonce` 列不再有新增用途（保持可空、兼容旧数据）。
- `KeyMaskCache` 的键从 `int id` 扩展为 **`id#index`**：
  - `put(int id, int index, String plain)` / `get(int id, int index)`；
  - `maskKeyForCard(AIKey)` → `maskKeyForKey(AIKey key, int entryIndex)`，并对 `entryIndex` 缺省取 `activeKeyIndex`；
  - 卡片 / 详情 / 工具页 / 下拉统一用「当前或指定的那张」取掩码。
- `_refreshMaskCache()`（viewmodel 第 218 行）改为**遍历每把子密钥解密并写 `id#index`**。

### 3.5 迁移（schemaVersion 22 → 23）

在 `_onUpgrade` 末尾追加：

```dart
if (oldVersion < 23) {
  await _addColumnIfNotExists(db, 'ai_keys', 'key_entries', 'TEXT');
  // 老行不写默认值：key_entries 为 NULL 即「单密钥」，
  // 由模型层在 fromMap 时用 key_value 合成唯一的 KeyEntry。
}
```

- 无需数据回填，无需 `UPDATE`。
- `_onDowngrade` 的降级保护不变；迁移前会自动备份（`backupBeforeMigrationIfNeeded`）。
- 单测：`runUpgradeForTest` 22→23 后列存在；`runCreateForTest` 建表含 `key_entries`。

---

## 4. 数据访问与 ViewModel

### 4.1 数据库（`database_service.dart`）

现有查询（`getAllKeys` / `getClaudeCodeKeys` / `getCodexKeys` / `getGeminiKeys` / `getClaudeDesktopKeys` / `getKeyById`）**全部不用改**——它们仍按 `enable_xxx` 过滤行，`key_entries` 随 `fromMap` 一并解析。

新增/改动仅三处：

- `updateKey`：INSERT/UPDATE 需要带上 `key_entries`（`AIKey.toMap()` 已经产出）。
- `updateLastUsed(int id)` → `updateEntryLastUsed(int id, int index, DateTime at)`：读该行 → 改 `items[index].lastUsedAt`（若 index 是 active，同步行的 `last_used_at`）→ 写回。
- `secureDeleteKey`：行为不变（整行删除，连带多密钥一起删）。

### 4.2 `KeyManagerViewModel`

**当前密钥的读写**

```dart
/// 主界面下拉：切换卡片的当前密钥
Future<bool> setActiveKeyEntry(int keyId, int entryIndex);
```
内部顺序（对应"已确认语义 1"）：

1. 读该 key → 校验 `entryIndex` 合法 → 构造 `updated = key.copyWith(activeKeyIndex: entryIndex)`；
2. 先改内存（`_allKeys` / `_filteredKeys`）+ `notifyListeners()`，UI 立即响应；
3. 写 DB；
4. **工具联动改写**：对该卡片当前「生效中」的每个工具，用新当前密钥的值重写配置（复用第 5 节的 `_rewriteActiveTools`）；
5. `_notifyStatusBarMenuUpdate()`。

**当前密钥的检测（值匹配链路升级）**

`getCurrentClaudeCodeKey/Codex/Gemini/ClaudeDesktop` 由「遍历卡片比 `keyValue`」升级为「**遍历卡片 → 遍历该卡片每个密钥项 → 逐一解密比对**」，返回 `(AIKey?, int entryIndex)`，并缓存到新的 `_currentXxxKeyEntry`：

```dart
class ActiveKeyRef { final int keyId; final int entryIndex; }

int? _currentClaudeCodeKeyId; int? _currentClaudeCodeEntryIndex;  // 其余三个工具同理
```

对外暴露两个 getter：

- `currentKeyRefs` → `Map<AiToolType, ActiveKeyRef?>`：工具页/详情抽屉判断"哪把生效"用；
- `currentKeyIds` → `Map<AiToolType,int?>`（由 `currentKeyRefs` 派生）：保留给只关心"卡片是否生效"的旧调用点（`main_screen:407`、`app_switcher`、卡片工具 chip）。

**复制 / 最后使用**

```dart
Future<bool> copyKeyToClipboard(int id, {int? entryIndex});  // 默认当前密钥
```
内部：取指定项的值解密 → `copyWithAutoClear` → `updateEntryLastUsed(id, index)`。

**删除密钥项**

```dart
Future<bool> deleteKeyEntry(int keyId, int entryIndex);
```
删到 0 把时禁止（UI 禁用）；若删的是 active，`active` 收敛到 `clamp(0, len-1)`；随后走一次与 `setActiveKeyEntry` 相同的联动改写。

---

## 5. 工具联动（本次最需要小心的部分）

### 5.1 切换即改写

新增统一入口，避免在 6 个工具里重复：

```dart
/// 该卡片当前在哪些工具里生效 → 用当前密钥重写这些工具的配置文件
Future<void> _rewriteActiveTools(AIKey key);
```
实现方式与现有 `_refreshActiveConfigIfNeeded`（第 1312 行）保持同一套判断：

- Claude Code / Codex（含地区过滤与 `isRestrictedInChina` 判断）/ Gemini / Claude Desktop：若 `currentKeyRefs[tool]?.keyId == key.id` → `backupConfig()` + `switchProvider(key)`；
- OpenClaw：`OpenClawConfigService.getAppliedKeyIds()` 命中 → `applyProviderKey(...)`；
- 更多工具（`ToolProviderService.tools`）：`appliedKeyIds(tool)` 命中 → `apply(tool, key, plain, makeDefault: isDefault)`；`grokBuild` 走按值比较的分支。

> `switchProvider(key)` 内部读的是 `key.keyValue`，而 `keyValue` 已镜像新当前密钥 → **工具侧服务无需任何改动**。

### 5.2 工具页「先选子密钥、再应用」

- `switchClaudeCodeProvider/switchCodexProvider/switchGeminiProvider/switchClaudeDesktopProvider(int keyId, {int? entryIndex})`：默认取卡片的当前密钥；传入 `entryIndex` 时写入指定那把。
- `applyKeyToTool(tool, keyId, {int? entryIndex, bool makeDefault})`：同上，先 `key.copyWith(activeKeyIndex: entryIndex)` 再 `apply`（`apply` 读 `key.value`/解密值）。
- 工具页卡片把"生效中的那把"标出来：`currentKeyRefs[tool]` 的 `(keyId, entryIndex)` 与该卡片比对，命中即 `● 生效中`，并在子密钥选择器上高亮那一把。

### 5.3 三处状态出口的呈现

| 位置 | 现在 | 之后 |
| --- | --- | --- |
| 卡片工具 chip（`_ToolStatusChips`/`_V3ToolRow`） | `currentKeyIds[t] == aiKey.id` | 同上（卡片级不变）；多密钥时在 chip 上追加当前生效项的别名（如 `Claude Code · 主号`） |
| 详情抽屉工具行 | `ids[t] == _key.id` → 生效中 | 同上；额外显示生效的是哪一把 |
| 侧栏 `app_switcher` | `currentKeyIds[tool]` 取卡片 | 不变（标签仍用卡片名；需要时可补别名后缀） |

---

## 6. UI 规格

**总原则：不改变现有布局骨架与 Token**，多密钥以"附加控件"形式出现；单密钥卡片与今天**像素一致**（选择器不渲染）。

### 6.1 主界面卡片（v3）下拉切换

- **落点**：头部第二行（当前只显示 `平台`）。多密钥时改为 `平台`＋` · `＋**密钥选择触发器**。
- **触发器**（`KcKeyEntryPicker`，新增共享组件）：
  - 外观 = 普通 caption 文本（`KcType.caption`, `cs.mutedForeground`）+ 尾部 `Icons.expand_more` 14px；
  - 文案 = 当前密钥别名（无别名则 `密钥 N`）；hover 时文字转 `kc.actionText` 并出现 `kc.subtle` 圆角底（复用 `_labeledSlot` 的 hover 风格）；
  - 点击 → `KcMenu` 弹出列表（复用 `kc_menu.dart`，与卡片 `⋯` 菜单同一点击弹出、同一项高亮规则）。
- **弹出项**：`✓`(当前项) + 别名 + `掩码`（mono）+ 校验状态点（`kc.ok` / `kc.danger` / 灰）。
- **注意**：v3 底栏是定宽五槽位，**选择器绝不放入底栏**；面包屑行高 20 不变，避免卡片位移。

线框（多密钥时）：
```
┌───────────────────────────────────────────────┐
│ [logo] 供应商名  ★                             │
│        平台 · 主号 ▾                           │   ← 触发器（单密钥时无 ▾、无交互）
│ [正常] [分类] [模型 12] [标签…]                 │   ← 徽章行（不变）
│ ● Claude Code · 主号   ○ Codex   ＋            │   ← 工具行（多密钥时 chip 带别名）
├───────────────────────────────────────────────┤
│ [密钥 58] [地址 58] [✎ 28] [↗ 28]        [⋯ 28] │   ← 定宽五槽位（不变）
└───────────────────────────────────────────────┘
```

### 6.2 详情抽屉（`key_details_dialog.dart`）

**仅用于切换查看 / 复制同一卡片的各把密钥，不改动工具配置与当前密钥**（局部 state）。

- 在 `API 密钥` 字段上方插入一行**密钥选择器**（多密钥时才显示）：
  - 形态：`KcSegmented<int>`（复用现有组件，与「概览 / 模型」页签同规格）或横向滚动的小 chip 列表；每项 = 别名（+ 校验点）。
  - 默认选中 = 卡片当前密钥；右上角对当前密钥加 `● 当前` 小字，避免"抽屉里选的"与"卡片当前"混淆。
- 下方 `API 密钥` 字段整体绑定**抽屉选中的那一把**：`显示/隐藏`、`复制` 均作用于它；`复制` 调 `copyKeyToClipboard(id, entryIndex: 选中项)`。
- 逐把复制：选择器每一项右侧提供 `copy_outlined`，一键复制该把（Toast 只写"名称 + 密钥 N"，不回显内容）。
- 「复制为环境变量」`buildEnvExport(k)` 使用**抽屉当前选中的那把**的值。
- 工具开关表及其"设为当前"逻辑维持卡片级（不受抽屉选择影响）。

### 6.3 配置表单（`key_form_page.dart`）

把"密钥值"单输入改为**密钥项列表编辑**，视觉沿用 `ImeSafeTextField` 规格（同圆角、同 `prefixIcon` 键图标、同 `suffixIcon` 图标组）：

```
密钥值 *                                    [ ＋ 添加密钥 ]
┌ ( ) ①  [别名: 主号]                          ┐
│        [🔑 密钥值 ................] [👁][📋][✔][🗑] │
│        [备注（可选）.............]              │
└──────────────────────────────────────────────┘
┌ (•) ②  [别名: 备用]                          ┐
│        [🔑 密钥值 ................] [👁][📋][✔][🗑] │
└──────────────────────────────────────────────┘
```
- 左侧单选点 = **当前密钥**（保存后即 `active`）；至少一把；最后一把的删除按钮禁用。
- 每行内：`别名` 输入（占位"如：主号 / 备用"）、密钥值输入（`obscureText` 逐行独立）、`备注`（可选，折叠或小字输入）。
- 每行的 `suffixIcon`：显示/隐藏、粘贴、**验证**（逐把）、删除——沿用现有按钮规格（`ValueKey('keyForm.toggleObscure')` / `paste` / `validate` 改为带 index：`keyForm.toggleObscure.1` 等）。
- **依赖改动的实现点**：`_keyValueController` → `List<_KeyEntryForm>`（每项含 3 个 controller + `viewIndex`）；`_handleValidate` → `_handleValidateEntry(i)`，`_validationState` → `Map<int, ValidationState>`；保存时不再有 6 处 `keyValue: _keyValueController.text`，统一构建 `keyEntries` 一次并传入所有构造点；`_obscureKeyValue` → 逐行 map。校验/余额/模型仍只对当前密钥取值。

### 6.4 工具页（Claude / Codex / Gemini / OpenClaw / 更多工具）

- 卡片（`KeyCard`，`cardMode: switchKey` + `lens`）新增可选参数：
  - `ValueChanged<int>? onSelectEntry`（选择子密钥，页面本地记住"该卡片选中项"，默认 = 卡片的当前密钥）；
  - `int? selectedEntryIndex` / 由 `currentKeyRefs` 得到的 `activeEntryIndex`。
- 头部第二行 `平台 · 掩码` 之后接 `KcKeyEntryPicker`（同 6.1 组件）：切换即改变该卡片在**本页**的选中项（不写配置）。
- 点卡片 → `switchXxxProvider(key.id!, entryIndex: 选中项)`；成功后该卡片 `● 生效中`，且 `onSwitchTool` 等既有交互不变。
- OpenClaw / 更多工具页同理：`applyKeyToTool(tool, keyId, entryIndex: 选中项)`。
- `_buildUnenabledSection`（未启用列表）保持点击即启用当前密钥的行为。

---

## 7. 边界与回归清单

| 场景 | 处理 |
| --- | --- |
| 老数据（无 `key_entries`） | `fromMap` 合成单把 → 卡片与今天完全一致，选择器不出现 |
| 主密码中途开启 | `reEncryptAllPlaintextKeys`（第 147 行）改为**逐把**判断"是否明文"并加密；`updateKey` 的"已密文则跳过"也逐把判断 |
| 导出 | `exportKeys` / `exportKeysPlain` 在每条卡片里加 `key_entries`（值同样解密/明文），并保留 `key_value`（= 当前密钥）以兼容旧版导入 |
| 导入 | 解析 `key_entries`；无该字段 → 按 `key_value` 单把构造；导入后按主密码状态**逐把重新加密** |
| 备份 / 云同步 | 若走同一份导出格式，天然覆盖；`backup` 目录无需改 |
| 排序 `reorderKeys` / 置顶 | 卡片 = 行，**不受影响** |
| 编辑模式多选 / 批量删除 | 卡片级，**不受影响** |
| 统计 `getStatistics` | 行级计数，**不受影响**（口径：卡片数） |
| 缓存：模型列表 / 余额 | 卡片级（同一供应商同地址，两把密钥看到同一份）→ 保持 `key_models_<id>` |
| 缓存：校验状态 | **改为按密钥项**：`key_validation_<id>#<idx>`；卡片徽章显示当前密钥的校验态 |
| `lastUsedAt`（卡片级排序用） | 镜像当前密钥；每把另有 `items[i].lastUsedAt` |
| 状态栏菜单 | 展示卡片当前密钥的掩码/别名；切换当前密钥后 `_notifyStatusBarMenuUpdate()` |
| 卡片"生效中"但配置被外部改过 | 沿用现有"总是重读配置文件匹配"策略；找不到匹配即视为官方态 |
| 两把子密钥值完全相同 | 值匹配会命中第一把；`currentKeyRefs` 记录命中的下标，不额外处理 |
| 别名重复 | 允许（别名仅展示用，不参与匹配） |

---

## 8. 实施步骤（建议顺序）

1. **数据层**：`schemaVersion 22→23` + `key_entries` 迁移；`KeyEntry` 模型与 `AIKey` 扩展（`keyEntries`/`activeKeyIndex`/`withKeyEntries`/`copyWith(activeKeyIndex)`/`toMap`/`fromMap`/`props`）；`parseKeyEntries`；迁移单测。
2. **加密与掩码**：逐把加密路径（`addKey`/`updateKey`/`reEncryptAllPlaintextKeys`）；`KeyMaskCache` 改 `id#index`；`maskKeyForKey`。
3. **ViewModel**：`setActiveKeyEntry` / `deleteKeyEntry` / `copyKeyToClipboard(entryIndex)` / `updateEntryLastUsed`；`currentKeyRefs` + 派生的 `currentKeyIds`；四个 `getCurrentXxxKey` 升级为逐把匹配（返回 `(card, entryIndex)`）。
4. **联动**：`_rewriteActiveTools`，并让 `_refreshActiveConfigIfNeeded` 复用它；`switchXxxProvider(..., entryIndex)`、`applyKeyToTool(..., entryIndex)` 加参。
5. **UI - 选择器组件**：新增 `KcKeyEntryPicker`（基于 `KcMenu`），单密钥时不渲染。
6. **UI - 主界面卡片**：v3 头部第二行接入选择器；工具行 chip 追加别名。
7. **UI - 详情抽屉**：`KcSegmented` 密钥选择器 + 字段绑定到选中项（局部 state，当前密钥加 `● 当前` 标记）。
8. **UI - 工具页**：`KeyCard` 增 `onSelectEntry`/选中态；四个配置页 + OpenClaw + 更多工具页接线。
9. **UI - 表单**：密钥项列表编辑（含别名/备注/逐把校验/当前单选/删除）。
10. **边界**：导出/导入、统计口径、缓存键、状态栏；跑既有单测 + 新增多密钥用例。

---

## 9. 未决议题（实施前可再确认）

1. `key_entries` 采用**单列 JSON（含 `active`）**；若偏好拆成 `key_entries` + `key_active_index` 两列，仅迁移与解析处改动，其余设计不变。
2. 卡片选择器在**钥匙包主界面**是否也显示「掩码」——本设计为保持 v3"头部不显示密钥"的克制风格，只显示别名；工具页因原本就显示掩码，故显示「别名 + 掩码」。
3. 子密钥是否设数量上限（建议不设硬上限，列表内滚动即可）。
</content>
