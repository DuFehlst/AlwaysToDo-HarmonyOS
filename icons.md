# alwaystodo 图标白名单（Reicon Outline · 2026-09-11）

> 图标集：Reicon（MIT，24 网格，currentColor）。所有图标取自 `reicon-mcp` 的真实导出名（Outline weight），
> 禁止凭记忆编造图标名。资源文件即导出名去 `ic_` 前缀，`$r('app.media.<name>')` 与文件名一致。
> **鸿蒙资源名铁律（2026-09-11 编译踩坑，Error 11211116）**：资源名只允许 `[a-zA-Z0-9_]`，
> 导出名含 `-` 的一律转下划线作资源名：`chevron-left→chevron_left`、`arrow-right→arrow_right`，`$r` 引用同步用下划线名。
> **fillColor 只染 fill 不染 stroke（2026-09-11 真机踩坑）**：`stroke="currentColor"` 的图标在真机上恒黑。
> 因此 5 个描边图标已换为填充版（同名资源、视觉等价）：`activity`（用 web 原版 ic-chart-line 填充路径）、
> `chevron_left/right/down`（按原 polyline 坐标手转 1.5px 填充多边形）、`edit`（Reicon Filled edit）。
> **后续新增图标只收 fill-based SVG**（path 带 `fill="currentColor"`），描边图标一律先转填充再入库。
> 染色方式：ArkUI `Image($r(...)).fillColor(选中态? accent : text2/text3)`，svg 内 `fill="currentColor"` 已保留。

| 语义 | 导出名 | 资源文件 | 使用位置 |
|---|---|---|---|
| 顶栏菜单（侧栏触发） | menu | entry/src/main/resources/base/media/menu.svg | Index.ets 顶栏 |
| 命令面板 | search | entry/src/main/resources/base/media/search.svg | Index.ets 顶栏 |
| 列表导航 | list | entry/src/main/resources/base/media/list.svg | Index.ets 底栏 + 侧栏「全部任务」 |
| 日历导航 | calendar | entry/src/main/resources/base/media/calendar.svg | Index.ets 底栏 |
| 时间线导航 | activity | entry/src/main/resources/base/media/activity.svg | Index.ets 底栏 |
| 稍后再看 / 已过期 / ToConfirm | clock | entry/src/main/resources/base/media/clock.svg | Index.ets 底栏 + 侧栏 |
| 关闭 | x | entry/src/main/resources/base/media/x.svg | Index.ets 侧栏 / TasksPage 子任务·附件 |
| 编辑 | edit | entry/src/main/resources/base/media/edit.svg | WatchlistPage 条目行 |
| 上月 | chevron-left | entry/src/main/resources/base/media/chevron_left.svg | CalendarView 月历头 |
| 下月 | chevron-right | entry/src/main/resources/base/media/chevron_right.svg | CalendarView 月历头 |
| 折叠/展开指示 | chevron-down | entry/src/main/resources/base/media/chevron_down.svg | Index.ets 侧栏「更多智能列表」+ 分类树（rotate 切换方向） |
| 今天 | sun | entry/src/main/resources/base/media/sun.svg | Index.ets 侧栏 |
| 高优先级 | star | entry/src/main/resources/base/media/star.svg | Index.ets 侧栏 |
| 重复（日/周/月） | repeat | entry/src/main/resources/base/media/repeat.svg | Index.ets 侧栏 |
| 已完成 | check | entry/src/main/resources/base/media/check.svg | Index.ets 侧栏 |
| AI 任务 | cpu | entry/src/main/resources/base/media/cpu.svg | Index.ets 侧栏 |
| 深色模式 | moon | entry/src/main/resources/base/media/moon.svg | Index.ets 侧栏主题切换 |
| 提交/发送（快速记录） | arrow-right | entry/src/main/resources/base/media/arrow_right.svg | Index.ets 侧栏 |
| 新增（空态） | plus | entry/src/main/resources/base/media/plus.svg | TaskListView 空态 |

## 查证备注（避免踩坑）

- `calendar-days`、`git-branch`、`pencil` 均为**假名**（`reicon-mcp search` 无此导出名）：
  - 日历 → `calendar`（search「calendar」top）
  - 时间线 → `activity`（search「activity」top；`git-branch` 不存在，备选 `branch-up`/`branch-down`/`history3`）
  - 编辑 → `edit`（search「edit」top；`pencil` 不存在，备选 `pen`）
- 已核实真实导出名：`menu` / `list` / `calendar` / `clock` / `x` / `edit` / `chevron-left` / `chevron-right` /
  `chevron-down` / `search` / `sun` / `star` / `repeat` / `check` / `cpu` / `moon` / `arrow-right` / `plus` / `activity`。
