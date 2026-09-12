import { DARK_MODE_KEY, FontSize, Palette, Radius, Space, Weight, palette } from '../common/Theme';
import { TaskListView } from './TaskListView';
import { CalendarView } from './CalendarView';
import { WatchlistPage } from './WatchlistPage';
import { TasksPage } from './TasksPage';
import { TaskEditSheet } from './TaskEditSheet';
import { SettingsPage } from './SettingsPage';
import { SyncEngine } from '../common/SyncEngine';
import { Store } from '../common/Storage';
import { Task, WatchlistStore, CatNode, isAITask, isToConfirm } from '../common/Models';
import { ApiClient } from '../common/ApiClient';
import { SystemBars } from '../common/SystemBars';
import { common } from '@kit.AbilityKit';

/**
 * 主入口（批 1 骨架对齐 web 移动端）：
 * 顶栏（logo + 搜索 pill + 命令 + 添加）+ 分段导航（列表/日历/稍后再看/时间线）
 * + 侧边玻璃抽屉（智能列表+分类+主题切换）+ 底部玻璃 dock（视图+徽标）+ 设置视图。
 * 布局/主题照 design.md；字重 300/400/600。
 */
@Entry
@Component
struct Index {
  @StorageProp('darkMode') isDark: boolean = false;
  @StorageProp('sheetOpen') sheetOpen: boolean = false;   // 子页弹层打开时收起 dock
  @State currentView: string = 'list';
  @State sidebarOpen: boolean = false;
  @State tasks: Task[] = [];
  // 筛选状态（传给列表/时间线视图）
  @State searchText: string = '';
  @State smartFilter: string = 'today';   // 默认进「今天」（与 web 一致）
  @State filterCategory: string = '';
  @StorageProp('showWatched') showWatched: boolean = false;
  @State catsExpanded: boolean = true;
  @State smartFoldOpen: boolean = false;
  @State quickText: string = '';
  @State searchOpen: boolean = false;   // Apple Music 式：dock 右端搜索钮点开 → dock 叠起换成搜索条
  // 共享任务编辑弹层（任意视图弹出，不跳时间线）
  @State taskEditVisible: boolean = false;
  @State taskEditId: string = '';
  // 保存后刷新子视图（列表/日历各自依赖注册）
  @State listRefreshKey: number = 0;
  @State calRefreshKey: number = 0;
  @State collapsedCats: string[] = [];   // 折叠的分类全路径（E3 树形）
  @State catsInited: boolean = false;

  private pal(): Palette {
    return palette(this.isDark);
  }

  private buttonRadius(): number {
    return this.isDark ? Radius.control : Radius.pill;
  }

  aboutToAppear(): void {
    if (AppStorage.get<boolean>(DARK_MODE_KEY) === undefined) {
      AppStorage.setOrCreate<boolean>(DARK_MODE_KEY, false);
    }
    // 系统栏跟随当前主题（消除底部系统导航栏白带）
    SystemBars.apply(getContext(this) as common.Context, this.isDark);
    // 通知/卡片深链：有待打开任务或新建请求 → 任意当前视图直接弹层（不跳时间线）
    const pending = AppStorage.get<string>('pendingTaskId');
    const pnew = AppStorage.get<string>('pendingNew');
    if (pnew !== undefined && pnew !== '') {
      AppStorage.setOrCreate<string>('pendingNew', '');
      this.openTaskEdit('');
    } else if (pending !== undefined && pending !== '') {
      AppStorage.setOrCreate<string>('pendingTaskId', '');
      this.openTaskEdit(pending);
    }
    this.loadCounts();
  }

