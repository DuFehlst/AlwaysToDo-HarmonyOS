import { formBindingData, formProvider } from '@kit.FormKit';
import { Task, isAITask } from './Models';
import { Store } from './Storage';
import { SyncEngine } from './SyncEngine';

/**
 * 服务卡片数据层（v2.1 · 真机实测后修正）：
 * 按卡片**实际高度**给行数，不再写死 4 条 —— 1x2→0 / 2x2→1 / 2x4→3 / 4x4→6。
 * 尺寸标签来自 ohos.extra.param.key.form_dimension（1=1×2 / 2=2×2 / 3=2×4 / 4=4×4）。
 * 另含 formId 注册表（Preferences）与 refreshAll()（App 侧主动刷新卡片）。
 */
export class WidgetData {
  static readonly MAX_ROWS: number = 8;

  /** 卡片尺寸标签（onAddForm 的 want.parameters 取值 → 布局用） */
  static dimLabel(dimension: number): string {
    if (dimension === 1) { return '1x2'; }
    if (dimension === 3) { return '2x4'; }
    if (dimension === 4) { return '4x4'; }
    return '2x2';
  }

  /**
   * 每个尺寸能放几条 —— 按真机实测的卡片高度（vp）配比：
   * 2×2 ≈ 161vp（1 条）／2×4 ≈ 161vp（右侧 3 条）／4×4 ≈ 369vp（右侧 8 条，行高 36）
   */
  static maxRows(dim: string): number {
    if (dim === '1x2') { return 0; }
    if (dim === '2x2') { return 1; }
    if (dim === '2x4') { return 3; }
    return WidgetData.MAX_ROWS;
  }

  private static todayStr(): string {
    const d = new Date();
    const m = ('0' + (d.getMonth() + 1)).slice(-2);
    const day = ('0' + d.getDate()).slice(-2);
    return d.getFullYear() + '-' + m + '-' + day;
  }

  private static priRank(p: string): number {
    if (p === 'high') { return 0; }
    if (p === 'medium') { return 1; }
    if (p === 'low') { return 2; }
    return 3;
  }

  /** 今日待办（未完成 + 截止=今天），排序：优先级 → 标题 */
  private static todayOpen(list: Task[], today: string): Task[] {
    const out: Task[] = [];
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      if (t.isDeleted || t.status === 'completed') { continue; }
      if (t.dueDate !== today) { continue; }
      out.push(t);
    }
    out.sort((a: Task, b: Task) => {
      const d = WidgetData.priRank(a.priority) - WidgetData.priRank(b.priority);
      if (d !== 0) { return d; }
      return a.title.localeCompare(b.title);
    });
    return out;
  }

  private static overdueCount(list: Task[], today: string): number {
    let n = 0;
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      if (t.isDeleted || t.status === 'completed') { continue; }
      if (t.dueDate !== '' && t.dueDate < today) { n++; }
    }
    return n;
  }

  /**
   * 卡片绑定数据：
   * dim / empty / todayCount / pendingCount / overdueCount
   * t1..t8 标题、id1..id8 任务 id（深链 + 勾选）、f1..f8 标记（high / due / ai）
   */
  static build(dim: string, list: Task[]): Record<string, string> {
    const today = WidgetData.todayStr();
    let pending = 0;
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      if (!t.isDeleted && t.status === 'pending') { pending++; }
    }
    const todays = WidgetData.todayOpen(list, today);
    const maxRows = WidgetData.maxRows(dim);
    const data: Record<string, string> = {
      'dim': dim,
      'empty': todays.length === 0 ? '1' : '0',
      'todayCount': '' + todays.length,
      'pendingCount': '' + pending,
      'overdueCount': '' + WidgetData.overdueCount(list, today),
      'budget': '' + maxRows,
      // 右下清单还有空位时才显示「+ 添加任务」入口
      'showAdd': todays.length < maxRows ? '1' : '0'
    };
    for (let i = 0; i < WidgetData.MAX_ROWS; i++) {
      const k = i + 1;
      const t = i < maxRows && i < todays.length ? todays[i] : null;
      data['t' + k] = t === null ? '' : t.title;
      data['id' + k] = t === null ? '' : t.id;
      let flag = '';
      if (t !== null) {
        if (t.dueDate !== '' && t.dueDate < today) { flag = 'due'; }
        else if (t.priority === 'high') { flag = 'high'; }
        else if (isAITask(t)) { flag = 'ai'; }
      }
      data['f' + k] = flag;
    }
    return data;
  }

  /** App 侧：把最新数据推给所有已注册卡片（完成/新增/打开 App 时调用） */
  static async refreshAll(): Promise<void> {
    try {
      const ids = await Store.getFormIds();
      if (ids.length === 0) { return; }
      // 内存为空时先拉一次，避免把卡片刷成 0
      if (SyncEngine.tasks.length === 0) {
        try {
          await SyncEngine.fullPull();
        } catch (e) {
          return;
        }
      }
      const list = SyncEngine.tasks;
      for (let i = 0; i < ids.length; i++) {
        const dim = await Store.getFormDim(ids[i]);
        const data = WidgetData.build(dim, list);
        await formProvider.updateForm(ids[i], formBindingData.createFormBindingData(data));
      }
    } catch (e) {
      // 卡片刷新失败不影响主流程
    }
  }
}
