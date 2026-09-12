import { http } from '@kit.NetworkKit';
import {
  StatusInfo, WatchlistItem, WatchlistPatch, WatchlistPatchItem, WatchlistSaveBody, CollectBody,
  BrainCandidate, BrainSuggest, BrainSuggestBody, BrainMountBody, IdeaCreateBody, AgentUpdateBody
} from './Models';
import { Store } from './Storage';

// /api/status 返回的 snake_case 原始结构，用于 JSON 解析显式定型（avoid any/unknown）
interface StatusRaw {
  status: string;
  server_time: string;
  task_count: number;
  pending_count: number;
  completed_count: number;
  device_count: number;
  last_sync_at: string;
}

// /api/watchlist GET 返回的原始结构（{count, items:[...]}）
interface WatchlistItemRaw {
  id: string;
  fingerprint: string;
  title: string;
  url: string;
  source: string;
  category: string;
  summary: string;
  overview: string;
  importance: string;
  sourceDate: string;
  addedAt: string;
  dueDate: string;
  status: string;
  author: string;
  duration: string;
  notes: string;
  brain_id: string;
  skip_brain: boolean;
}

interface WatchlistRaw {
  count: number;
  items: WatchlistItemRaw[];
}

// /api/watchlist/collect 响应（{ok, added, item}）
interface CollectRaw {
  ok: boolean;
  added: boolean;
  item: Object;
}

// brain 归档建议响应原始结构
interface BrainCandidateRaw {
  id: string;
  title: string;
  reason: string;
}
interface BrainSuggestRaw {
  candidates: BrainCandidateRaw[];
  recommended: string;
  suggested_importance: string;
  suggested_topic: string;
}
interface IdeaItemRaw {
  id: string;
  title: string;
}
interface IdeaListRaw {
  items: IdeaItemRaw[];
}
interface IdeaCreateRaw {
  id: string;
}
interface MountRaw {
  ok: boolean;
  id: string;
}

/**
 * API 客户端（P1·3）——统一走 HTTPS 域名。
 * base = https://your-server.example/todo 是 nginx 入口，/api/.. 是数据接口）
 */
export class ApiClient {
  static readonly BASE: string = 'https://your-server.example/todo';   // ← 改成你自己的服务地址
  // brain 网关（第二大脑归档建议走独立 /brain/api）
  static readonly BRAIN_BASE: string = 'https://your-server.example/brain/api';

  private static request(url: string, method: http.RequestMethod): Promise<string> {
    let req = http.createHttp();
    return new Promise<string>((resolve, reject) => {
      req.request(url, { method: method, connectTimeout: 10000, readTimeout: 15000 })
        .then((resp: http.HttpResponse) => {
          req.destroy();
          if (resp.responseCode === 200) {
            resolve(resp.result as string);
          } else {
            reject(new Error('HTTP ' + resp.responseCode));
          }
        })
        .catch((e: Error) => {
          req.destroy();
          reject(e);
        });
    });
  }

  static getJson(path: string): Promise<string> {
    return ApiClient.request(ApiClient.BASE + path, http.RequestMethod.GET);
  }

