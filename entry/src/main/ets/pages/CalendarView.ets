import { common } from '@kit.AbilityKit';
import { FontSize, Palette, Radius, Space, Weight, palette } from '../common/Theme';
import { SyncEngine } from '../common/SyncEngine';
import { Store } from '../common/Storage';
import { Task } from '../common/Models';

// 日历单元格：day<0 = 空位；idx = 稳定索引（ForEach key 用）
class CalCell {
  day: number = -1;
  dateStr: string = '';
  events: Task[] = [];
  idx: number = 0;
}

/**
 * 日历视图（批 2）：月历（今天实心 accent 圆 + 事件胶囊 + 上/下月导航 + 今天按钮）
 * + 选中日任务列表。对齐 web mcal-cell/mcal-grid/cal-daylist。
 */
@Component
export struct CalendarView {
  @StorageProp('darkMode') isDark: boolean = false;
  @Prop refreshKey: number = 0;   // Index 保存任务后 bump，触发刷新
    @State year: number = 2026;
  @State month: number = 1;
  @State selDay: number = 0;   // 0 = 未选
  @State selDate: string = '';
  @State calMode: string = 'month';   // month / week（对齐 web calMode）
  @State tick: number = 0;            // 拉取/本地变更后 bump 触发重渲染

  private pal(): Palette {
    return palette(this.isDark);
  }

  aboutToAppear(): void {
    const d = new Date();
    this.year = d.getFullYear();
    this.month = d.getMonth() + 1;
    this.load();
  }

  
  async load(): Promise<void> {
    try {
      await Store.init(getContext(this) as common.Context);
      await SyncEngine.fullPull();
      this.tick = this.tick + 1;   // 拉取完成后自 bump（依赖注册模式）
    } catch (e) {
    }
  }

  private pad(n: number): string {
    return ('0' + n).slice(-2);
  }

  private dateStr(y: number, m: number, day: number): string {
    return y + '-' + this.pad(m) + '-' + this.pad(day);
  }

  private todayStr(): string {
    const d = new Date();
    return this.dateStr(d.getFullYear(), d.getMonth() + 1, d.getDate());
  }

  private daysInMonth(y: number, m: number): number {
    return new Date(y, m, 0).getDate();
  }

  private firstWeekday(y: number, m: number): number {
    return new Date(y, m - 1, 1).getDay();  // 0=周日
  }

