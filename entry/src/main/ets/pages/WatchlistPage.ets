import { FontSize, Palette, Radius, Space, TOUCH_TARGET, Weight, palette } from '../common/Theme';
import { ApiClient } from '../common/ApiClient';
import { WatchlistItem, WatchlistStore, BrainCandidate } from '../common/Models';
import { common, Want } from '@kit.AbilityKit';

/**
 * 稍后再看 Tab（P3·7 列表 + P3·8 条目编辑）。
 * 点条目弹编辑卡：重要性/分类/完成/summary，保存走 POST /api/watchlist（服务器按 id 合并）。
 * 布局：内容优先裸排；单 accent；字重 300/400/600；浮层唯一例外阴影。
 */
@Component
export struct WatchlistPage {
  @StorageProp('darkMode') isDark: boolean = false;
  @State items: WatchlistItem[] = [];
  @State categories: string[] = [];
  @State activeCat: string = '全部';
  @State sortMode: string = 'added';
  @State sortOpen: boolean = false;   // 排序下拉（页头右侧叠放，与列表页同款）
  @StorageProp('showWatched') showWatched: boolean = false;
  @State loadText: string = '';
  // 编辑弹层（字段对齐 web 稍后再看详情：标题/原始地址/分类/重要性/概述/综述/来源时间/计划看完/加入时间）
  @State editVisible: boolean = false;
  @State editItem: WatchlistItem = new WatchlistItem();
  @State fTitle: string = '';
  @State fUrl: string = '';
  @State fImportance: string = 'B';
  @State fCategory: string = '';
  @State fSummary: string = '';
  @State fOverview: string = '';
  @State fSourceDate: string = '';
  @State fDueDate: string = '';
  // 删除确认弹层
  @State delVisible: boolean = false;
  @State detailVisible: boolean = false;
  @State detailItem: WatchlistItem = new WatchlistItem();
  // 添加链接弹层
  @State urlVisible: boolean = false;
  @State urlInput: string = '';
  // 归档建议弹层
  @State arcVisible: boolean = false;
  @State arcItem: WatchlistItem = new WatchlistItem();
  @State arcCands: BrainCandidate[] = [];
  @State arcRec: string = '';
  @State arcSelId: string = '';
  @State arcImp: string = 'C';
  @State arcInput: string = '';
  @State arcSugImp: string = '';
  @State arcSugTopic: string = '';

  private pal(): Palette {
    return palette(this.isDark);
  }