  // 顶栏标题：列表=当前智能列表/分类名，其余=视图名
  private smartLabel(s: string): string {
    if (s === 'today') { return '今天'; }
    if (s === 'high') { return '高优先级'; }
    if (s === 'overdue') { return '已过期'; }
    if (s === 'done') { return '已完成'; }
    if (s === 'recur-daily') { return '日重复'; }
    if (s === 'recur-weekly') { return '周重复'; }
    if (s === 'recur-monthly') { return '月重复'; }
    if (s === 'ai') { return 'AI 任务'; }
    if (s === 'toconfirm') { return 'ToConfirm'; }
    return '全部任务';
  }

  private viewTitle(): string {
    if (this.currentView === 'calendar') { return '日历'; }
    if (this.currentView === 'timeline') { return '时间线'; }
    if (this.currentView === 'watchlist') { return '稍后再看'; }
    if (this.currentView === 'settings') { return '设置'; }
    if (this.filterCategory !== '') { return this.filterCategory; }
    return this.smartLabel(this.smartFilter);
  }

  private openTaskEdit(taskId: string): void {
    this.taskEditId = taskId;
    this.taskEditVisible = true;
  }

  private onTaskSaved(): void {
    // 列表/日历数据来自各自 @State，保存后 bump 刷新键
    this.listRefreshKey = this.listRefreshKey + 1;
    this.calRefreshKey = this.calRefreshKey + 1;
    this.tasks = SyncEngine.tasks.slice();
  }

  async loadCounts(): Promise<void> {
    try {
      await Store.init(getContext(this) as common.Context);
      await SyncEngine.fullPull();
      this.tasks = SyncEngine.tasks;
      if (!this.catsInited) {
        // 默认折叠所有有子级的父分类（对齐 web catsInit）
        const counts = this.catCounts();
        const parents: string[] = [];
        counts.forEach((v: number, key: string) => {
          counts.forEach((v2: number, key2: string) => {
            if (key2.indexOf(key + '/') === 0 && parents.indexOf(key) < 0) { parents.push(key); }
          });
        });
        this.collapsedCats = parents;
        this.catsInited = true;
      }
    } catch (e) {
      this.tasks = [];
    }
  }

