import { ApiClient } from './ApiClient';
import { Store } from './Storage';
import { SyncRequest, Task, Recurrence } from './Models';

/**
 * 同步引擎（P1·4）——复刻 web 端 todo.js:61-97 合并规则：
 *  - v4 恒全量拉取（last_sync_at=null, changes=[]），避免增量丢墓碑致幽灵复活；
 *  - 服务端唯一真源：服务器墓碑优先、非删除按 version/updatedAt 谁新谁赢（server_wins）；
 *  - 本地下墓碑（未推送删除）不被服务端旧数据复活（除非其出 outbox）；
 *  - 离线 outbox：推送失败入队，恢复自动补传。
 */

// /api/sync 响应原始结构 + 服务端任务 node 原始结构（snake_case 无关，节点用 camelCase）
interface RecurrenceRaw {
  type: string;
  interval: number;
  endDate: string | null;
}
interface TaskRaw {
  id: string;
  title: string;
  status: string;
  isDeleted: boolean;
  version: number;
  updatedAt: string;
  createdAt: string;
  completedAt: string | null;
  description: string;
  priority: string;
  dueDate: string | null;
  dueTime: string | null;
  category: string;
  track: string;
  deviceId: string;
  reminderBefore: number | null;
  tags: string[];
  subtasks: SubtaskRaw[];
  attachments: string[];
  recurrence: RecurrenceRaw | null;
  taskKind: string;
  agentOwners: string[];
  agentStatus: string;
  agentResult: string;
}
interface SubtaskRaw {
  id: string;
  title: string;
  completed: boolean;
  order: number;
}
interface SyncRaw {
  sync_at: string;
  pushed_count: number;
  server_changes: TaskRaw[];
  conflicts: Object[];
}

export class SyncEngine {
  static tasks: Task[] = [];

  private static toTask(r: TaskRaw): Task {
    const t = new Task();
    t.id = r.id;
    t.title = r.title;
    t.status = r.status;
    t.version = r.version;
    t.updatedAt = r.updatedAt;
    t.isDeleted = r.isDeleted;
    t.createdAt = r.createdAt || '';
    t.completedAt = r.completedAt ? r.completedAt : '';
    t.description = r.description || '';
    t.priority = r.priority || '';
    t.dueDate = r.dueDate ? r.dueDate : '';
    t.dueTime = r.dueTime ? r.dueTime : '';
    t.category = r.category || '';
    t.track = r.track || '';
    t.deviceId = r.deviceId || '';
    t.reminderBefore = r.reminderBefore === null ? 0 : r.reminderBefore;
    t.taskKind = r.taskKind || 'human';
    t.agentOwners = r.agentOwners || [];
    t.agentStatus = r.agentStatus || '';
    t.agentResult = r.agentResult || '';
    t.tags = r.tags ? r.tags : [];
    t.attachments = r.attachments ? r.attachments : [];
    t.subtasks = r.subtasks ? r.subtasks : [];
    if (r.recurrence !== null) {
      const rec = new Recurrence();
      rec.type = r.recurrence.type;
      rec.interval = r.recurrence.interval;
      rec.endDate = r.recurrence.endDate === null ? '' : r.recurrence.endDate;
      t.recurrence = rec;
    }
    return t;
  }

  /** 恒全量拉取 + 合并 → 内存任务列表 */
  static async fullPull(): Promise<Task[]> {
    const deviceId = await Store.getDeviceId();
    const body = new SyncRequest();
    body.deviceId = deviceId;
    body.lastSyncAt = '';
    body.changes = [];
    const raw = await ApiClient.postJson('/api/sync', body);
    const d = JSON.parse(raw) as SyncRaw;

    const map = new Map<string, Task>();
    // 1) 本地缓存镜像入图（v1 用内存，断网回退用）
    for (let i = 0; i < SyncEngine.tasks.length; i++) {
      const lt = SyncEngine.tasks[i];
      map.set(lt.id, lt);
    }
    const outboxIds = await Store.getOutboxIds();
    const sc = d.server_changes;
    for (let j = 0; j < sc.length; j++) {
      const r = sc[j];
      if (!r.id) { continue; }
      const t = SyncEngine.toTask(r);
      if (t.isDeleted) { map.set(t.id, t); continue; }
      const ex = map.get(t.id);
      if (!ex) { map.set(t.id, t); }
      else if (ex.isDeleted) { if (outboxIds.indexOf(t.id) < 0) { map.set(t.id, t); } }
      else if ((t.version || 0) > (ex.version || 0) || (t.updatedAt || '') > (ex.updatedAt || '')) {
        if ((!t.attachments || !t.attachments.length) && ex.attachments && ex.attachments.length) {
          t.attachments = ex.attachments;
        }
        map.set(t.id, t);
      }
    }

    const list: Task[] = [];
    map.forEach((v: Task) => { if (!v.isDeleted) { list.push(v); } });
    SyncEngine.tasks = list;
    return list;
  }

  /** 推送单个任务；失败入 outbox */
  /** 数据变更回调（EntryAbility 注入 → 刷新桌面卡片）；用回调而非直接 import，避免模块循环依赖 */
  static onChanged: () => void = () => { };

  static async pushOne(task: Task): Promise<boolean> {
    const deviceId = await Store.getDeviceId();
    const body = new SyncRequest();
    body.deviceId = deviceId;
    body.lastSyncAt = '';
    body.changes = [task];
    try {
      await ApiClient.postJson('/api/sync', body);
      SyncEngine.onChanged();
      return true;
    } catch (e) {
      await Store.pushOutbox(task.id);
      return false;
    }
  }

  /** 补传 outbox 队列（按内存/最近一次拉取找任务对象） */
  static async flushOutbox(): Promise<void> {
    const ids = await Store.getOutboxIds();
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i];
      const found = SyncEngine.tasks.find((t: Task) => t.id === id);
      if (!found) { await Store.removeOutbox(id); continue; }
      const ok = await SyncEngine.pushOne(found);
      if (ok) { await Store.removeOutbox(id); }
      else { break; }  // 网络仍不可达，保持队列
    }
  }
}
