import { common } from '@kit.AbilityKit';
import { FontSize, Palette, Radius, Space, TOUCH_TARGET, Weight, palette } from '../common/Theme';
import { SyncEngine } from '../common/SyncEngine';
import { Store } from '../common/Storage';
import { Task, isAITask, isToConfirm, agentStatusLabel } from '../common/Models';
import { Reminders } from '../common/Reminders';
import { TaskEditSheet } from './TaskEditSheet';

class DayGroup {
  date: string = '';
  tasks: Task[] = [];
}

class LaneModel {
  name: string = '';
  count: number = 0;
  days: DayGroup[] = [];
}

class OtherGroup {
  cat: string = '';
  tasks: Task[] = [];
}

/**
 * 任务 Tab（P2·5 完整：时间线泳道 + 详情/编辑弹层 + pushOne 双向）。
 * 布局：内容优先裸排（design.md §2.3）；单 accent（§1.4）；字重 300/400/600。
 * 编辑弹层：底部浮层（唯一例外阴影，design.md §1.4 浮层例外）。
 */
@Component
export struct TasksPage {
  @StorageProp('darkMode') isDark: boolean = false;
  @Prop query: string = '';
  @Prop category: string = '';
  @Prop smart: string = 'all';
  @State lanes: LaneModel[] = [];
  @State others: OtherGroup[] = [];
  @State otherOpen: boolean = false;
  @State laneSel: string = 'all';   // 轨道切换：all / 具体轨道名 / other
  @State trackBanner: string = '';
  @State syncText: string = '';
  // 共享任务编辑弹层（TaskEditSheet，表单已抽离）
  @State taskEditVisible: boolean = false;
  @State taskEditId: string = '';

  private pal(): Palette {
    return palette(this.isDark);
  }

  private buttonRadius(): number {
    return this.isDark ? Radius.control : Radius.pill;
  }

  aboutToAppear(): void {
    this.load();
  }

  private todayStr(): string {
    const d = new Date();
    const m = ('0' + (d.getMonth() + 1)).slice(-2);
    const day = ('0' + d.getDate()).slice(-2);
    return d.getFullYear() + '-' + m + '-' + day;
  }

  async load(): Promise<void> {
    try {
      await Store.init(getContext(this) as common.Context);
      const list = await SyncEngine.fullPull();
      this.buildTimeline(list);   // 对齐 web renderTimeline：全量任务，不受侧栏智能筛选/分类限制
      this.syncText = list.length ? '' : '还没有任务';
      Reminders.requestEnable();
      await Reminders.schedule(list);
    } catch (e) {
      this.syncText = '同步失败';
    }
  }

  private openTaskEdit(taskId: string): void {
    this.taskEditId = taskId;
    this.taskEditVisible = true;
  }

  /** 分类匹配：精确匹配，父分类不含子分类（用户 2026-09-12 拍板） */
  private catMatch(cat: string, sel: string): boolean {
    const c = cat === '' ? '未分类' : cat;
    return c === sel;
  }
  private applyFilters(list: Task[]): Task[] {
    const today = this.todayStr();
    const out: Task[] = [];
    const searching = this.query !== '';   // 搜索是全局的：不受智能列表/分类/完成状态限制
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      if (searching) {
        if (t.title.indexOf(this.query) < 0 && t.description.indexOf(this.query) < 0) { continue; }
        out.push(t);
        continue;
      }
      // 对齐 web：除「已完成」外所有过滤只显示未完成
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
    return out;
  }

  // 轨道推导（对齐 web deriveTrack）：先取 t.track，空则按分类/标签/标题关键词归 Agent/Quant
  private deriveTrack(t: Task): string {
    const tr = t.track.trim();
    if (tr !== '') { return tr; }
    const hay = (t.category + ' ' + t.tags.join(' ') + ' ' + t.title).toLowerCase();
    if (/agent|rag|llm|大模型|prompt|智能体|多模态|langchain|deepseek|agentic|\bai\b|ocr|asr/.test(hay)) { return 'Agent'; }
    if (/quant|量化|因子|回测|宽客|随机过程|black.?scholes|策略|对冲|机器学习|统计套利/.test(hay)) { return 'Quant'; }
    return '';
  }

