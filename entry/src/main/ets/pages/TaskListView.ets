import { common } from '@kit.AbilityKit';
import { FontSize, Palette, Radius, Space, Weight, palette } from '../common/Theme';
import { SyncEngine } from '../common/SyncEngine';
import { Store } from '../common/Storage';
import { ApiClient } from '../common/ApiClient';
import { Task, isAITask, isToConfirm, agentStatusLabel } from '../common/Models';

/**
 * 列表视图（对齐 web viewList）：排序（截止/创建/重要性）+ 完成圈 + 标题 + meta chips（截止/分类/标签）。
 * 数据复用 SyncEngine.tasks；完成圈点按 = 标记完成并推送（乐观更新）。
 */
@Component
export struct TaskListView {
  @StorageProp('darkMode') isDark: boolean = false;
  @Prop query: string = '';
  @Prop category: string = '';
  @Prop smart: string = 'all';
  @Prop refreshKey: number = 0;   // Index 在保存任务后 bump，触发本页刷新
  @State tick: number = 0;   // 本地变更后 bump 触发重渲染
  @State errText: string = '';   // 同步失败原因（诊断可见）
  @State sortMode: string = 'due';   // due / created / importance
  @State sortOpen: boolean = false;  // 排序下拉（页头右侧叠放）
  // 空态「+ 新建任务」回调：由 Index 注入（跳时间线视图拉起新建弹层）
  goNew: () => void = () => { };
  // 行内编辑回调：由 Index 注入（打开共享编辑弹层）
  goEdit: (id: string) => void = () => { };

  private pal(): Palette {
    return palette(this.isDark);
  }

  aboutToAppear(): void {
    this.load();
  }

  
  async load(): Promise<void> {
    try {
      await Store.init(getContext(this) as common.Context);
      await SyncEngine.fullPull();
      this.errText = '';
      this.tick = this.tick + 1;   // 拉取完成后触发重渲染（依赖注册模式必须自 bump）
    } catch (e) {
      this.errText = '同步失败：' + e;
    }
  }

  private todayStr(): string {
    const d = new Date();
    const m = ('0' + (d.getMonth() + 1)).slice(-2);
    const day = ('0' + d.getDate()).slice(-2);
    return d.getFullYear() + '-' + m + '-' + day;
  }

  private priRank(p: string): number {
    if (p === 'high') { return 0; }
    if (p === 'medium') { return 1; }
    if (p === 'low') { return 2; }
    return 3;
  }

