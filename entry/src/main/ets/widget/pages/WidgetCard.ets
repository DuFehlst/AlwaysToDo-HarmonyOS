import { FontSize, Palette, Space, Weight, palette } from '../../common/Theme';

/**
 * 桌面服务卡片（v1.1）：今日任务数 / 待办数 + 添加任务按钮（拉起 App）。
 * 数据绑定：formBindingData 键（todayCount/pendingCount）↔ @LocalStorageProp。
 * 注意：卡片不支持 @StorageProp → 固定亮色 token（深色适配留后续）。
 * postCardAction 是卡片页环境的全局函数，不 import。
 */
@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('todayCount') todayCount: string = '—';
  @LocalStorageProp('pendingCount') pendingCount: string = '—';
  @LocalStorageProp('t1') t1: string = '';
  @LocalStorageProp('t2') t2: string = '';
  @LocalStorageProp('t3') t3: string = '';

  private pal(): Palette {
    return palette(false);
  }

  @Builder
  titleRow(txt: string) {
    Row({ space: 6 }) {
      Circle({ width: 5, height: 5 })
        .fill(this.pal().accent)
      Text(txt)
        .fontSize(FontSize.secondary)
        .fontWeight(Weight.regular)
        .fontColor(this.pal().text2)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 3, bottom: 3 })
  }

  build() {
    Column({ space: Space.s1 }) {
      Text('AlwaysToDo')
        .fontSize(FontSize.secondary)
        .fontWeight(Weight.semibold)
        .fontColor(this.pal().text)

      Row({ space: Space.s2 }) {
        Column({ space: 2 }) {
          Text(this.todayCount)
            .fontSize(FontSize.pageTitle)
            .fontWeight(Weight.semibold)
            .fontColor(this.pal().text)
          Text('今日任务')
            .fontSize(FontSize.helper)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text3)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 2 }) {
          Text(this.pendingCount)
            .fontSize(FontSize.pageTitle)
            .fontWeight(Weight.semibold)
            .fontColor(this.pal().text)
          Text('待办')
            .fontSize(FontSize.helper)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text3)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      // v1.1：今日任务标题预览（最多 3 条）
      if (this.t1 !== '') {
        this.titleRow(this.t1)
      }
      if (this.t2 !== '') {
        this.titleRow(this.t2)
      }
      if (this.t3 !== '') {
        this.titleRow(this.t3)
      }

      Button('添加任务')
        .width('100%')
        .height(32)
        .fontSize(FontSize.secondary)
        .fontWeight(Weight.regular)
        .fontColor(this.pal().text)
        .backgroundColor(this.pal().card2)
        .borderRadius(999)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            want: {
              bundleName: 'com.always.todosync',
              abilityName: 'EntryAbility',
              parameters: { 'pendingNew': '1' }
            }
          });
        })
    }
    .width('100%')
    .height('100%')
    .padding(Space.s2)
    .alignItems(HorizontalAlign.Start)
  }
}