  private groupDays(arr: Task[]): DayGroup[] {
    const sorted = arr.slice().sort((a: Task, b: Task) => a.dueDate.localeCompare(b.dueDate));
    const days: DayGroup[] = [];
    for (let i = 0; i < sorted.length; i++) {
      const t = sorted[i];
      if (days.length === 0 || days[days.length - 1].date !== t.dueDate) {
        const d = new DayGroup();
        d.date = t.dueDate;
        d.tasks = [];
        days.push(d);
      }
      days[days.length - 1].tasks.push(t);
    }
    return days;
  }

  // 时间线组装（对齐 web renderTimeline）：只收 pending 且有截止日期的任务
  /** 轨道切换 chip */
  @Builder
  laneChip(key: string, label: string) {
    Text(label)
      .fontSize(FontSize.secondary)
      .fontWeight(this.laneSel === key ? Weight.semibold : Weight.regular)
      .fontColor(this.laneSel === key ? this.pal().accent : this.pal().text2)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.pal().chip)
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.laneSel = key;
      })
  }

  /** 当前选择下要渲染的轨道（all=全部；other=只看其他任务；具体名=只看该轨道） */
  private visibleLanes(): LaneModel[] {
    if (this.laneSel === 'all') { return this.lanes; }
    if (this.laneSel === 'other') { return []; }
    const out: LaneModel[] = [];
    for (let i = 0; i < this.lanes.length; i++) {
      if (this.lanes[i].name === this.laneSel) { out.push(this.lanes[i]); }
    }
    return out;
  }

  private buildTimeline(list: Task[]): void {
    const items: Task[] = [];
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      // 对齐 web renderTimeline：未删除 + 未完成 + 有截止日期（调用方已改为传全量，不受智能筛选/分类限制）
      if (t.isDeleted) { continue; }
      if (t.status === 'completed') { continue; }
      if (t.dueDate && t.dueDate.length >= 10) { items.push(t); }
    }
    const laneMap = new Map<string, Task[]>();
    const otherTasks: Task[] = [];
    for (let i = 0; i < items.length; i++) {
      const t = items[i];
      const tr = this.deriveTrack(t);
      if (tr === '') { otherTasks.push(t); continue; }
      let arr = laneMap.get(tr);
      if (!arr) { arr = []; laneMap.set(tr, arr); }
      arr.push(t);
    }
    const names: string[] = [];
    laneMap.forEach((v: Task[], k: string) => { names.push(k); });
    names.sort((a: string, b: string) => a.localeCompare(b));
    this.trackBanner = names.length ? names.join(' · ') : '暂无';
    const lanes: LaneModel[] = [];
    for (let i = 0; i < names.length; i++) {
      const arr = laneMap.get(names[i]) || [];
      const l = new LaneModel();
      l.name = names[i];
      l.count = arr.length;
      l.days = this.groupDays(arr);
      lanes.push(l);
    }
    this.lanes = lanes;
    // 其他任务（未分配轨道）：按分类分组，组内按日期
    const ogMap = new Map<string, Task[]>();
    for (let i = 0; i < otherTasks.length; i++) {
      const t = otherTasks[i];
      const cy = t.category === '' ? '未分类' : t.category;
      let arr2 = ogMap.get(cy);
      if (!arr2) { arr2 = []; ogMap.set(cy, arr2); }
      arr2.push(t);
    }
    const ogs: OtherGroup[] = [];
    ogMap.forEach((arr: Task[], cat: string) => {
      arr.sort((a: Task, b: Task) => a.dueDate.localeCompare(b.dueDate));
      const g = new OtherGroup();
      g.cat = cat;
      g.tasks = arr;
      ogs.push(g);
    });
    ogs.sort((a: OtherGroup, b: OtherGroup) => a.cat.localeCompare(b.cat));
    this.others = ogs;
  }

  private otherCount(): number {
    let n = 0;
    for (let i = 0; i < this.others.length; i++) { n += this.others[i].tasks.length; }
    return n;
  }

  // 对齐 web tlLabel：YYYY-MM-DD → M月D日
  private tlLabel(d: string): string {
    if (d.length < 10) { return d; }
    return parseInt(d.substring(5, 7)) + '月' + parseInt(d.substring(8, 10)) + '日';
  }

  private openNew(): void {
    this.openTaskEdit('');
  }

  private openEdit(t: Task): void {
    this.openTaskEdit(t.id);
  }

  /** 时间线条目（对齐 web tl-item：优先级点+字 / 标题 / 分类 tag / dueTime 右置） */
  @Builder
  tlItem(t: Task) {
    Row({ space: 8 }) {
      if (t.priority !== '') {
        Row({ space: 4 }) {
          Circle({ width: 6, height: 6 })
            .fill(t.priority === 'high' ? this.pal().accent : t.priority === 'medium' ? 'transparent' : this.pal().text3)
            .stroke(t.priority === 'medium' ? this.pal().accent : 'transparent')
            .strokeWidth(t.priority === 'medium' ? 1.5 : 0)
          Text(t.priority === 'high' ? '高' : t.priority === 'medium' ? '中' : '低')
            .fontSize(FontSize.secondary)
            .fontWeight(t.priority === 'high' ? Weight.semibold : Weight.regular)
            .fontColor(t.priority === 'high' ? this.pal().accent : this.pal().text2)
        }
        .margin({ top: 2 })
      }
      Column({ space: 3 }) {
        Text(t.title)
          .fontSize(FontSize.body)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (t.category !== '') {
          Text(t.category)
            .fontSize(FontSize.secondary)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text2)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .backgroundColor(this.pal().chip)
            .borderRadius(4)
        }
        if (isAITask(t)) {
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
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (t.dueTime !== '') {
        Text(t.dueTime)
          .fontSize(FontSize.secondary)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text3)
          .margin({ top: 2 })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.openEdit(t);
    })
  }
  build() {
    Stack() {
      Column() {
        // 顶部不再放「添加」按钮（新建走顶栏「+ 新建任务」或列表页）
        // 轨道横幅（对齐 web tl-banner）
        Row({ space: 4 }) {
          Text('学习轨道：')
            .fontSize(FontSize.secondary)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text3)
          Text(this.trackBanner)
            .fontSize(FontSize.secondary)
            .fontWeight(Weight.semibold)
            .fontColor(this.pal().accent)
        }
        .width('100%')
        .padding({ left: Space.s2, right: Space.s2, top: 6 })

        // 轨道切换 chips：多轨道时一键切到另一条（不必滚过整条轨道）
        Row({ space: 6 }) {
          this.laneChip('all', '全部')
          ForEach(this.lanes, (l: LaneModel) => {
            this.laneChip(l.name, l.name)
          }, (l: LaneModel) => l.name)
          if (this.others.length > 0) {
            this.laneChip('other', '其他')
          }
        }
        .width('100%')
        .padding({ left: Space.s2, right: Space.s2, top: 8 })

        if (this.lanes.length === 0 && this.others.length === 0) {
          Column({ space: Space.s1 }) {
            Text(this.syncText === '' ? '没有带截止日期的任务' : this.syncText)
              .fontSize(FontSize.body)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text2)
            Button('添加任务')
              .height(TOUCH_TARGET)
              .padding({ left: 24, right: 24 })
              .fontSize(FontSize.body)
              .fontWeight(Weight.semibold)
              .fontColor(this.pal().accent)
              .backgroundColor(this.isDark ? 'rgba(94,106,210,0.24)' : 'rgba(0,102,204,0.14)')
              .backdropBlur(12)
              .saturate(1.4)
              .borderRadius(Radius.pill)
              .border({ width: 0.5, color: this.isDark ? 'rgba(130,143,255,0.38)' : 'rgba(0,102,204,0.30)' })
              .shadow({ radius: 8, color: 'rgba(0,0,0,0.04)', offsetY: 2 })
              .onClick(() => {
                this.openNew();
              })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else {
          List() {
            ForEach(this.visibleLanes(), (lane: LaneModel) => {
              ListItem() {
                Column() {
                  // 泳道头（对齐 web tl-laneh：accent 点 + 名 600 + 计数右置）
                  Row({ space: 9 }) {
                    Circle({ width: 10, height: 10 }).fill(this.pal().accent)
                    Text(lane.name)
                      .fontSize(FontSize.panelTitle)
                      .fontWeight(Weight.semibold)
                      .fontColor(this.pal().text)
                      .layoutWeight(1)
                    Text('' + lane.count)
                      .fontSize(FontSize.secondary)
                      .fontWeight(Weight.regular)
                      .fontColor(this.pal().text3)
                  }
                  .padding({ left: Space.s2, right: Space.s2, top: 16, bottom: 12 })

                  // 日期轴（对齐 web tl-axis：2px 竖线 + 节点圆点 + M月D日）
                  Column() {
                    ForEach(lane.days, (d: DayGroup) => {
                      Column() {
                        Row({ space: 6 }) {
                          Circle({ width: 10, height: 10 })
                            .fill(d.date === this.todayStr() ? this.pal().accent : this.pal().border2)
                            .margin({ left: -23, top: 3 })
                          Text(this.tlLabel(d.date))
                            .fontSize(FontSize.body)
                            .fontWeight(Weight.semibold)
                            .fontColor(d.date === this.todayStr() ? this.pal().accent : this.pal().text)
                          if (d.date === this.todayStr()) {
                            Text('今天')
                              .fontSize(FontSize.groupLabel)
                              .fontWeight(Weight.regular)
                              .fontColor(this.pal().text3)
                          }
                        }
                        .alignItems(VerticalAlign.Top)
                        .margin({ top: 12 })
                        ForEach(d.tasks, (t: Task) => {
                          this.tlItem(t)
                        }, (t: Task) => t.id)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .width('100%')
                    }, (d: DayGroup) => d.date)
                  }
                  .width('100%')
                  .margin({ left: 22 })
                  .padding({ left: 18 })
                  .border({ width: { left: 2 }, color: this.pal().border })
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding({ bottom: 20 })
                .backgroundColor(this.pal().bg)   // ListItem 默认白底，盖回页面底色
              }
            }, (lane: LaneModel) => lane.name)

            // 其他任务（未分配轨道，折叠区，对齐 web other-fold）
            if (this.others.length > 0 && (this.laneSel === 'all' || this.laneSel === 'other')) {
              ListItem() {
                Column() {
                  Row({ space: 6 }) {
                    Image($r('app.media.chevron_down'))
                      .width(14)
                      .height(14)
                      .fillColor(this.pal().text3)
                      .rotate({ angle: this.otherOpen ? 0 : -90 })
                    Text('其他任务')
                      .fontSize(FontSize.panelTitle)
                      .fontWeight(Weight.semibold)
                      .fontColor(this.pal().text)
                    Text('未分配轨道')
                      .fontSize(FontSize.groupLabel)
                      .fontWeight(Weight.regular)
                      .fontColor(this.pal().text3)
                    Blank()
                    Text('' + this.otherCount())
                      .fontSize(FontSize.secondary)
                      .fontWeight(Weight.regular)
                      .fontColor(this.pal().text3)
                  }
                  .width('100%')
                  .padding({ left: Space.s2, right: Space.s2, top: 16, bottom: 8 })
                  .onClick(() => {
                    this.otherOpen = !this.otherOpen;
                  })
                  if (this.otherOpen) {
                    ForEach(this.others, (g: OtherGroup) => {
                      Column() {
                        Row({ space: 6 }) {
                          Text(g.cat)
                            .fontSize(FontSize.body)
                            .fontWeight(Weight.semibold)
                            .fontColor(this.pal().text)
                          Text('' + g.tasks.length)
                            .fontSize(FontSize.secondary)
                            .fontWeight(Weight.regular)
                            .fontColor(this.pal().text3)
                        }
                        .padding({ top: 8, bottom: 4 })
                        ForEach(g.tasks, (t: Task) => {
                          this.tlItem(t)
                        }, (t: Task) => t.id)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .width('100%')
                      .padding({ left: Space.s2 })
                    }, (g: OtherGroup) => g.cat)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .backgroundColor(this.pal().bg)
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ bottom: 8 })   // 只留极小呼吸位（同行列表页）
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().bg)

      // 共享任务编辑弹层（条件渲染：每次打开重新挂载）
      if (this.taskEditVisible) {
        TaskEditSheet({
          taskId: this.taskEditId,
          onClose: () => {
            this.taskEditVisible = false;
          },
          onSaved: () => {
            this.buildTimeline(SyncEngine.tasks);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