  /** 分类匹配：精确匹配，父分类不含子分类（用户 2026-09-12 拍板） */
  private catMatch(cat: string, sel: string): boolean {
    const c = cat === '' ? '未分类' : cat;
    return c === sel;
  }
  private visible(): Task[] {
    const today = this.todayStr();
    const key = this.refreshKey;   // 依赖注册：父级保存后 bump → 重建
    const tick = this.tick;
    const list = SyncEngine.tasks;
    const out: Task[] = [];
    const searching = this.query !== '';   // 搜索是全局的：不受智能列表/分类/完成状态限制
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      if (searching) {
        if (t.title.indexOf(this.query) < 0 && t.description.indexOf(this.query) < 0) { continue; }
        out.push(t);
        continue;
      }
      // 对齐 web filterTasks：除「已完成」外所有过滤只显示未完成（已完成不再混进列表）
      if (this.smart === 'done') {
        if (t.status !== 'completed') { continue; }
      } else if (t.status === 'completed') { continue; }
      if (this.smart === 'today' && t.dueDate !== today) { continue; }
      if (this.smart === 'high' && t.priority !== 'high') { continue; }
      if (this.smart === 'overdue' && (t.dueDate === '' || t.dueDate >= today)) { continue; }
      if (this.smart === 'recur-daily' && (t.recurrence === null || t.recurrence.type !== 'daily')) { continue; }
      if (this.smart === 'recur-weekly' && (t.recurrence === null || t.recurrence.type !== 'weekly')) { continue; }
      if (this.smart === 'recur-monthly' && (t.recurrence === null || t.recurrence.type !== 'monthly')) { continue; }
      if (this.smart === 'ai' && !isAITask(t)) { continue; }
      if (this.smart === 'toconfirm' && !isToConfirm(t)) { continue; }
      if (this.category !== '' && !this.catMatch(t.category, this.category)) { continue; }
      if (this.query !== '' && t.title.indexOf(this.query) < 0 && t.description.indexOf(this.query) < 0) { continue; }
      out.push(t);
    }
    const mode = this.sortMode;
    out.sort((a: Task, b: Task) => {
      if (mode === 'created') {
        return (b.createdAt || '').localeCompare(a.createdAt || '');
      }
      if (mode === 'importance') {
        const d = this.priRank(a.priority) - this.priRank(b.priority);
        if (d !== 0) { return d; }
        return (a.dueDate || '9999').localeCompare(b.dueDate || '9999');
      }
      return (a.dueDate || '9999').localeCompare(b.dueDate || '9999');
    });
    return out;
  }

  private async toggleComplete(t: Task): Promise<void> {
    t.status = t.status === 'completed' ? 'pending' : 'completed';
    t.completedAt = t.status === 'completed' ? new Date().toISOString() : '';
    t.updatedAt = new Date().toISOString();
    t.version = t.version + 1;
    await SyncEngine.pushOne(t);
    this.tick = this.tick + 1;
  }

  // 页标题（对齐 web pageTitle/titleMap）
  private pageTitle(): string {
    if (this.category !== '') { return this.category; }
    if (this.smart === 'today') { return '今天'; }
    if (this.smart === 'high') { return '高优先级'; }
    if (this.smart === 'overdue') { return '已过期'; }
    if (this.smart === 'recur-daily') { return '日重复'; }
    if (this.smart === 'recur-weekly') { return '周重复'; }
    if (this.smart === 'recur-monthly') { return '月重复'; }
    if (this.smart === 'done') { return '已完成'; }
    if (this.smart === 'ai') { return 'AI 任务'; }
    if (this.smart === 'toconfirm') { return 'ToConfirm'; }
    return '全部任务';
  }

  // 对齐 web fmtDate：YYYY-MM-DD → M/D
  private fmtDate(d: string): string {
    if (d.length < 10) { return d; }
    const m = parseInt(d.substring(5, 7));
    const day = parseInt(d.substring(8, 10));
    return m + '/' + day;
  }

  // 对齐 web createWeekTemplate：空态一键建本周里程碑 3 条
  private async createWeekTemplate(): Promise<void> {
    try {
      await Store.init(getContext(this) as common.Context);
      const deviceId = await Store.getDeviceId();
      const tpl: string[][] = [
        ['Quant 主线：本周课程推进 2×2h', 'IBD-Quant', 'Quant', 'high'],
        ['Anki 卡片复习（IBD/Quant）', 'IBD-Quant', 'Quant', 'medium'],
        ['本周复盘与下周里程碑规划', '复盘', '', 'medium']
      ];
      for (let i = 0; i < tpl.length; i++) {
        const t = new Task();
        t.id = 'task_' + Date.now().toString(36) + '_' + Math.floor(Math.random() * 0xffff).toString(36) + i.toString(36);
        t.title = tpl[i][0];
        t.category = tpl[i][1];
        t.track = tpl[i][2];
        t.priority = tpl[i][3];
        t.status = 'pending';
        t.version = 1;
        t.deviceId = deviceId;
        t.createdAt = new Date().toISOString();
        t.updatedAt = t.createdAt;
        t.subtasks = [];
        t.tags = [];
        t.attachments = [];
        t.recurrence = null;
        SyncEngine.tasks.push(t);
        await SyncEngine.pushOne(t);
      }
      this.tick = this.tick + 1;
      this.getUIContext().getPromptAction().showToast({ message: '已创建 3 条本周里程碑' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '创建失败，请检查网络后重试' });
    }
  }

  @Builder
  sortOpt(mode: string, label: string) {
    Text(label)
      .fontSize(FontSize.secondary)
      .fontWeight(this.sortMode === mode ? Weight.semibold : Weight.regular)
      .fontColor(this.sortMode === mode ? this.pal().accent : this.pal().text2)
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor(this.sortMode === mode ? this.pal().chip : 'transparent')
      .borderRadius(Radius.control)
      .onClick(() => {
        this.sortMode = mode;
        this.sortOpen = false;
      })
  }

  private sortLabel(): string {
    if (this.sortMode === 'created') { return '创建时间'; }
    if (this.sortMode === 'importance') { return '重要性'; }
    return '截止时间';
  }

  @Builder
  priChip(p: string) {
    // 对齐 web .pri：高=深灰实心点；中=空心灰点；低=浅灰点（单色符号 §2.9）
    Row({ space: 4 }) {
      Circle({ width: 6, height: 6 })
        .fill(p === 'high' ? this.pal().text2 : p === 'medium' ? 'transparent' : this.pal().text3)
        .stroke(p === 'medium' ? this.pal().text3 : 'transparent')
        .strokeWidth(p === 'medium' ? 1.5 : 0)
      Text(p === 'high' ? '高' : p === 'medium' ? '中' : '低')
        .fontSize(FontSize.secondary)
        .fontWeight(p === 'high' ? Weight.semibold : Weight.regular)
        .fontColor(this.pal().text2)
    }
  }

  /** 左滑操作区：编辑 / 删除（删除二次确认，§2.13） */
  @Builder
  rowSwipe(t: Task) {
    Row() {
      Text('编辑')
        .fontSize(FontSize.secondary)
        .fontWeight(Weight.regular)
        .fontColor(this.pal().text2)
        .height('100%')
        .padding({ left: 18, right: 18 })
        .backgroundColor(this.pal().chip)
        .onClick(() => {
          this.goEdit(t.id);
        })
      Text('删除')
        .fontSize(FontSize.secondary)
        .fontWeight(Weight.regular)
        .fontColor(this.isDark ? '#ff6b5e' : '#c0392b')
        .height('100%')
        .padding({ left: 18, right: 18 })
        .backgroundColor(this.isDark ? 'rgba(255,107,94,0.14)' : 'rgba(192,57,43,0.10)')
        .onClick(() => {
          this.confirmDelete(t);
        })
    }
    .height('100%')
  }

  /** 删除确认 → 软删除并推送 */
  private confirmDelete(t: Task): void {
    this.getUIContext().showAlertDialog({
      title: '删除任务',
      message: t.title,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: this.isDark ? '#ff6b5e' : '#c0392b',
        action: () => {
          this.softDelete(t);
        }
      }
    });
  }

  private async softDelete(t: Task): Promise<void> {
    t.isDeleted = true;
    t.updatedAt = new Date().toISOString();
    t.version = t.version + 1;
    try {
      await SyncEngine.pushOne(t);
    } catch (e) {
    }
    this.tick = this.tick + 1;
    this.getUIContext().getPromptAction().showToast({ message: '已删除' });
  }

  @Builder
  taskRow(t: Task) {
    Row() {
      // 完成圈（对齐 web task-ck：20px 圆、1.5px 边、选中 accent 底白勾）
      Text(t.status === 'completed' ? '✓' : '')
        .width(20)
        .height(20)
        .fontSize(FontSize.helper)
        .fontWeight(Weight.semibold)
        .fontColor('#ffffff')
        .textAlign(TextAlign.Center)
        .borderRadius(Radius.pill)
        .border({ width: 1.5, color: t.status === 'completed' ? this.pal().accent : this.pal().text3 })
        .backgroundColor(t.status === 'completed' ? this.pal().accent : 'transparent')
        .margin({ top: 2 })
        .onClick(() => {
          this.toggleComplete(t);
        })

      Column({ space: 4 }) {
        Text(t.title)
          .fontSize(FontSize.body)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          if (t.priority !== '') {
            this.priChip(t.priority)
          }
          if (t.category !== '') {
            Text(t.category)
              .fontSize(FontSize.secondary)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text2)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .backgroundColor(this.pal().chip)
              .borderRadius(4)
          }
          if (t.dueDate !== '') {
            Text(this.fmtDate(t.dueDate))
              .fontSize(FontSize.secondary)
              .fontWeight(Weight.regular)
              .fontColor(t.dueDate < this.todayStr() ? this.pal().text : this.pal().text2)
          }
          if (isAITask(t)) {
            // 对齐 web ai-badge：AI任务 · owners · 状态
            Row({ space: 3 }) {
              Circle({ width: 5, height: 5 })
                .fill(t.agentStatus === 'blocked' ? this.pal().accent : this.pal().text3)
              Text('AI · ' + agentStatusLabel(t.agentStatus))
                .fontSize(FontSize.secondary)
                .fontWeight(t.agentStatus === 'blocked' ? Weight.semibold : Weight.regular)
                .fontColor(t.agentStatus === 'blocked' ? this.pal().accent : this.pal().text2)
            }
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .backgroundColor(this.isDark ? 'rgba(94,106,210,0.18)' : 'rgba(0,102,204,0.08)')
            .borderRadius(4)
          }
        }
        if (this.smart === 'toconfirm' && isToConfirm(t)) {
          // 对齐 web aiActionBar：确认完成 / 打回
          Row({ space: 8 }) {
            Button('确认完成')
              .height(28)
              .padding({ left: 10, right: 10 })
              .fontSize(FontSize.secondary)
              .fontWeight(Weight.regular)
              .fontColor('#ffffff')
              .backgroundColor(this.pal().accent)
              .borderRadius(Radius.control)
              .onClick(() => {
                this.quickAgentUpdate(t, 'done');
              })
            Button('打回')
              .height(28)
              .padding({ left: 10, right: 10 })
              .fontSize(FontSize.secondary)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text)
              .backgroundColor(this.pal().card2)
              .borderRadius(Radius.control)
              .onClick(() => {
                this.quickAgentUpdate(t, 'failed');
              })
          }
          .padding({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ left: 12 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: Space.s2, right: Space.s2, top: 14, bottom: 14 })
    .backgroundColor(this.pal().bg)   // ArkUI ListItem 默认白底，显式盖回页面底色（否则玻璃 dock 下显白块）
    .opacity(t.status === 'completed' ? 0.5 : 1)
  }

  // 对齐 web agentQuickUpdate：确认完成/打回 → 回写云端 + 本地刷新
  private async quickAgentUpdate(t: Task, status: string): Promise<void> {
    try {
      await ApiClient.agentUpdate(t.id, status, '');
      t.agentStatus = status;
      t.updatedAt = new Date().toISOString();
      t.version = t.version + 1;
      this.tick = this.tick + 1;
      this.getUIContext().getPromptAction().showToast({ message: status === 'done' ? '已确认完成' : '已打回' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '回写失败，云端不可达' });
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
      // 页头（pageTitle + N 项；排序叠起放右侧下拉）
      Row({ space: 6 }) {

        Text('' + this.visible().length + ' 项')
          .fontSize(FontSize.secondary)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text3)
          .padding({ top: 4 })
        Blank()
        Row({ space: 4 }) {
          Text(this.sortLabel())
            .fontSize(FontSize.secondary)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text3)
          Image($r('app.media.chevron_down'))
            .width(12)
            .height(12)
            .fillColor(this.pal().text3)
            .rotate({ angle: this.sortOpen ? 180 : 0 })
        }
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .onClick(() => {
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
            this.sortOpen = !this.sortOpen;
          })
        })
      }
      .width('100%')
      .padding({ left: Space.s2, right: Space.s2, top: Space.s1 })

      if (this.visible().length === 0) {
        if (this.query !== '') {
          // B3 无结果视图（Apple 搜索规范：显示当前搜索词，帮助发现错别字）
          Column({ space: Space.s1 }) {
            Image($r('app.media.search'))
              .width(28)
              .height(28)
              .fillColor(this.pal().text3)
            Text('没有找到与「' + this.query + '」相关的任务')
              .fontSize(FontSize.listTitle)
              .fontWeight(Weight.semibold)
              .fontColor(this.pal().text)
            Text('检查拼写，或换个关键词试试')
              .fontSize(FontSize.secondary)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text3)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else {
          // 空态（对齐 web empty-state：插画 + 标题 + 提示 + CTA）
          Column({ space: Space.s1 }) {
            Image($r('app.media.plus'))
              .width(28)
              .height(28)
              .fillColor(this.pal().text3)
            Text(this.errText !== '' ? this.errText : (this.smart === 'today' ? '今天还没有任务' : '暂无任务'))
              .fontSize(FontSize.listTitle)
              .fontWeight(Weight.semibold)
              .fontColor(this.pal().text)
            Text('把想做的事写进来，专注完成它。')
              .fontSize(FontSize.secondary)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text3)
            Row({ space: 8 }) {
              Button('+ 新建任务')
                .height(36)
                .padding({ left: 16, right: 16 })
                .fontSize(FontSize.secondary)
                .fontWeight(Weight.semibold)
                .fontColor(this.pal().accent)
                .backgroundColor(this.isDark ? 'rgba(94,106,210,0.24)' : 'rgba(0,102,204,0.14)')
                .backdropBlur(12)
                .saturate(1.4)
                .borderRadius(Radius.pill)
                .border({ width: 0.5, color: this.isDark ? 'rgba(130,143,255,0.38)' : 'rgba(0,102,204,0.30)' })
                .shadow({ radius: 8, color: 'rgba(0,0,0,0.04)', offsetY: 2 })
                .onClick(() => {
                  this.goNew();
                })
              Button('从模板创建本周里程碑')
                .height(36)
                .padding({ left: 14, right: 14 })
                .fontSize(FontSize.secondary)
                .fontWeight(Weight.regular)
                .fontColor(this.pal().text)
                .backgroundColor(this.isDark ? 'rgba(20,21,23,0.34)' : 'rgba(240,240,243,0.28)')
                .backdropBlur(12)
                .saturate(1.4)
                .borderRadius(Radius.pill)
                .border({ width: 0.5, color: this.isDark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)' })
                .onClick(() => {
                  this.createWeekTemplate();
                })
            }
            .padding({ top: 4 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }
      } else {
        List() {
          ForEach(this.visible(), (t: Task) => {
            ListItem() {
              this.taskRow(t)
            }
            .swipeAction({ end: this.rowSwipe(t) })
          }, (t: Task) => t.id)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: this.pal().border })
        .padding({ bottom: 8 })   // 只留极小呼吸位：任务行直接滚到玻璃 dock 下面（透明可见）
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().bg)

      if (this.sortOpen) {
        // 透明遮罩（点任意处收起）
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.sortOpen = false;
            })
        }
        .width('100%')
        .height('100%')

        // 排序浮层（右侧叠放，液态玻璃）
        Column({ space: 2 }) {
          this.sortOpt('due', '截止时间')
          this.sortOpt('created', '创建时间')
          this.sortOpt('importance', '重要性')
        }
        .width(112)
        .padding(4)
        .backgroundColor(this.isDark ? 'rgba(20,21,23,0.60)' : 'rgba(250,250,252,0.60)')
        .backdropBlur(28)
        .saturate(1.8)
        .borderRadius(Radius.secondary)
        .border({ width: 0.5, color: this.isDark ? 'rgba(255,255,255,0.10)' : 'rgba(255,255,255,0.65)' })
        .shadow({ radius: 30, color: 'rgba(0,0,0,0.14)', offsetY: 10 })
        .margin({ top: 46, right: Space.s2 })
        .transition(TransitionEffect.OPACITY)
      }
    }
    .width('100%')
    .height('100%')
  }
}
