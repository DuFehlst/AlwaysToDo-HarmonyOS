import { Weight } from '../../common/Theme';

/**
 * 桌面服务卡片（v2.3 · iOS 三段式版式）
 *
 * 版式（用户 2026-09-12 指定，参考 iOS 小组件）：
 *   上方  = title 行（今天 ＋ 右上角 AlwaysToDo）
 *   左下  = 数字（今日任务数，视觉主语）＋ 待办/逾期
 *   右下  = 具体任务清单（2×2→1 条／2×4→3 条／4×4→8 条；有空位时才挂「+ 添加任务」）
 *
 * 尺寸标定（真机像素测量，2026-09-12）：
 *   卡片单位 = vp（1vp ≈ 3.25px）；2×2 / 2×4 ≈ 161vp 高，4×4 ≈ 369vp
 *   预算：padding 28 + header 18 + gap 6 + 下段
 *     2×2 → 1 行×30 = 30／2×4 → 3×30+4 = 94 ≤ 109 ✓／4×4 → 行高 36：8×36+14 = 302 ≤ 317 ✓（多显示 2 条）
 * 约束：**禁止纵向 Blank**；空态与居中一律用 justifyContent（高度受约束，安全）
 * 交互：Checkbox 勾选完成（postCardAction message，不打开 App）／点标题深链到该任务／点「+」新建
 * 配色：全部 $r('app.color.card_*')（base/dark 双份，跟随系统深浅）
 */
