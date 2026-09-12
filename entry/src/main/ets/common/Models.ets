/**
 * 数据模型（P1·3）——字段对齐 web 端同步契约 + TodoSync SOP §2。
 * 序列化走 class 实例（JSON.stringify 可序列化自有属性）；解析用 ESObject（ArkTS 动态 JSON 逃生口）。
 */

export class Subtask {
  id: string = '';
  title: string = '';
  completed: boolean = false;
  order: number = 0;
}

export class Recurrence {
  type: string = '';      // daily / weekly / monthly
  interval: number = 1;
  endDate: string = '';
}

export class Task {
  id: string = '';
  title: string = '';
  description: string = '';
  priority: string = '';
  status: string = 'pending';
  dueDate: string = '';         // YYYY-MM-DD
  dueTime: string = '';         // HH:MM
  category: string = '';
  track: string = '';
  tags: string[] = [];
  subtasks: Subtask[] = [];
  attachments: string[] = [];
  recurrence: Recurrence | null = null;
  reminderBefore: number = 0;   // 提前 N 分钟（0 = 无提醒）
  createdAt: string = '';
  updatedAt: string = '';
  completedAt: string = '';
  deviceId: string = '';
  version: number = 1;
  isDeleted: boolean = false;
  // AI 协作字段（对齐 web：taskKind/agentOwners/agentStatus/agentResult）
  taskKind: string = 'human';   // human / ai_auto(AI全自动) / ai_check(AI+我确认)
  agentOwners: string[] = [];
  agentStatus: string = '';     // queued排队中/running执行中/done已完成/failed失败/blocked待确认
  agentResult: string = '';
}

export class WatchlistItem {
  id: string = '';
  fingerprint: string = '';
  title: string = '';
  url: string = '';
  source: string = 'web';       // bilibili / douyin / web
  category: string = '';
  summary: string = '';
  overview: string = '';
  importance: string = 'B';     // S/A/B/C
  sourceDate: string = '';
  addedAt: string = '';
  dueDate: string = '';          // 计划看完（web watchDueDate）
  status: string = 'unwatched'; // unwatched / watched
  author: string = '';
  duration: string = '';
  notes: string = '';
  brain_id: string = '';        // 已归档的 brain 主题 id（避免重复弹建议）
  skip_brain: boolean = false;  // 用户已跳过归档
}

export class CatNode {
  name: string = '';     // 本层名（如「子类」）
  full: string = '';     // 全路径（如「大类/子类」，过滤用）
  depth: number = 0;     // 缩进层级
  count: number = 0;     // 计数（父级累计子级）
  hasKids: boolean = false;
}

// ════ AI 协作（对齐 web todo.js AGENT_STATUS_META）════

export function isAITask(t: Task): boolean {
  return t.taskKind !== 'human' && t.agentOwners.length > 0;
}

export function isToConfirm(t: Task): boolean {
  return t.status !== 'completed' && (t.taskKind === 'ai_check' || t.taskKind === 'ai_auto')
    && (t.agentStatus === 'blocked' || t.agentStatus === 'done');
}

export function agentStatusLabel(s: string): string {
  if (s === 'running') { return '执行中'; }
  if (s === 'done') { return '已完成'; }
  if (s === 'failed') { return '失败'; }
  if (s === 'blocked') { return '待确认'; }
  return '排队中';
}

export function kindLabel(k: string): string {
  if (k === 'ai_auto') { return 'AI全自动'; }
  if (k === 'ai_check') { return 'AI+我确认'; }
  return '';
}

export class AgentUpdateBody {
  task_id: string = '';
  agent_status: string = '';
  agent_result: string = '';
  device_id: string = '';
}

export class StatusInfo {  status: string = '';
  serverTime: string = '';
  taskCount: number = 0;
  pendingCount: number = 0;
  completedCount: number = 0;
  deviceCount: number = 0;
  lastSyncAt: string = '';
}

export class SyncRequest {
  deviceId: string = '';
  lastSyncAt: string = '';
  changes: Task[] = [];
}

export class SyncResponse {
  syncAt: string = '';
  pushedCount: number = 0;
  serverChanges: Task[] = [];
  conflicts: Object[] = [];
}

// 稍后再看：POST /api/watchlist 合并更新的请求体（{items:[...]}）
export class WatchlistPatchItem {
  id: string = '';
  status: string = '';
  _delete: boolean = false;
}

export class WatchlistPatch {
  items: WatchlistPatchItem[] = [];
}

// 稍后再看：整条目保存请求体（{items:[完整条目]}，服务器按 id 合并）
export class WatchlistSaveBody {
  items: WatchlistItem[] = [];
}

// 稍后再看共享缓存：WatchlistPage 拉取后写入，侧栏/顶栏徽标计数读它
export class WatchlistStore {
  static items: WatchlistItem[] = [];
}

// POST /api/watchlist/collect 请求体（{url:...}）
export class CollectBody {
  url: string = '';
}

// 归档建议（brain）相关模型
export class BrainCandidate {
  id: string = '';
  title: string = '';
  reason: string = '';
}

export class BrainSuggest {
  candidates: BrainCandidate[] = [];
  recommended: string = '';
  suggestedImportance: string = '';
  suggestedTopic: string = '';
}

export class BrainSuggestBody {
  url: string = '';
  title: string = '';
  summary: string = '';
  source: string = '';
}

export class BrainMountBody {
  url: string = '';
  title: string = '';
  summary: string = '';
  source: string = '';
  idea_id: string = '';
  importance: string = '';
  suggested_importance: string = '';
  suggested_topic: string = '';
}

export class IdeaCreateBody {
  type: string = 'idea';
  title: string = '';
  raw: string = '';
  source: string = 'watchlist';
}