  static postJson(path: string, body: Object): Promise<string> {
    let req = http.createHttp();
    return new Promise<string>((resolve, reject) => {
      req.request(ApiClient.BASE + path, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify(body),
        connectTimeout: 10000,
        readTimeout: 15000
      })
        .then((resp: http.HttpResponse) => {
          req.destroy();
          if (resp.responseCode === 200) {
            resolve(resp.result as string);
          } else {
            reject(new Error('HTTP ' + resp.responseCode));
          }
        })
        .catch((e: Error) => {
          req.destroy();
          reject(e);
        });
    });
  }

  /** GET /api/status → StatusInfo（服务器返回 snake_case 键，逐字段映射） */
  static async status(): Promise<StatusInfo> {
    const raw = await ApiClient.getJson('/api/status');
    const d = JSON.parse(raw) as StatusRaw;
    const s = new StatusInfo();
    s.status = d.status;
    s.serverTime = d.server_time;
    s.taskCount = d.task_count;
    s.pendingCount = d.pending_count;
    s.completedCount = d.completed_count;
    s.deviceCount = d.device_count;
    s.lastSyncAt = d.last_sync_at;
    return s;
  }

  /** GET /api/watchlist → WatchlistItem[]（服务器固定返回 {count, items:[...]}） */
  static async watchlist(): Promise<WatchlistItem[]> {
    const raw = await ApiClient.getJson('/api/watchlist');
    const d = JSON.parse(raw) as WatchlistRaw;
    const out: WatchlistItem[] = [];
    for (let i = 0; i < d.items.length; i++) {
      out.push(ApiClient.toWatchlistItem(d.items[i]));
    }
    return out;
  }

  private static toWatchlistItem(r: WatchlistItemRaw): WatchlistItem {
    const w = new WatchlistItem();
    // 服务器可能省略字段（undefined）→ 一律真值兜底，避免 .length/substring 在视图层崩溃
    w.id = r.id;
    w.fingerprint = r.fingerprint ? r.fingerprint : '';
    w.title = r.title ? r.title : '';
    w.url = r.url ? r.url : '';
    w.source = r.source ? r.source : '';
    w.category = r.category ? r.category : '';
    w.summary = r.summary ? r.summary : '';
    w.overview = r.overview ? r.overview : '';
    w.importance = r.importance ? r.importance : '';
    w.sourceDate = r.sourceDate ? r.sourceDate : '';
    w.addedAt = r.addedAt ? r.addedAt : '';
    w.dueDate = r.dueDate ? r.dueDate : '';
    w.status = r.status ? r.status : '';
    w.author = r.author ? r.author : '';
    w.duration = r.duration ? r.duration : '';
    w.notes = r.notes ? r.notes : '';
    w.brain_id = r.brain_id ? r.brain_id : '';
    w.skip_brain = r.skip_brain;
    return w;
  }

  /** 标记看完/取消看完：POST /api/watchlist 合并更新 status */
  static async markWatched(id: string, watched: boolean): Promise<void> {
    const item = new WatchlistPatchItem();
    item.id = id;
    item.status = watched ? 'watched' : 'unwatched';
    const body = new WatchlistPatch();
    body.items = [item];
    await ApiClient.postJson('/api/watchlist', body);
  }

  /** 删除条目：POST /api/watchlist {items:[{id, _delete:true}]} */
  static async deleteWatchlistItem(id: string): Promise<void> {
    const item = new WatchlistPatchItem();
    item.id = id;
    item._delete = true;
    const body = new WatchlistPatch();
    body.items = [item];
    await ApiClient.postJson('/api/watchlist', body);
  }

  /** 整条目保存（编辑 category/summary/importance/status）：POST /api/watchlist 合并 */
  static async saveWatchlistItem(item: WatchlistItem): Promise<void> {
    const body = new WatchlistSaveBody();
    body.items = [item];
    await ApiClient.postJson('/api/watchlist', body);
  }

  /** 回写 agent 状态（对齐 web /api/agent/update：确认完成/打回） */
  static async agentUpdate(taskId: string, status: string, result: string): Promise<void> {
    const b = new AgentUpdateBody();
    b.task_id = taskId;
    b.agent_status = status;
    b.agent_result = result;
    b.device_id = await Store.getDeviceId();
    await ApiClient.postJson('/api/agent/update', b);
  }

  /** 丢网址收藏：POST /api/watchlist/collect {url} → 服务端抓取+LLM 分类+指纹查重，返回是否新加 */
  static async collect(url: string): Promise<boolean> {
    const b = new CollectBody();
    b.url = url;
    const raw = await ApiClient.postJson('/api/watchlist/collect', b);
    const d = JSON.parse(raw) as CollectRaw;
    return d.added;
  }

  // ════ brain 网关（归档建议流）════

  private static postBrain(path: string, body: Object): Promise<string> {
    let req = http.createHttp();
    return new Promise<string>((resolve, reject) => {
      req.request(ApiClient.BRAIN_BASE + path, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify(body),
        connectTimeout: 10000,
        readTimeout: 20000
      })
        .then((resp: http.HttpResponse) => {
          req.destroy();
          if (resp.responseCode === 200) { resolve(resp.result as string); }
          else { reject(new Error('HTTP ' + resp.responseCode)); }
        })
        .catch((e: Error) => {
          req.destroy();
          reject(e);
        });
    });
  }

  private static getBrain(path: string): Promise<string> {
    let req = http.createHttp();
    return new Promise<string>((resolve, reject) => {
      req.request(ApiClient.BRAIN_BASE + path, { method: http.RequestMethod.GET, connectTimeout: 10000, readTimeout: 15000 })
        .then((resp: http.HttpResponse) => {
          req.destroy();
          if (resp.responseCode === 200) { resolve(resp.result as string); }
          else { reject(new Error('HTTP ' + resp.responseCode)); }
        })
        .catch((e: Error) => {
          req.destroy();
          reject(e);
        });
    });
  }

  /** 取归档建议：POST /brain/api/entries/from-watchlist {url,title,summary,source} */
  static async brainSuggest(title: string, summary: string, url: string, source: string): Promise<BrainSuggest> {
    const body = new BrainSuggestBody();
    body.url = url;
    body.title = title;
    body.summary = summary;
    body.source = source;
    const raw = await ApiClient.postBrain('/entries/from-watchlist', body);
    const d = JSON.parse(raw) as BrainSuggestRaw;
    const s = new BrainSuggest();
    for (let i = 0; i < d.candidates.length; i++) {
      const c = new BrainCandidate();
      c.id = d.candidates[i].id;
      c.title = d.candidates[i].title;
      c.reason = d.candidates[i].reason;
      s.candidates.push(c);
    }
    s.recommended = d.recommended;
    s.suggestedImportance = d.suggested_importance;
    s.suggestedTopic = d.suggested_topic;
    return s;
  }

  /** 确认归档到主题：POST /brain/api/entries/from-watchlist（带 idea_id）→ 返回归档条目 id */
  static async brainMount(w: WatchlistItem, ideaId: string, importance: string, sugImp: string, sugTopic: string): Promise<string> {
    const body = new BrainMountBody();
    body.url = w.url;
    body.title = w.title;
    body.summary = w.summary;
    body.source = w.source;
    body.idea_id = ideaId;
    body.importance = importance;
    body.suggested_importance = sugImp;
    body.suggested_topic = sugTopic;
    const raw = await ApiClient.postBrain('/entries/from-watchlist', body);
    const d = JSON.parse(raw) as MountRaw;
    return d.id;
  }

  /** 主题名 → 主题 id：候选精确命中 → 全量 idea 精确匹配 → 不存在则创建（对齐 web resolveTopicIdByName） */
  static async brainResolveTopic(name: string, cands: BrainCandidate[]): Promise<string> {
    const norm = name.trim().toLowerCase();
    if (norm === '') { return ''; }
    for (let i = 0; i < cands.length; i++) {
      if (cands[i].title.trim().toLowerCase() === norm) { return cands[i].id; }
    }
    try {
      const raw = await ApiClient.getBrain('/entries?type=idea');
      const d = JSON.parse(raw) as IdeaListRaw;
      for (let j = 0; j < d.items.length; j++) {
        if (d.items[j].title.trim().toLowerCase() === norm) { return d.items[j].id; }
      }
    } catch (e) {
      // 忽略
    }
    const body = new IdeaCreateBody();
    body.title = name;
    body.raw = name;
    const raw2 = await ApiClient.postBrain('/entries', body);
    const d2 = JSON.parse(raw2) as IdeaCreateRaw;
    return d2.id;
  }
}