  private eventsOf(date: string): Task[] {
    // 对齐 web：日历只收 pending 且有截止日的任务
    const key = this.refreshKey;   // 依赖注册：保存后 bump → 重建
    const tick = this.tick;
    const list = SyncEngine.tasks;
    const out: Task[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].dueDate === date && list[i].status === 'pending') { out.push(list[i]); }
    }
    return out;
  }

  private cells(): CalCell[] {
    const out: CalCell[] = [];
    const lead = this.firstWeekday(this.year, this.month);
    const dim = this.daysInMonth(this.year, this.month);
    let idx = 0;
    for (let i = 0; i < lead; i++) {
      const c = new CalCell();
      c.idx = idx;
      idx++;
      out.push(c);
    }
    for (let d = 1; d <= dim; d++) {
      const c = new CalCell();
      c.day = d;
      c.dateStr = this.dateStr(this.year, this.month, d);
      c.events = this.eventsOf(c.dateStr);
      c.idx = idx;
      idx++;
      out.push(c);
    }
    while (out.length < 42) {
      const c = new CalCell();
      c.idx = idx;
      idx++;
      out.push(c);
    }
    return out;
  }

  private monthLabel(): string {
    return this.year + '年' + this.month + '月';
  }

  private goMonth(delta: number): void {
    let m = this.month + delta;
    let y = this.year;
    if (m < 1) { m = 12; y = y - 1; }
    if (m > 12) { m = 1; y = y + 1; }
    this.year = y;
    this.month = m;
  }

  private gotoToday(): void {
    const d = new Date();
    this.year = d.getFullYear();
    this.month = d.getMonth() + 1;
    this.selDay = d.getDate();
    this.selDate = this.todayStr();
  }

  // 周视图：以选中日（缺省今天）为中心的一周 7 天
  private weekDates(): string[] {
    const base = this.selDate.length >= 10 ? this.selDate : this.todayStr();
    const y = parseInt(base.substring(0, 4));
    const m = parseInt(base.substring(5, 7));
    const d = parseInt(base.substring(8, 10));
    const wd = new Date(y, m - 1, d).getDay();
    const out: string[] = [];
    for (let i = 0; i < 7; i++) {
      const dt = new Date(y, m - 1, d - wd + i);
      out.push(this.dateStr(dt.getFullYear(), dt.getMonth() + 1, dt.getDate()));
    }
    return out;
  }

  private dayOf(ds: string): string {
    return ds.length >= 10 ? '' + parseInt(ds.substring(8, 10)) : '';
  }

  private wdLabel(ds: string): string {
    if (ds.length < 10) { return ''; }
    const cn = ['日', '一', '二', '三', '四', '五', '六'];
    const y = parseInt(ds.substring(0, 4));
    const m = parseInt(ds.substring(5, 7));
    const d = parseInt(ds.substring(8, 10));
    return '周' + cn[new Date(y, m - 1, d).getDay()];
  }

  private selEvents(): Task[] {
    if (this.selDate === '') { return []; }
    return this.eventsOf(this.selDate);
  }

  // 选中日标题（对齐 web：M月D日 · 周X）
  private selTitle(): string {
    if (this.selDate.length < 10) { return ''; }
    const m = parseInt(this.selDate.substring(5, 7));
    const d = parseInt(this.selDate.substring(8, 10));
    const y = parseInt(this.selDate.substring(0, 4));
    const wd = new Date(y, m - 1, d).getDay();
    const cn = ['日', '一', '二', '三', '四', '五', '六'];
    return m + '月' + d + '日 · 周' + cn[wd];
  }

  @Builder
  dpRow(t: Task) {
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
          .fontWeight(Weight.semibold)
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
    .padding({ left: Space.s2, right: Space.s2, top: 10, bottom: 10 })
    .backgroundColor(this.pal().bg)   // ListItem 默认白底，盖回页面底色
  }

  @Builder
  modeBtn(key: string, label: string) {
    Text(label)
      .fontSize(FontSize.secondary)
      .fontWeight(this.calMode === key ? Weight.semibold : Weight.regular)
      .fontColor(this.calMode === key ? this.pal().accent : this.pal().text2)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(this.calMode === key ? this.pal().card : 'transparent')
      .borderRadius(Radius.control)
      .onClick(() => {
        this.calMode = key;
      })
  }

  /** 事件胶囊（月/周共用，对齐 web .ev：accent-soft + 优先级点，高=实心 accent） */
  @Builder
  evChip(t: Task) {
    Row({ space: 3 }) {
      Circle({ width: 5, height: 5 })
        .fill(t.priority === 'high' ? '#ffffff' : this.pal().accent)
      Text(t.title.length > 6 ? t.title.substring(0, 6) + '…' : t.title)
        .fontSize(FontSize.helper)
        .fontWeight(Weight.regular)
        .fontColor(t.priority === 'high' ? '#ffffff' : this.pal().accent)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 1, bottom: 1 })
    .margin({ top: 2, left: 3, right: 3 })
    .backgroundColor(t.priority === 'high' ? this.pal().accent : (this.isDark ? 'rgba(94,106,210,0.18)' : 'rgba(0,102,204,0.08)'))
    .borderRadius(4)
  }

  build() {
    Column() {
      // 头部（对齐 web cal-head）：‹ 标题 › 今天
      Row() {
        // 月份标签顶到最左（用户 2026-09-12）
        Text(this.monthLabel())
          .fontSize(FontSize.panelTitle)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().text)
        Blank()
        Image($r('app.media.chevron_left'))
          .width(16)
          .height(16)
          .fillColor(this.pal().text2)
          .padding(6)
          .onClick(() => {
            this.goMonth(-1);
          })
        Image($r('app.media.chevron_right'))
          .width(16)
          .height(16)
          .fillColor(this.pal().text2)
          .padding(6)
          .onClick(() => {
            this.goMonth(1);
          })
        Button('今天')
          .height(30)
          .padding({ left: 12, right: 12 })
          .fontSize(FontSize.secondary)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().accent)
          .backgroundColor(this.isDark ? 'rgba(94,106,210,0.18)' : 'rgba(0,102,204,0.08)')
          .borderRadius(Radius.pill)
          .onClick(() => {
            this.gotoToday();
          })
        // 月/周切换（对齐 web cmode）
        Row({ space: 2 }) {
          this.modeBtn('month', '月')
          this.modeBtn('week', '周')
        }
        .padding(2)
        .backgroundColor(this.pal().chip)
        .borderRadius(Radius.control)
      }
      .width('100%')
      .padding({ left: Space.s2, right: Space.s2, top: Space.s1, bottom: 4 })

      // 星期头
      Row() {
        ForEach(['日', '一', '二', '三', '四', '五', '六'], (w: string) => {
          Text(w)
            .fontSize(FontSize.groupLabel)
            .fontWeight(Weight.semibold)
            .fontColor(this.pal().text3)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
        }, (w: string) => w)
      }
      .width('100%')
      .padding({ left: Space.s1, right: Space.s1, bottom: 4 })

      // 月历网格（对齐 web mcal-cell：数字居左上，事件胶囊 accent-soft，今天=accent描边，选中=accent-soft底）
      if (this.calMode === 'month') {
      Grid() {
        ForEach(this.cells(), (c: CalCell) => {
          GridItem() {
            Column() {
              if (c.day > 0) {
                Text('' + c.day)
                  .fontSize(FontSize.body)
                  .fontWeight(Weight.semibold)
                  .fontColor(c.dateStr === this.todayStr() || c.dateStr === this.selDate ? this.pal().accent : this.pal().text)
                  .padding({ left: 6, top: 5 })
                ForEach(c.events.slice(0, 2), (t: Task) => {
                  this.evChip(t)
                }, (t: Task) => t.id)
                if (c.events.length > 2) {
                  Text('+' + (c.events.length - 2))
                    .fontSize(FontSize.helper)
                    .fontWeight(Weight.regular)
                    .fontColor(this.pal().text3)
                    .padding({ left: 6 })
                }
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .height('100%')
          }
          .height(64)
          .backgroundColor(c.day > 0
            ? (c.dateStr === this.selDate ? (this.isDark ? 'rgba(94,106,210,0.18)' : 'rgba(0,102,204,0.08)') : this.pal().card2)
            : 'transparent')
          .borderRadius(12)
          .border(c.dateStr === this.todayStr()
            ? { width: 1.5, color: this.pal().accent }
            : { width: 0.5, color: 'transparent' })
          .onClick(() => {
            if (c.day > 0) {
              this.selDay = c.day;
              this.selDate = c.dateStr;
            }
          })
        }, (c: CalCell) => '' + c.idx)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .columnsGap(4)
      .rowsGap(4)
      .width('100%')
      .padding({ left: Space.s1, right: Space.s1 })
      } else {
      // 周视图（对齐 web mcal-week：7 列日期+星期+事件胶囊，今天 accent）
      Grid() {
        ForEach(this.weekDates(), (ds: string) => {
          GridItem() {
            Column() {
              Row({ space: 3 }) {
                Text(this.dayOf(ds))
                  .fontSize(FontSize.body)
                  .fontWeight(Weight.semibold)
                  .fontColor(ds === this.todayStr() ? this.pal().accent : this.pal().text)
                Text(this.wdLabel(ds))
                  .fontSize(FontSize.helper)
                  .fontWeight(Weight.regular)
                  .fontColor(ds === this.todayStr() ? this.pal().accent : this.pal().text3)
              }
              .padding({ top: 6, bottom: 4 })
              ForEach(this.eventsOf(ds).slice(0, 3), (t: Task) => {
                this.evChip(t)
              }, (t: Task) => t.id)
              if (this.eventsOf(ds).length > 3) {
                Text('+' + (this.eventsOf(ds).length - 3))
                  .fontSize(FontSize.helper)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().text3)
                  .padding({ top: 2 })
              }
              if (ds === this.todayStr()) {
                Row({ space: 4 }) {
                  Circle({ width: 5, height: 5 }).fill(this.pal().accent)
                  Text('今天')
                    .fontSize(FontSize.helper)
                    .fontWeight(Weight.semibold)
                    .fontColor(this.pal().accent)
                }
                .padding({ top: 4 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .height('100%')
            .padding(4)
          }
          .height(150)
          .backgroundColor(ds === this.selDate
            ? (this.isDark ? 'rgba(94,106,210,0.18)' : 'rgba(0,102,204,0.08)')
            : this.pal().card2)
          .borderRadius(12)
          .onClick(() => {
            this.selDate = ds;
            this.year = parseInt(ds.substring(0, 4));
            this.month = parseInt(ds.substring(5, 7));
            this.selDay = parseInt(ds.substring(8, 10));
          })
        }, (ds: string) => ds)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .columnsGap(4)
      .width('100%')
      .padding({ left: Space.s1, right: Space.s1 })
      }

      // 选中日列表（对齐 web cal-daylist：M月D日 · 周X + accent 计数徽章）
      Row() {
        Text(this.selTitle())
          .fontSize(FontSize.listBody)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().text)
        if (this.selDate !== '') {
          Text('' + this.selEvents().length)
            .fontSize(FontSize.helper)
            .fontWeight(Weight.semibold)
            .fontColor(this.pal().accent)
            .padding({ left: 7, right: 7, top: 1, bottom: 1 })
            .border({ width: 1, color: this.pal().accent })
            .borderRadius(Radius.control)
            .margin({ left: 6 })
        }
      }
      .width('100%')
      .padding({ left: Space.s2, right: Space.s2, top: Space.s1, bottom: 4 })

      if (this.selEvents().length === 0) {
        Text(this.selDate === '' ? '选择日期查看任务' : '该日无到期待办')
          .fontSize(FontSize.listBody)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text3)
          .width('100%')
          .padding({ left: Space.s2, top: 8 })
      } else {
        List() {
          ForEach(this.selEvents(), (t: Task) => {
            ListItem() {
              this.dpRow(t)
            }
          }, (t: Task) => t.id)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: this.pal().border })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().bg)
  }
}
