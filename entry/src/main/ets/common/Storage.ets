import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 本地存储（P1·3 + P1·4）——Preferences 存 deviceId / 主题 / 排序 / outbox。
 * 服务端唯一真源，本地只是镜像（SOP §8.2 教训）。init 时传入 ApplicationContext。
 * outbox 用逗号分隔串存储，避免 ArkTS 的 JSON.parse any 限制。
 */
export class Store {
  private static prefs: preferences.Preferences | null = null;

  static async init(ctx: common.Context): Promise<void> {
    if (Store.prefs === null) {
      Store.prefs = await preferences.getPreferences(ctx, 'todo_prefs');
    }
  }

  private static async get(key: string, def: string): Promise<string> {
    if (Store.prefs === null) { return def; }
    const v = await Store.prefs.get(key, def);
    return v as string;
  }

  private static async put(key: string, value: string): Promise<void> {
    if (Store.prefs === null) { return; }
    await Store.prefs.put(key, value);
    await Store.prefs.flush();
  }

  static async getDeviceId(): Promise<string> {
    let id = await Store.get('device_id', '');
    if (id === '') {
      id = 'dev_' + Date.now().toString(36) + '_' + Math.floor(Math.random() * 0xffff).toString(36);
      await Store.put('device_id', id);
    }
    return id;
  }

  // outbox：离线待推送的任务 id 队列
  static async getOutboxIds(): Promise<string[]> {
    const raw = await Store.get('outbox', '');
    return raw === '' ? [] : raw.split(',');
  }

  static async pushOutbox(id: string): Promise<void> {
    const ids = await Store.getOutboxIds();
    if (ids.indexOf(id) < 0) {
      ids.push(id);
      await Store.put('outbox', ids.join(','));
    }
  }

  static async removeOutbox(id: string): Promise<void> {
    const ids = await Store.getOutboxIds();
    await Store.put('outbox', ids.filter((x: string) => x !== id).join(','));
  }

  static async setTheme(v: string): Promise<void> { await Store.put('theme', v); }
  static async getTheme(): Promise<string> { return Store.get('theme', 'light'); }
  static async setSort(v: string): Promise<void> { await Store.put('wl_sort', v); }
  static async getSort(): Promise<string> { return Store.get('wl_sort', 'added'); }
}