@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('dim') dim: string = '2x2';
  @LocalStorageProp('empty') empty: string = '0';
  @LocalStorageProp('todayCount') todayCount: string = '—';
  @LocalStorageProp('pendingCount') pendingCount: string = '—';
  @LocalStorageProp('overdueCount') overdueCount: string = '0';
  @LocalStorageProp('budget') budget: string = '1';
  @LocalStorageProp('showAdd') showAdd: string = '0';
  @LocalStorageProp('t1') t1: string = '';
  @LocalStorageProp('t2') t2: string = '';
  @LocalStorageProp('t3') t3: string = '';
  @LocalStorageProp('t4') t4: string = '';
  @LocalStorageProp('t5') t5: string = '';
  @LocalStorageProp('t6') t6: string = '';
  @LocalStorageProp('t7') t7: string = '';
  @LocalStorageProp('t8') t8: string = '';
  @LocalStorageProp('id1') id1: string = '';
  @LocalStorageProp('id2') id2: string = '';
  @LocalStorageProp('id3') id3: string = '';
  @LocalStorageProp('id4') id4: string = '';
  @LocalStorageProp('id5') id5: string = '';
  @LocalStorageProp('id6') id6: string = '';
  @LocalStorageProp('id7') id7: string = '';
  @LocalStorageProp('id8') id8: string = '';
  @LocalStorageProp('f1') f1: string = '';
  @LocalStorageProp('f2') f2: string = '';
  @LocalStorageProp('f3') f3: string = '';
  @LocalStorageProp('f4') f4: string = '';
  @LocalStorageProp('f5') f5: string = '';
  @LocalStorageProp('f6') f6: string = '';
  @LocalStorageProp('f7') f7: string = '';
  @LocalStorageProp('f8') f8: string = '';

  /** 行高随卡片高度走：4×4 卡片高得多，行也放高一些，避免下方大片空白 */
  private rowH(): number {
    return this.dim === '4x4' ? 36 : 30;
  }

  private toggle(id: string): void {
    postCardAction(this, { action: 'message', params: { 'toggle': id } });
  }

  private openTask(id: string): void {
    postCardAction(this, {
      action: 'router',
      want: {
        bundleName: 'com.always.todosync',
        abilityName: 'EntryAbility',
        parameters: { 'taskId': id }
      }
    });
  }

  private openNew(): void {
    postCardAction(this, {
      action: 'router',
      want: {
        bundleName: 'com.always.todosync',
        abilityName: 'EntryAbility',
        parameters: { 'pendingNew': '1' }
      }
    });
  }

  /** 上方：title 行 */
  @Builder
  header() {
    Row() {
      Text('今天')
        .fontSize(13)
        .fontWeight(Weight.semibold)
        .fontColor($r('app.color.card_text3'))
      Blank()
      Text('AlwaysToDo')
        .fontSize(11)
        .fontWeight(Weight.regular)
        .fontColor($r('app.color.card_text3'))
    }
    .width('100%')
    .height(18)
  }

  /** 左下：数字（视觉主语）＋ 标签 */
  @Builder
  bigNumber() {
    Row({ space: 6 }) {
      Text(this.todayCount)
        .fontSize(42)
        .fontWeight(Weight.semibold)
        .fontColor($r('app.color.card_text'))
      Text('今日任务')
        .fontSize(13)
        .fontWeight(Weight.regular)
        .fontColor($r('app.color.card_text3'))
        .margin({ bottom: 7 })
    }
    .alignItems(VerticalAlign.Bottom)
  }

  /** 左下：待办 / 逾期 */
  @Builder
  leftStats() {
    Column({ space: 2 }) {
      Text('待办 ' + this.pendingCount)
        .fontSize(12)
        .fontWeight(Weight.regular)
        .fontColor($r('app.color.card_text3'))
      if (this.overdueCount !== '0') {
        Text('逾期 ' + this.overdueCount)
          .fontSize(12)
          .fontWeight(Weight.regular)
          .fontColor($r('app.color.card_danger'))
      }
    }
    .alignItems(HorizontalAlign.Start)
  }

  /** 右下：单条任务（勾选圈 + 标题深链 + 标记） */
  @Builder
  taskRow(title: string, id: string, flag: string) {
    Row({ space: 7 }) {
      Checkbox({ name: id, group: 'todo' })
        .select(false)
        .selectedColor($r('app.color.card_accent'))
        .width(22)
        .height(22)
        .onChange(() => {
          this.toggle(id);
        })
      Text(title)
        .fontSize(13)
        .fontWeight(Weight.regular)
        .fontColor($r('app.color.card_text'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .onClick(() => {
          this.openTask(id);
        })
      if (flag === 'due') {
        Text('逾期')
          .fontSize(10)
          .fontWeight(Weight.regular)
          .fontColor($r('app.color.card_danger'))
      } else if (flag === 'high') {
        Circle({ width: 6, height: 6 }).fill($r('app.color.card_accent'))
      } else if (flag === 'ai') {
        Text('AI')
          .fontSize(10)
          .fontWeight(Weight.semibold)
          .fontColor($r('app.color.card_accent'))
      }
    }
    .width('100%')
    .height(this.rowH())
  }

  @Builder
  addRow() {
    Row() {
      Text('+ 添加任务')
        .fontSize(13)
        .fontWeight(Weight.regular)
        .fontColor($r('app.color.card_accent'))
    }
    .width('100%')
    .height(30)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.card_chip'))
    .borderRadius(999)
    .onClick(() => {
      this.openNew();
    })
  }

  @Builder
  emptyHint() {
    Column({ space: 3 }) {
      Text('今天没有任务')
        .fontSize(17)
        .fontWeight(Weight.semibold)
        .fontColor($r('app.color.card_text'))
      Text('享受空闲，或加一件小事')
        .fontSize(12)
        .fontWeight(Weight.regular)
        .fontColor($r('app.color.card_text3'))
    }
    .alignItems(HorizontalAlign.Start)
  }

  /** 右下：清单（含空态与可用空位时的入口） */
  @Builder
  rightList() {
    Column({ space: 2 }) {
      if (this.empty === '1') {
        this.emptyHint()
        if (this.showAdd === '1') {
          this.addRow()
        }
      } else {
        if (this.t1 !== '') {
          this.taskRow(this.t1, this.id1, this.f1)
        }
        if (this.t2 !== '') {
          this.taskRow(this.t2, this.id2, this.f2)
        }
        if (this.t3 !== '') {
          this.taskRow(this.t3, this.id3, this.f3)
        }
        if (this.t4 !== '') {
          this.taskRow(this.t4, this.id4, this.f4)
        }
        if (this.t5 !== '') {
          this.taskRow(this.t5, this.id5, this.f5)
        }
        if (this.t6 !== '') {
          this.taskRow(this.t6, this.id6, this.f6)
        }
        if (this.t7 !== '') {
          this.taskRow(this.t7, this.id7, this.f7)
        }
        if (this.t8 !== '') {
          this.taskRow(this.t8, this.id8, this.f8)
        }
        if (this.showAdd === '1') {
          this.addRow()
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 1×2 状态条（最小尺寸不做三段式） */
  @Builder
  statusBar() {
    Row({ space: 8 }) {
      Text(this.todayCount)
        .fontSize(30)
        .fontWeight(Weight.semibold)
        .fontColor($r('app.color.card_accent'))
      Text('今天')
        .fontSize(13)
        .fontWeight(Weight.regular)
        .fontColor($r('app.color.card_text3'))
      Blank()
      Text('待办 ' + this.pendingCount)
        .fontSize(14)
        .fontWeight(Weight.regular)
        .fontColor($r('app.color.card_text2'))
    }
    .width('100%')
  }

  build() {
    Column({ space: 6 }) {
      if (this.dim === '1x2') {
        this.statusBar()
      } else {
        // 上方：title
        this.header()
        // 下段：左下数字 + 右下清单（layoutWeight 占满剩余高度，不用 Blank）
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            this.bigNumber()
            this.leftStats()
          }
          .width('32%')
          .alignItems(HorizontalAlign.Start)

          Column() {
            this.rightList()
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          // 空态在右下区域内竖向居中，看起来是刻意的留白
          .justifyContent(this.empty === '1' ? FlexAlign.Center : FlexAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.card_bg'))
  }
}