  private buttonRadius(): number {
    return this.isDark ? Radius.control : Radius.pill;
  }

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    try {
      const list = await ApiClient.watchlist();
      this.items = list;
      WatchlistStore.items = list;
      const cats: string[] = [];
      for (let i = 0; i < list.length; i++) {
        const c = list[i].category;
        if (c !== '' && cats.indexOf(c) < 0) { cats.push(c); }
      }
      this.categories = cats;
      this.loadText = list.length ? '' : '还没有稍后再看的条目';
    } catch (e) {
      this.loadText = '加载失败';
    }
  }

  private impRank(imp: string): number {
    if (imp === 'S') { return 0; }
    if (imp === 'A') { return 1; }
    if (imp === 'B') { return 2; }
    return 3;
  }

  private visible(): WatchlistItem[] {
    let list = this.items;
    if (this.activeCat !== '全部') {
      list = list.filter((x: WatchlistItem) => x.category === this.activeCat);
    }
    if (!this.showWatched) {
      list = list.filter((x: WatchlistItem) => x.status !== 'watched');
    }
    const mode = this.sortMode;
    const out = list.slice().sort((a: WatchlistItem, b: WatchlistItem) => {
      if (mode === 'due') {
        // web watchDueCompare：无计划看完者沉底，先比 dueDate 再比加入时间
        const aN = a.dueDate === '';
        const bN = b.dueDate === '';
        if (aN !== bN) { return aN ? 1 : -1; }
        if (!aN && !bN) {
          const d = (a.dueDate || '').localeCompare(b.dueDate || '');
          if (d !== 0) { return d; }
        }
        return (b.addedAt || '').localeCompare(a.addedAt || '');
      }
      if (mode === 'sourceDate') {
        const d = (b.sourceDate || '').localeCompare(a.sourceDate || '');
        if (d !== 0) { return d; }
        return (b.addedAt || '').localeCompare(a.addedAt || '');
      }
      if (mode === 'importance') {
        const d = this.impRank(a.importance) - this.impRank(b.importance);
        if (d !== 0) { return d; }
        return (b.addedAt || '').localeCompare(a.addedAt || '');
      }
      return (b.addedAt || '').localeCompare(a.addedAt || '');
    });
    return out;
  }

  async toggleWatched(t: WatchlistItem, on: boolean): Promise<void> {
    t.status = on ? 'watched' : 'unwatched';
    try {
      await ApiClient.markWatched(t.id, on);
    } catch (e) {
      // 离线忽略
    }
    this.items = this.items.slice();
    if (on && t.brain_id === '' && !t.skip_brain) {
      await this.openArchive(t);
    }
  }

  async openArchive(t: WatchlistItem): Promise<void> {
    try {
      const s = await ApiClient.brainSuggest(t.title, t.summary, t.url, t.source);
      this.arcItem = t;
      this.arcCands = s.candidates;
      this.arcRec = s.recommended;
      this.arcSelId = s.recommended;
      this.arcSugImp = s.suggestedImportance;
      this.arcSugTopic = s.suggestedTopic;
      this.arcImp = s.suggestedImportance !== '' ? s.suggestedImportance : (t.importance !== '' ? t.importance : 'C');
      this.arcInput = '';
      animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.arcVisible = true; });
      this.syncSheetFlag();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '归档建议不可用' });
    }
  }

  async confirmArchive(): Promise<void> {
    const t = this.arcItem;
    const imp = this.arcImp;
    try {
      let ideaId = '';
      if (this.arcInput.trim() !== '') {
        ideaId = await ApiClient.brainResolveTopic(this.arcInput, this.arcCands);
      } else {
        ideaId = this.arcSelId;
      }
      if (ideaId === '') {
        this.getUIContext().getPromptAction().showToast({ message: '请选择或输入主题名' });
        return;
      }
      const mountId = await ApiClient.brainMount(t, ideaId, imp, this.arcSugImp, this.arcSugTopic);
      t.brain_id = mountId;
      t.importance = imp;
      await ApiClient.saveWatchlistItem(t);
      animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.arcVisible = false; });
      this.syncSheetFlag();
      this.getUIContext().getPromptAction().showToast({ message: '已归档到第二大脑' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '归档失败，请稍后重试' });
    }
  }

  async skipArchive(): Promise<void> {
    const t = this.arcItem;
    t.importance = this.arcImp;
    t.skip_brain = true;
    try {
      await ApiClient.saveWatchlistItem(t);
    } catch (e) {
      // 离线忽略
    }
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.arcVisible = false; });
    this.syncSheetFlag();
    this.getUIContext().getPromptAction().showToast({ message: '已跳过归档' });
  }

  /** 左滑操作区：详情 / 编辑 / 删除（删除走二次确认，§2.13） */
  @Builder
  rowSwipe(t: WatchlistItem) {
    Row() {
      Text('详情')
        .fontSize(FontSize.secondary)
        .fontWeight(Weight.regular)
        .fontColor(this.pal().accent)
        .height('100%')
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.isDark ? 'rgba(94,106,210,0.16)' : 'rgba(0,102,204,0.08)')
        .onClick(() => {
          this.detailItem = t;
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.detailVisible = true; });
          this.syncSheetFlag();
        })
      Text('编辑')
        .fontSize(FontSize.secondary)
        .fontWeight(Weight.regular)
        .fontColor(this.pal().text2)
        .height('100%')
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.pal().chip)
        .onClick(() => {
          this.openEdit(t);
        })
      Text('删除')
        .fontSize(FontSize.secondary)
        .fontWeight(Weight.regular)
        .fontColor(this.isDark ? '#ff6b5e' : '#c0392b')
        .height('100%')
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.isDark ? 'rgba(255,107,94,0.14)' : 'rgba(192,57,43,0.10)')
        .onClick(() => {
          this.editItem = t;
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.delVisible = true; });
          this.syncSheetFlag();
        })
    }
    .height('100%')
  }

  /** 详情弹层：完整综述/概览（列表里只显示 3 行摘录）+ 打开原文 */
  @Builder
  detailSheet() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.detailVisible = false; });
          this.syncSheetFlag();
        })
      Column({ space: Space.s1 }) {
        Text(this.detailItem.title)
          .fontSize(FontSize.panelTitle)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().text)
          .width('100%')
        Row({ space: 8 }) {
          Text(this.detailItem.source)
            .fontSize(FontSize.helper)
            .fontColor(this.pal().text3)
          if (this.detailItem.category !== '') {
            Text(this.detailItem.category)
              .fontSize(FontSize.helper)
              .fontColor(this.pal().text3)
          }
          if (this.detailItem.sourceDate !== '') {
            Text(this.detailItem.sourceDate)
              .fontSize(FontSize.helper)
              .fontColor(this.pal().text3)
          }
          if (this.detailItem.importance !== '') {
            Text(this.detailItem.importance)
              .fontSize(FontSize.helper)
              .fontColor(this.pal().accent)
          }
        }
        .width('100%')

        Scroll() {
          Column({ space: Space.s1 }) {
            if (this.detailItem.summary !== '') {
              Text(this.detailItem.summary)
                .fontSize(FontSize.body)
                .fontWeight(Weight.regular)
                .fontColor(this.pal().text)
                .lineHeight(22)
                .width('100%')
            }
            if (this.detailItem.overview !== '') {
              Text(this.detailItem.overview)
                .fontSize(FontSize.secondary)
                .fontWeight(Weight.regular)
                .fontColor(this.pal().text2)
                .lineHeight(20)
                .width('100%')
            }
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: '56%' })
        .align(Alignment.TopStart)

        Row({ space: Space.s1 }) {
          Button('关闭')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text)
            .backgroundColor(this.pal().chip)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.detailVisible = false; });
              this.syncSheetFlag();
            })
          Button('打开原文')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().accent)
            .backgroundColor(this.isDark ? 'rgba(94,106,210,0.24)' : 'rgba(0,102,204,0.14)')
            .backdropBlur(12)
            .saturate(1.4)
            .borderRadius(Radius.pill)
            .border({ width: 0.5, color: this.isDark ? 'rgba(130,143,255,0.38)' : 'rgba(0,102,204,0.30)' })
            .shadow({ radius: 8, color: 'rgba(0,0,0,0.04)', offsetY: 2 })
            .onClick(() => {
              this.openUrl(this.detailItem);
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(Space.s2)
      .backgroundColor(this.pal().card)
      .borderRadius({ topLeft: Radius.card, topRight: Radius.card })
      .shadow({ radius: 30, color: 'rgba(0,0,0,0.14)', offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.4)')
    .transition(TransitionEffect.translate({ y: 360 }).combine(TransitionEffect.OPACITY))
  }

  private openEdit(t: WatchlistItem): void {
    this.editItem = t;
    this.fTitle = t.title;
    this.fUrl = t.url;
    this.fCategory = t.category;
    this.fImportance = t.importance;
    this.fSummary = t.summary;
    this.fOverview = t.overview;
    this.fSourceDate = t.sourceDate;
    this.fDueDate = t.dueDate;
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.editVisible = true; });
    this.syncSheetFlag();
  }

  /** 同步「有弹层打开」标志 → Index 据此收起 dock（弹层不再被 dock 压住） */
  private syncSheetFlag(): void {
    AppStorage.setOrCreate<boolean>('sheetOpen', this.editVisible || this.delVisible || this.urlVisible || this.arcVisible || this.detailVisible);
  }

  private openUrl(t: WatchlistItem): void {
    if (t.url === '') { return; }
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: t.url
      };
      ctx.startAbility(want);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开链接' });
    }
  }

  async submitCollect(): Promise<void> {
    const u = this.urlInput.trim();
    if (u === '') { return; }
    try {
      const added = await ApiClient.collect(u);
      this.getUIContext().getPromptAction().showToast({ message: added ? '已收藏' : '已存在' });
      animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.urlVisible = false; });
      this.syncSheetFlag();
      this.urlInput = '';
      await this.load();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '收藏失败，请检查网络后重试' });
    }
  }

  async saveEdit(): Promise<void> {
    const t = this.editItem;
    t.title = this.fTitle.trim() !== '' ? this.fTitle.trim() : t.title;
    t.url = this.fUrl.trim();
    t.category = this.fCategory.trim();
    t.importance = this.fImportance;
    t.summary = this.fSummary.trim();
    t.overview = this.fOverview.trim();
    t.sourceDate = this.fSourceDate.trim();
    t.dueDate = this.fDueDate.trim();
    try {
      await ApiClient.saveWatchlistItem(t);
    } catch (e) {
      // 离线忽略，本地已更新
    }
    this.items = this.items.slice();
    WatchlistStore.items = this.items;
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.editVisible = false; });
    this.syncSheetFlag();
  }

  async deleteItem(): Promise<void> {
    const t = this.editItem;
    try {
      await ApiClient.deleteWatchlistItem(t.id);
    } catch (e) {
      // 离线忽略，本地先移除
    }
    this.items = this.items.filter((x: WatchlistItem) => x.id !== t.id);
    WatchlistStore.items = this.items;
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.delVisible = false; });
    this.syncSheetFlag();
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.editVisible = false; });
    this.syncSheetFlag();
    this.getUIContext().getPromptAction().showToast({ message: '已删除' });
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
    if (this.sortMode === 'sourceDate') { return '来源时间'; }
    if (this.sortMode === 'importance') { return '重要性'; }
    if (this.sortMode === 'due') { return '截止时间'; }
    return '加入时间';
  }

  @Builder
  itemRow(t: WatchlistItem) {
    Row() {
      Column({ space: 2 }) {
        // 题目：15/600 文本色，不加下划线；行首不再放箭头（点标题即打开原文，详情走左滑）
        Row({ space: 4 }) {
          Text(t.title)
            .fontSize(FontSize.listTitle)
            .fontWeight(Weight.semibold)
            .fontColor(this.pal().text)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .onClick(() => {
          this.openUrl(t);
        })
        if (t.summary !== '') {
          // 综述：13/400 次级色，行高 18，最多 3 行（读完整综述走左滑「详情」）
          Text(t.summary)
            .fontSize(FontSize.listBody)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text2)
            .lineHeight(18)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Row({ space: 8 }) {
          Text(t.source)
            .fontSize(FontSize.helper)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text3)
          Text(t.importance)
            .fontSize(FontSize.helper)
            .fontWeight(Weight.semibold)
            .fontColor(this.pal().text2)
          if (t.category) {
            Text(t.category)
              .fontSize(FontSize.helper)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text3)
          }
          if (t.dueDate && t.dueDate.length >= 10) {
            Text('计划 ' + t.dueDate.substring(5))
              .fontSize(FontSize.helper)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text3)
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('app.media.edit'))
        .width(16)
        .height(16)
        .fillColor(this.pal().text3)
        .padding(6)
        .onClick(() => {
          this.openEdit(t);
        })
      Toggle({ type: ToggleType.Switch, isOn: t.status === 'watched' })
        .selectedColor(this.pal().accent)
        .onChange((on: boolean) => {
          this.toggleWatched(t, on);
        })
    }
    .width('100%')
    .padding({ left: Space.s2, right: Space.s2, top: 12, bottom: 12 })
    .backgroundColor(this.pal().bg)   // ListItem 默认白底，盖回页面底色
    .opacity(t.status === 'watched' ? 0.6 : 1)
  }

  @Builder
  fieldLabel(txt: string) {
    Text(txt)
      .fontSize(FontSize.secondary)
      .fontWeight(Weight.regular)
      .fontColor(this.pal().text2)
  }

  @Builder
  impChip(code: string, label: string) {
    Text(code + ' ' + label)
      .fontSize(FontSize.secondary)
      .fontWeight(this.fImportance === code ? Weight.semibold : Weight.regular)
      .fontColor(this.fImportance === code ? this.pal().accent : this.pal().text2)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.pal().chip)
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.fImportance = code;
      })
  }

  /**
   * 稍后再看详情（对齐 web watchModal）：
   * 标题 / 原始地址 / 分类 / 重要性(S 核心·A 重要·B 一般·C 稍后) /
   * 概述(一句话) / 综述(详情) / 来源时间 + 计划看完 / 加入时间(只读) / 删除·取消·保存
   */
  @Builder
  editSheet() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.editVisible = false; });
          this.syncSheetFlag();
        })
      Column() {
        Text('稍后再看详情')
          .fontSize(FontSize.panelTitle)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().text)
          .width('100%')
          .padding({ bottom: Space.s1 })

        Scroll() {
          Column({ space: Space.s1 }) {
            this.fieldLabel('标题')
            TextInput({ text: this.fTitle, placeholder: '标题' })
              .fontSize(FontSize.body)
              .fontColor(this.pal().text)
              .placeholderColor(this.pal().text3)
              .backgroundColor(this.pal().card2)
              .borderRadius(Radius.control)
              .height(40)
              .onChange((v: string) => {
                this.fTitle = v;
              })

            this.fieldLabel('原始地址')
            TextInput({ text: this.fUrl, placeholder: 'https://' })
              .fontSize(FontSize.secondary)
              .fontColor(this.pal().text)
              .placeholderColor(this.pal().text3)
              .backgroundColor(this.pal().card2)
              .borderRadius(Radius.control)
              .height(40)
              .onChange((v: string) => {
                this.fUrl = v;
              })

            this.fieldLabel('分类')
            TextInput({ text: this.fCategory, placeholder: '如: 个人成长' })
              .fontSize(FontSize.body)
              .fontColor(this.pal().text)
              .placeholderColor(this.pal().text3)
              .backgroundColor(this.pal().card2)
              .borderRadius(Radius.control)
              .height(40)
              .onChange((v: string) => {
                this.fCategory = v;
              })

            this.fieldLabel('重要性')
            Row({ space: 8 }) {
              this.impChip('S', '核心')
              this.impChip('A', '重要')
              this.impChip('B', '一般')
              this.impChip('C', '稍后')
            }
            .width('100%')

            this.fieldLabel('概述（一句话）')
            TextArea({ text: this.fSummary, placeholder: '一句话概述' })
              .fontSize(FontSize.body)
              .fontColor(this.pal().text)
              .placeholderColor(this.pal().text3)
              .backgroundColor(this.pal().card2)
              .borderRadius(Radius.control)
              .height(64)
              .onChange((v: string) => {
                this.fSummary = v;
              })

            this.fieldLabel('综述（详情）')
            TextArea({ text: this.fOverview, placeholder: '详细综述，可多段' })
              .fontSize(FontSize.body)
              .fontColor(this.pal().text)
              .placeholderColor(this.pal().text3)
              .backgroundColor(this.pal().card2)
              .borderRadius(Radius.control)
              .height(120)
              .onChange((v: string) => {
                this.fOverview = v;
              })

            Row({ space: Space.s1 }) {
              Column({ space: 4 }) {
                this.fieldLabel('来源时间')
                TextInput({ text: this.fSourceDate, placeholder: 'YYYY-MM-DD' })
                  .fontSize(FontSize.body)
                  .fontColor(this.pal().text)
                  .placeholderColor(this.pal().text3)
                  .backgroundColor(this.pal().card2)
                  .borderRadius(Radius.control)
                  .height(40)
                  .onChange((v: string) => {
                    this.fSourceDate = v;
                  })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Column({ space: 4 }) {
                this.fieldLabel('计划看完')
                TextInput({ text: this.fDueDate, placeholder: 'YYYY-MM-DD' })
                  .fontSize(FontSize.body)
                  .fontColor(this.pal().text)
                  .placeholderColor(this.pal().text3)
                  .backgroundColor(this.pal().card2)
                  .borderRadius(Radius.control)
                  .height(40)
                  .onChange((v: string) => {
                    this.fDueDate = v;
                  })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            this.fieldLabel('加入时间')
            Text(this.editItem.addedAt.length >= 10 ? this.editItem.addedAt.substring(0, 10) : this.editItem.addedAt)
              .fontSize(FontSize.secondary)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text3)
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(this.pal().card2)
              .borderRadius(Radius.control)
          }
          .width('100%')
          .padding({ bottom: Space.s1 })
        }
        .width('100%')
        .flexShrink(1)
        .scrollBar(BarState.Off)

        Row({ space: 12 }) {
          Button('删 除')
            .height(TOUCH_TARGET)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor('#ffffff')
            .backgroundColor(this.pal().up)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.delVisible = true; });
              this.syncSheetFlag();
            })
          Blank()
          Button('取消')
            .height(TOUCH_TARGET)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text)
            .backgroundColor(this.pal().card2)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.editVisible = false; });
              this.syncSheetFlag();
            })
          Button('保存')
            .height(TOUCH_TARGET)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor('#ffffff')
            .backgroundColor(this.pal().accent)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              this.saveEdit();
            })
        }
        .width('100%')
        .padding({ top: Space.s1 })
      }
      .width('100%')
      .padding(Space.s2)
      .backgroundColor(this.pal().card)
      .borderRadius({ topLeft: Radius.card, topRight: Radius.card })
      .shadow({ radius: 30, color: 'rgba(0,0,0,0.14)', offsetY: 10 })
      .constraintSize({ maxHeight: '86%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.4)')
    .transition(TransitionEffect.translate({ y: 360 }).combine(TransitionEffect.OPACITY))
  }

  @Builder
  delSheet() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.delVisible = false; });
          this.syncSheetFlag();
        })
      Column({ space: Space.s2 }) {
        Text('删除该条目？')
          .fontSize(FontSize.panelTitle)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().text)
        Text(this.editItem.title)
          .fontSize(FontSize.body)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text2)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 12 }) {
          Button('取消')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text)
            .backgroundColor(this.pal().card2)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.delVisible = false; });
              this.syncSheetFlag();
            })
          Button('删除')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor('#ffffff')
            .backgroundColor(this.pal().up)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              this.deleteItem();
            })
        }
      }
      .width('100%')
      .padding(Space.s2)
      .backgroundColor(this.pal().card)
      .borderRadius({ topLeft: Radius.card, topRight: Radius.card })
      .shadow({ radius: 30, color: 'rgba(0,0,0,0.14)', offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.4)')
    .transition(TransitionEffect.translate({ y: 360 }).combine(TransitionEffect.OPACITY))
  }

  @Builder
  urlSheet() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.urlVisible = false; });
          this.syncSheetFlag();
        })
      Column({ space: Space.s2 }) {
        Text('添加链接')
          .fontSize(FontSize.panelTitle)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().text)
        TextInput({ text: this.urlInput, placeholder: '粘贴网址（网页 / B站等）' })
          .fontSize(FontSize.body)
          .fontColor(this.pal().text)
          .placeholderColor(this.pal().text3)
          .backgroundColor(this.pal().card2)
          .borderRadius(Radius.control)
          .height(40)
          .onChange((v: string) => {
            this.urlInput = v;
          })
        Row({ space: 12 }) {
          Button('取消')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text)
            .backgroundColor(this.pal().card2)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.urlVisible = false; });
              this.syncSheetFlag();
            })
          Button('收藏')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor('#ffffff')
            .backgroundColor(this.pal().accent)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              this.submitCollect();
            })
        }
      }
      .width('100%')
      .padding(Space.s2)
      .backgroundColor(this.pal().card)
      .borderRadius({ topLeft: Radius.card, topRight: Radius.card })
      .shadow({ radius: 30, color: 'rgba(0,0,0,0.14)', offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.4)')
    .transition(TransitionEffect.translate({ y: 360 }).combine(TransitionEffect.OPACITY))
  }

  @Builder
  archiveSheet() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.arcVisible = false; });
          this.syncSheetFlag();
        })
      Column({ space: Space.s2 }) {
        Text('已看完 · 归档到第二大脑？')
          .fontSize(FontSize.panelTitle)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().text)
        Text(this.arcItem.title)
          .fontSize(FontSize.body)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text2)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          Text('重要级')
            .fontSize(FontSize.secondary)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text2)
          ForEach(['S', 'A', 'B', 'C'], (p: string) => {
            Text(p)
              .fontSize(FontSize.body)
              .fontWeight(this.arcImp === p ? Weight.semibold : Weight.regular)
              .fontColor(this.arcImp === p ? this.pal().accent : this.pal().text)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .backgroundColor(this.pal().chip)
              .borderRadius(Radius.pill)
              .onClick(() => {
                this.arcImp = p;
              })
          }, (p: string) => p)
          if (this.arcSugImp !== '') {
            Text('AI 建议 ' + this.arcSugImp)
              .fontSize(FontSize.helper)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text2)
              .backgroundColor(this.pal().chip)
              .borderRadius(Radius.pill)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          }
        }

        ForEach(this.arcCands, (c: BrainCandidate) => {
          Row({ space: 6 }) {
            Text(c.title)
              .fontSize(FontSize.body)
              .fontWeight(this.arcSelId === c.id ? Weight.semibold : Weight.regular)
              .fontColor(this.pal().text)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (c.id === this.arcRec) {
              Text('推荐')
                .fontSize(FontSize.helper)
                .fontWeight(Weight.regular)
                .fontColor(this.pal().text2)
                .backgroundColor(this.pal().chip)
                .borderRadius(Radius.pill)
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            }
            if (c.reason !== '') {
              Text(c.reason)
                .fontSize(FontSize.helper)
                .fontWeight(Weight.regular)
                .fontColor(this.pal().text3)
            }
          }
          .width('100%')
          .padding(10)
          .borderRadius(Radius.secondary)
          .border({ width: 1, color: this.arcSelId === c.id ? this.pal().accent : this.pal().border })
          .backgroundColor(this.arcSelId === c.id ? this.pal().chip : 'transparent')
          .onClick(() => {
            this.arcSelId = c.id;
            this.arcInput = '';
          })
        }, (c: BrainCandidate) => c.id)

        TextInput({ text: this.arcInput, placeholder: '输入主题名，不存在自动创建' })
          .fontSize(FontSize.body)
          .fontColor(this.pal().text)
          .placeholderColor(this.pal().text3)
          .backgroundColor(this.pal().card2)
          .borderRadius(Radius.control)
          .height(40)
          .onChange((v: string) => {
            this.arcInput = v;
          })

        Row({ space: 12 }) {
          Button('跳过')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text)
            .backgroundColor(this.pal().card2)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              this.skipArchive();
            })
          Button('确认挂载')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor('#ffffff')
            .backgroundColor(this.pal().accent)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              this.confirmArchive();
            })
        }
      }
      .width('100%')
      .padding(Space.s2)
      .backgroundColor(this.pal().card)
      .borderRadius({ topLeft: Radius.card, topRight: Radius.card })
      .shadow({ radius: 30, color: 'rgba(0,0,0,0.14)', offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.4)')
    .transition(TransitionEffect.translate({ y: 360 }).combine(TransitionEffect.OPACITY))
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Row({ space: 6 }) {
          // 左侧：显示已完成 | 排序（靠左）
          Row({ space: 8 }) {
            Text('显示已完成')
              .fontSize(FontSize.secondary)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text2)
            Toggle({ type: ToggleType.Switch, isOn: this.showWatched })
              .selectedColor(this.pal().accent)
              .onChange((on: boolean) => {
                AppStorage.setOrCreate<boolean>('showWatched', on);
              })
          }
          // 排序下拉（与「显示已完成」「添加链接」紧凑聚拢在右侧）
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
          Blank()
          Button('添加链接')
            .height(32)
            .padding({ left: 14, right: 14 })
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
              animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.urlVisible = true; });
              this.syncSheetFlag();
            })
        }
        .width('100%')
        .padding({ left: Space.s2, right: Space.s2, top: Space.s1 })

        if (this.categories.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              Text('全部')
                .fontSize(FontSize.secondary)
                .fontWeight(Weight.regular)
                .fontColor(this.activeCat === '全部' ? this.pal().accent : this.pal().text2)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.activeCat === '全部' ? this.pal().chip : 'transparent')
                .borderRadius(Radius.pill)
                .onClick(() => {
                  this.activeCat = '全部';
                })
              ForEach(this.categories, (c: string) => {
                Text(c)
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.activeCat === c ? this.pal().accent : this.pal().text2)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.activeCat === c ? this.pal().chip : 'transparent')
                  .borderRadius(Radius.pill)
                  .onClick(() => {
                    this.activeCat = c;
                  })
              }, (c: string) => c)
            }
            .padding({ left: Space.s2, right: Space.s2, top: 4, bottom: 4 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }

        if (this.visible().length === 0) {
          // C2 空态=引导：插画 + 一句价值 + 主 CTA（对齐空态原则）
          Column({ space: Space.s1 }) {
            Image($r('app.media.clock'))
              .width(28)
              .height(28)
              .fillColor(this.pal().text3)
            Text(this.loadText === '' ? '还没有稍后再看的条目' : this.loadText)
              .fontSize(FontSize.listTitle)
              .fontWeight(Weight.semibold)
              .fontColor(this.pal().text)
            Text('链接丢进来，稍后慢慢看')
              .fontSize(FontSize.secondary)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text3)
            Button('添加链接')
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
                animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.urlVisible = true; });
                this.syncSheetFlag();
              })
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else {
          List() {
            ForEach(this.visible(), (t: WatchlistItem) => {
              ListItem() {
                this.itemRow(t)
              }
              .swipeAction({ end: this.rowSwipe(t) })
            }, (t: WatchlistItem) => t.id)
          }
          .layoutWeight(1)
          .width('100%')
          .divider({ strokeWidth: 0.5, color: this.pal().border })
          .padding({ bottom: 8 })   // 只留极小呼吸位（同行列表页）
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
          this.sortOpt('added', '加入时间')
          this.sortOpt('sourceDate', '来源时间')
          this.sortOpt('importance', '重要性')
          this.sortOpt('due', '截止时间')
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

      if (this.editVisible) {
        this.editSheet()
      }

      if (this.urlVisible) {
        this.urlSheet()
      }

      if (this.arcVisible) {
        this.archiveSheet()
      }

      if (this.delVisible) {
        this.delSheet()
      }

      if (this.detailVisible) {
        this.detailSheet()
      }
    }
    .width('100%')
    .height('100%')
  }
}