  private todayCount(): number {
    const d = new Date();
    const m = ('0' + (d.getMonth() + 1)).slice(-2);
    const day = ('0' + d.getDate()).slice(-2);
    const today = d.getFullYear() + '-' + m + '-' + day;
    let n = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].dueDate === today && this.tasks[i].status !== 'completed') { n++; }
    }
    return n;
  }

  private pendingCount(): number {
    let n = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].status === 'pending') { n++; }
    }
    return n;
  }

  private doneCount(): number {
    let n = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].status === 'completed') { n++; }
    }
    return n;
  }
  private aiCount(): number {
    let n = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      if (isAITask(this.tasks[i]) && this.tasks[i].status !== 'completed') { n++; }
    }
    return n;
  }

  private toconfirmCount(): number {
    let n = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      if (isToConfirm(this.tasks[i])) { n++; }
    }
    return n;
  }

  // v13 对齐：稍后再看徽标与「显示已完成」开关联动（开=全部数、关=未看完数）
  private wlBadgeCount(): number {
    if (this.showWatched) { return WatchlistStore.items.length; }
    let n = 0;
    for (let i = 0; i < WatchlistStore.items.length; i++) {
      if (WatchlistStore.items[i].status !== 'watched') { n++; }
    }
    return n;
  }

  private highCount(): number {
    let n = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].priority === 'high' && this.tasks[i].status !== 'completed') { n++; }
    }
    return n;
  }

  private overdueCount(): number {
    const today = this.todayStrDate();
    let n = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      const t = this.tasks[i];
      if (t.dueDate !== '' && t.dueDate < today && t.status !== 'completed') { n++; }
    }
    return n;
  }

  private recurCount(type: string): number {
    let n = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      const r = this.tasks[i].recurrence;
      if (r !== null && r.type === type) { n++; }
    }
    return n;
  }

  // E3 分类树（对齐 web renderCats）：pending 任务按 '/' 拆层，父级累计子级
  private catCounts(): Map<string, number> {
    const counts = new Map<string, number>();
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].status !== 'pending') { continue; }
      const cat = this.tasks[i].category === '' ? '未分类' : this.tasks[i].category;
      const parts = cat.split('/');
      let prefix = '';
      for (let j = 0; j < parts.length; j++) {
        const p = parts[j].trim();
        if (p === '') { continue; }
        prefix = prefix === '' ? p : prefix + '/' + p;
        counts.set(prefix, (counts.get(prefix) || 0) + 1);
      }
    }
    return counts;
  }

  private catTree(): CatNode[] {
    const counts = this.catCounts();
    const out: CatNode[] = [];
    const walk = (prefix: string, depth: number): void => {
      const kids: string[] = [];
      counts.forEach((v: number, key: string) => {
        const parent = key.indexOf('/') < 0 ? '' : key.substring(0, key.lastIndexOf('/'));
        if (parent === prefix) { kids.push(key); }
      });
      kids.sort((a: string, b: string) => {
        if (a === '未分类') { return 1; }
        if (b === '未分类') { return -1; }
        return a.localeCompare(b);
      });
      for (let k = 0; k < kids.length; k++) {
        const full = kids[k];
        const n = new CatNode();
        n.name = full.substring(prefix === '' ? 0 : prefix.length + 1);
        n.full = full;
        n.depth = depth;
        n.count = counts.get(full) || 0;
        let hasKids = false;
        counts.forEach((v2: number, key2: string) => {
          if (key2.indexOf(full + '/') === 0) { hasKids = true; }
        });
        n.hasKids = hasKids;
        out.push(n);
        if (hasKids && this.collapsedCats.indexOf(full) < 0) {
          walk(full, depth + 1);
        }
      }
    };
    walk('', 0);
    return out;
  }

  private toggleCat(full: string): void {
    const i = this.collapsedCats.indexOf(full);
    if (i >= 0) { this.collapsedCats.splice(i, 1); }
    else { this.collapsedCats.push(full); }
    this.collapsedCats = this.collapsedCats.slice();
  }

  private todayStrDate(): string {
    const d = new Date();
    const m = ('0' + (d.getMonth() + 1)).slice(-2);
    const day = ('0' + d.getDate()).slice(-2);
    return d.getFullYear() + '-' + m + '-' + day;
  }

  // 快速记录：贴链接→稍后再看 · 一句话→任务（对齐 web quickCapture）
  private async submitQuick(): Promise<void> {
    const v = this.quickText.trim();
    if (v === '') { return; }
    try {
      if (v.startsWith('http')) {
        const added = await ApiClient.collect(v);
        this.getUIContext().getPromptAction().showToast({ message: added ? '已收藏到稍后再看' : '已存在' });
      } else {
        await Store.init(getContext(this) as common.Context);
        const deviceId = await Store.getDeviceId();
        const t = new Task();
        t.id = 'task_' + Date.now().toString(36) + '_' + Math.floor(Math.random() * 0xffff).toString(36);
        t.title = v;
        t.status = 'pending';
        t.priority = '';
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
        this.getUIContext().getPromptAction().showToast({ message: '已记录任务' });
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '网络不可用，已存本地稍后同步' });
    }
    this.quickText = '';
    this.loadCounts();
  }

  @Builder
  topbar() {
    Stack({ alignContent: Alignment.Center }) {
      // 左：汉堡；右：搜索/命令 + 新建任务（标题叠在中间，保证真居中）
      Row({ space: 8 }) {
        Image($r('app.media.menu'))
          .width(40)
          .height(40)
          .padding(12)
          .fillColor(this.pal().text2)
          .glassSquare()
          .onClick(() => {
            this.openSidebar();
          })
        Blank()
        Button('+ 新建任务')
        .height(32)
        .padding({ left: 14, right: 14 })
        .fontSize(FontSize.secondary)
        .fontWeight(Weight.semibold)
        .fontColor(this.pal().accent)
        .accentGlass()
        .onClick(() => {
          // 任意当前视图直接弹新建层（不跳时间线）
          this.openTaskEdit('');
        })
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)
      .padding({ left: Space.s2, right: Space.s2 })

      // 居中标题：列表=当前智能列表/分类名；日历/时间线/稍后再看/设置=对应视图名
      // marginTop 微调视觉重心，使标题、汉堡、新建任务三者竖向中心一致
      Text(this.viewTitle())
        .fontSize(FontSize.pageTitle)
        .fontWeight(Weight.semibold)
        .fontColor(this.pal().text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
    }
    .width('100%')
    .height(48)
  }

  /**
   * 液态玻璃胶囊材质：**不用 backdropBlur**（ArkUI 会额外合成一层背板 → 视觉上是「白块/附加层」），
   * 改用页面同色系真半透明 tint（45%）+ 高光描边 + 极软阴影：内容直接透出，无附加层感。
   */
  /** accent 玻璃（主按钮玻璃化：同玻璃材质 + accent 淡底/描边/文字，保留「主操作」识别） */
  @Styles
  accentGlass() {
    .backgroundColor(this.isDark ? 'rgba(94,106,210,0.24)' : 'rgba(0,102,204,0.14)')
    .backdropBlur(12)
    .saturate(1.4)
    .borderRadius(Radius.pill)
    .border({ width: 0.5, color: this.isDark ? 'rgba(130,143,255,0.38)' : 'rgba(0,102,204,0.30)' })
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.04)', offsetY: 2 })
  }

  /** 玻璃圆角方形（顶部图标钮用，与 pill 同材质、方圆角区分层级） */
  @Styles
  glassSquare() {
    .backgroundColor(this.isDark ? 'rgba(20,21,23,0.34)' : 'rgba(240,240,243,0.28)')
    .backdropBlur(12)
    .saturate(1.4)
    .borderRadius(Radius.card)
    .border({ width: 0.5, color: this.isDark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)' })
    .shadow({ radius: 10, color: 'rgba(0,0,0,0.05)', offsetY: 2 })
  }

  @Styles
  glassPill() {
    // tint 28%（页面同色系，无白盖板）+ 适度背景模糊（frosted，12px）+ 中性描边 + 极软影
    .backgroundColor(this.isDark ? 'rgba(20,21,23,0.34)' : 'rgba(240,240,243,0.28)')
    .backdropBlur(12)
    .saturate(1.4)
    .borderRadius(Radius.pill)
    .border({ width: 0.5, color: this.isDark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)' })
    .shadow({ radius: 10, color: 'rgba(0,0,0,0.05)', offsetY: 2 })
  }

  /**
   * 搜索条（点开状态：dock 叠起后的液态玻璃搜索胶囊）。
   * 占位符带范围 = 搜索任务；右侧 ✕ 清空并收回 dock。
   */
  @Builder
  searchBar() {
    Row({ space: 6 }) {
      Image($r('app.media.search'))
        .width(15)
        .height(15)
        .fillColor(this.pal().text3)
      TextInput({ text: this.searchText, placeholder: '搜索任务' })
        .fontSize(FontSize.secondary)
        .fontColor(this.pal().text)
        .placeholderColor(this.pal().text3)
        .backgroundColor('transparent')
        .layoutWeight(1)
        .height(50)
        .onChange((v: string) => {
          this.searchText = v;
        })
      Image($r('app.media.x'))
        .width(14)
        .height(14)
        .fillColor(this.pal().text3)
        .padding(2)
        .onClick(() => {
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
            this.searchText = '';
            this.searchOpen = false;
          })
        })
    }
    .layoutWeight(1)
    .height(58)
    .padding({ left: 14, right: 14 })
    .glassPill()
    .geometryTransition('searchMorph')   // 由搜索圆钮形变延伸而来（非淡入）
  }

  @Builder
  dockItem(key: string, icon: Resource, label: string, badge: number) {
    Column({ space: 3 }) {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(this.currentView === key ? this.pal().accent : this.pal().text2)
      Row() {
        Text(label)
          .fontSize(FontSize.helper)
          .fontWeight(this.currentView === key ? Weight.semibold : Weight.regular)
          .fontColor(this.currentView === key ? this.pal().accent : this.pal().text2)
        if (badge > 0) {
          Text('' + badge)
            .fontSize(FontSize.helper)
            .fontWeight(Weight.semibold)
            .fontColor(this.pal().text)
            .backgroundColor(this.pal().chip)
            .borderRadius(Radius.pill)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        }
      }
      if (this.currentView === key) {
        Circle({ width: 4, height: 4 })
          .fill(this.pal().accent)
      }
    }
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    .borderRadius(Radius.secondary)
    .onClick(() => {
      this.currentView = key;
    })
  }

  /** dock 主胶囊：拉伸近整行，四项均匀分布（对齐 Apple Music / 原型 v3） */
  @Builder
  dock() {
    Row() {
      this.dockItem('list', $r('app.media.list'), '列表', 0)
      this.dockItem('calendar', $r('app.media.calendar'), '日历', 0)
      this.dockItem('timeline', $r('app.media.activity'), '时间线', this.pendingCount())
      this.dockItem('watchlist', $r('app.media.clock'), '稍后', this.wlBadgeCount())
    }
    .layoutWeight(1)
    .height(58)
    .justifyContent(FlexAlign.SpaceEvenly)
    .glassPill()
    .geometryTransition('dockMorph')   // 收缩成左侧单一图标
  }

  // 堆叠小圆钮的图标 = 当前视图图标
  private curViewIcon(): Resource {
    if (this.currentView === 'calendar') { return $r('app.media.calendar'); }
    if (this.currentView === 'timeline') { return $r('app.media.activity'); }
    if (this.currentView === 'watchlist') { return $r('app.media.clock'); }
    if (this.currentView === 'settings') { return $r('app.media.menu'); }
    return $r('app.media.list');
  }

  /** 模块化分组卡（Obsidian 设置页式：白卡 + 圆角16，行内 hairline 分隔） */
  @Styles
  sideCard() {
    .backgroundColor(this.pal().card)
    .borderRadius(Radius.card)
    .padding({ top: 2, bottom: 2 })
    .margin({ left: 10, right: 10, top: 2 })
  }

  @Builder
  hairline() {
    Row()
      .height(0.5)
      .width('100%')
      .backgroundColor(this.pal().border)
      .margin({ left: 34 })
  }

  @Builder
  groupLabel(txt: string) {
    Text(txt)
      .fontSize(FontSize.groupLabel)
      .fontWeight(Weight.semibold)
      .fontColor(this.pal().text3)
      .width('100%')
      .padding({ left: 16, right: 12, top: 12, bottom: 4 })
  }

  @Builder
  sidebarItem(label: string, badge: number, action: string, smart: string) {
    Row() {
      Text(label)
        .fontSize(FontSize.listBody)
        .fontWeight(this.smartFilter === smart && this.filterCategory === '' ? Weight.semibold : Weight.regular)
        .fontColor(this.smartFilter === smart && this.filterCategory === '' ? this.pal().accent : this.pal().text2)
      Blank()
      Text('' + badge)
        .fontSize(FontSize.secondary)
        .fontWeight(Weight.regular)
        .fontColor(this.pal().text3)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 11, bottom: 11 })
    .onClick(() => {
      this.currentView = action;
      this.smartFilter = smart;
      this.filterCategory = '';
      this.closeSidebar();
    })
  }

  /** 带矢量图标的侧栏项（卡内行：15px 图标 + 13px 标签 + 右侧计数/hint；选中 = accent） */
  @Builder
  sidebarIconItem(icon: Resource, label: string, badge: number, action: string, smart: string, hint: string) {
    Row({ space: 9 }) {
      Image(icon)
        .width(15)
        .height(15)
        .fillColor(this.smartFilter === smart && this.filterCategory === '' ? this.pal().accent : this.pal().text3)
      Text(label)
        .fontSize(FontSize.listBody)
        .fontWeight(this.smartFilter === smart && this.filterCategory === '' ? Weight.semibold : Weight.regular)
        .fontColor(this.smartFilter === smart && this.filterCategory === '' ? this.pal().accent : this.pal().text2)
      Blank()
      if (hint !== '') {
        Text(hint)
          .fontSize(FontSize.helper)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text3)
      } else {
        Text('' + badge)
          .fontSize(FontSize.secondary)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text3)
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 11, bottom: 11 })
    .onClick(() => {
      this.currentView = action;
      this.smartFilter = smart;
      this.filterCategory = '';
      this.closeSidebar();
    })
  }

  @Builder
  sidebar() {
    Column() {
      Row() {
        Text('AlwaysToDo')
          .fontSize(FontSize.listTitle)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().text)
          .fontFamily('serif')
        Blank()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })

      // 中部可滚动区（模块化分组卡：智能列表 / AI 任务 / 分类）
      Scroll() {
        Column() {
          this.groupLabel('智能列表')
          Column() {
            this.sidebarIconItem($r('app.media.sun'), '今天', this.todayCount(), 'list', 'today', '')
            this.hairline()
            this.sidebarIconItem($r('app.media.star'), '高优先级', this.highCount(), 'list', 'high', '')
            this.hairline()
            this.sidebarIconItem($r('app.media.clock'), '已过期', this.overdueCount(), 'list', 'overdue', '')
            this.hairline()
            this.sidebarIconItem($r('app.media.list'), '全部任务', this.pendingCount(), 'list', 'all', '')
            this.hairline()
            Row({ space: 9 }) {
              Image($r('app.media.chevron_down'))
                .width(14)
                .height(14)
                .fillColor(this.pal().text3)
                .rotate({ angle: this.smartFoldOpen ? 0 : -90 })
              Text('更多智能列表')
                .fontSize(FontSize.secondary)
                .fontWeight(Weight.regular)
                .fontColor(this.pal().text3)
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 11, bottom: 11 })
            .onClick(() => {
              this.smartFoldOpen = !this.smartFoldOpen;
            })
            if (this.smartFoldOpen) {
              this.hairline()
              this.sidebarIconItem($r('app.media.repeat'), '日重复', this.recurCount('daily'), 'list', 'recur-daily', '')
              this.hairline()
              this.sidebarIconItem($r('app.media.repeat'), '周重复', this.recurCount('weekly'), 'list', 'recur-weekly', '')
              this.hairline()
              this.sidebarIconItem($r('app.media.repeat'), '月重复', this.recurCount('monthly'), 'list', 'recur-monthly', '')
              this.hairline()
              this.sidebarIconItem($r('app.media.check'), '已完成', this.doneCount(), 'list', 'done', '')
            }
          }
          .sideCard()

          this.groupLabel('AI 任务')
          Column() {
            this.sidebarIconItem($r('app.media.cpu'), 'AI 任务', this.aiCount(), 'list', 'ai', '')
            this.hairline()
            this.sidebarIconItem($r('app.media.clock'), 'ToConfirm', this.toconfirmCount(), 'list', 'toconfirm', '新建任务可选 AI')
          }
          .sideCard()

          Row() {
            Text('分类')
              .fontSize(FontSize.groupLabel)
              .fontWeight(Weight.semibold)
              .fontColor(this.pal().text3)
            Blank()
            Text(this.catsExpanded ? '全部收起' : '展开')
              .fontSize(FontSize.helper)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text3)
              .onClick(() => {
                this.catsExpanded = !this.catsExpanded;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 12, top: 12, bottom: 4 })
          if (this.catsExpanded) {
            Column() {
              ForEach(this.catTree(), (n: CatNode, i: number) => {
                Column() {
                  if (i > 0) {
                    this.hairline()
                  }
                  Row() {
                    Row() {
                      if (n.hasKids) {
                        Image($r('app.media.chevron_down'))
                          .width(12)
                          .height(12)
                          .fillColor(this.pal().text3)
                          .rotate({ angle: this.collapsedCats.indexOf(n.full) < 0 ? 0 : -90 })
                      }
                    }
                    .width(16)
                    .height(20)
                    .onClick(() => {
                      if (n.hasKids) { this.toggleCat(n.full); }
                    })
                    Row() {
                      Text(n.name)
                        .fontSize(FontSize.listBody)
                        .fontWeight(this.filterCategory === n.full ? Weight.semibold : Weight.regular)
                        .fontColor(this.filterCategory === n.full ? this.pal().accent : this.pal().text2)
                      Blank()
                      Text('' + n.count)
                        .fontSize(FontSize.secondary)
                        .fontWeight(Weight.regular)
                        .fontColor(this.pal().text3)
                    }
                    .layoutWeight(1)
                    .padding({ top: 11, bottom: 11 })
                    .onClick(() => {
                      this.currentView = 'list';
                      this.filterCategory = n.full;
              this.smartFilter = 'all';   // 点分类 = 看该分类的全部任务（不再叠加「今天」等智能筛选）
              this.searchText = '';
                      this.closeSidebar();
                    })
                  }
                  .width('100%')
                  .padding({ left: 10 + n.depth * 14, right: 10 })
                }
                .width('100%')
              }, (n: CatNode) => n.full)
            }
            .sideCard()
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // 快速记录：贴链接→稍后再看 · 一句话→任务（箭头内嵌输入框，占整行）
      Row({ space: 6 }) {
        TextInput({ text: this.quickText, placeholder: '+ 快速记录…' })
          .fontSize(FontSize.secondary)
          .fontColor(this.pal().text)
          .placeholderColor(this.pal().text3)
          .backgroundColor('transparent')
          .layoutWeight(1)
          .height(34)
          .onChange((v: string) => {
            this.quickText = v;
          })
          .onSubmit(() => {
            this.submitQuick();
          })
        Image($r('app.media.arrow_right'))
          .width(16)
          .height(16)
          .fillColor(this.pal().text3)
          .padding(2)
          .onClick(() => {
            this.submitQuick();
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.pal().card2)
      .borderRadius(Radius.control)
      .margin({ left: 10, right: 10, top: 8 })

      // 主题图标钮（浅色显太阳/深色显月亮；整行点按切换，只走一次 onClick）
      Row() {
        if (this.isDark) {
          Image($r('app.media.moon'))
            .width(20)
            .height(20)
            .fillColor(this.pal().text)
        } else {
          Image($r('app.media.sun'))
            .width(20)
            .height(20)
            .fillColor(this.pal().text2)
        }
      }
      .width('100%')
      .height(44)
      .padding({ left: 20, right: 12 })
      .onClick(() => {
        const next = !this.isDark;
        AppStorage.setOrCreate<boolean>('darkMode', next);
        SystemBars.apply(getContext(this) as common.Context, next);
      })
    }
    .width(280)
    .height('100%')
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.isDark ? 'rgba(15,16,17,0.72)' : 'rgba(245,245,247,0.72)')
    .backdropBlur(20)
    .saturate(1.8)
    .align(Alignment.TopStart)
    .transition(TransitionEffect.translate({ x: -280 }).combine(TransitionEffect.OPACITY))
  }

  @Builder
  content() {
    if (this.currentView === 'calendar') {
      CalendarView({ refreshKey: this.calRefreshKey })
    } else if (this.currentView === 'watchlist') {
      WatchlistPage()
    } else if (this.currentView === 'timeline') {
      TasksPage({ query: this.searchText, category: this.filterCategory, smart: this.smartFilter })
    } else if (this.currentView === 'settings') {
      SettingsPage()
    } else {
      TaskListView({
        query: this.searchText,
        category: this.filterCategory,
        smart: this.smartFilter,
        refreshKey: this.listRefreshKey,
        goNew: () => {
          this.openTaskEdit('');
        },
        goEdit: (id: string) => {
          this.openTaskEdit(id);
        }
      })
    }
  }

  // E1 统一缓动：抽屉/弹层 250ms EaseOut
  private openSidebar(): void {
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.sidebarOpen = true; });
  }

  private closeSidebar(): void {
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.sidebarOpen = false; });
  }


  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.topbar()
        Column() {
          this.content()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().bg)
      // 页面底色扩展绘制进底部系统区（消除 dock 下方那条系统导航栏纯白带）
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      // 悬浮底栏：**直接作为 Stack 子节点**（不再用全屏 Column 包裹——全屏层会吃掉列表的滚动手势）
      // 默认 = dock 主胶囊（拉伸均布）+ 独立搜索圆钮；点开 = dock 叠成小圆钮 + 搜索条展开
      if (!this.sheetOpen && !this.taskEditVisible) {
      Row({ space: 10 }) {
        if (!this.searchOpen) {
          this.dock()
          Image($r('app.media.search'))
            .width(58)
            .height(58)
            .padding(19)
            .fillColor(this.pal().text2)
            .glassPill()
            .geometryTransition('searchMorph')   // 展开成搜索条
            .onClick(() => {
              animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
                this.searchOpen = true;
              })
            })
        } else {
          // 左侧单一图标钮（由 dock 胶囊收缩形变而来；if/else 显式渲染，避免三元资源为空）
          if (this.currentView === 'calendar') {
            Image($r('app.media.calendar'))
              .width(58)
              .height(58)
              .padding(19)
              .fillColor(this.pal().accent)
              .glassPill()
              .geometryTransition('dockMorph')
              .onClick(() => {
                animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
                  this.searchText = '';
                  this.searchOpen = false;
                })
              })
          } else if (this.currentView === 'timeline') {
            Image($r('app.media.activity'))
              .width(58)
              .height(58)
              .padding(19)
              .fillColor(this.pal().accent)
              .glassPill()
              .geometryTransition('dockMorph')
              .onClick(() => {
                animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
                  this.searchText = '';
                  this.searchOpen = false;
                })
              })
          } else if (this.currentView === 'watchlist') {
            Image($r('app.media.clock'))
              .width(58)
              .height(58)
              .padding(19)
              .fillColor(this.pal().accent)
              .glassPill()
              .geometryTransition('dockMorph')
              .onClick(() => {
                animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
                  this.searchText = '';
                  this.searchOpen = false;
                })
              })
          } else {
            Image($r('app.media.list'))
              .width(58)
              .height(58)
              .padding(19)
              .fillColor(this.pal().accent)
              .glassPill()
              .geometryTransition('dockMorph')
              .onClick(() => {
                animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
                  this.searchText = '';
                  this.searchOpen = false;
                })
              })
          }
          this.searchBar()
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 10 })   // 两态子项等高 → 占位一致
      }

      if (this.sidebarOpen) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick(() => {
              this.closeSidebar();
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.3)')
        .transition(TransitionEffect.OPACITY)

        // 侧栏：Stack 现为 Bottom 对齐，直接放会被水平居中 → 用全尺寸 Row 左对齐承载
        Row() {
          this.sidebar()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .hitTestBehavior(HitTestMode.Transparent)
      }


      // 共享任务编辑弹层（条件渲染：每次打开重新挂载，aboutToAppear 装载表单）
      if (this.taskEditVisible) {
        TaskEditSheet({
          taskId: this.taskEditId,
          onClose: () => {
            this.taskEditVisible = false;
          },
          onSaved: () => {
            this.onTaskSaved();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
