import { common } from '@kit.AbilityKit';
import { FontSize, Palette, Radius, Space, TOUCH_TARGET, Weight, palette } from '../common/Theme';
import { SyncEngine } from '../common/SyncEngine';
import { Store } from '../common/Storage';
import { Task, Subtask, Recurrence, agentStatusLabel } from '../common/Models';
import { Attachments } from '../common/Attachments';

/**
 * 共享任务编辑弹层（新建/编辑）。
 * - Index 与 TasksPage 各持一个实例；taskId='' 为新建、否则编辑该任务。
 * - 修复①「新建跳时间线」：弹层挂任意页面，不切视图。
 * - 修复②「弹层不完整」：表单区 Scroll + 外层 maxHeight 86%，底部按钮恒可见。
 * - 保存后回调 onSaved（宿主刷新列表/泳道）。
 */
@Component
export struct TaskEditSheet {
  @Prop taskId: string = '';      // '' = 新建；宿主条件渲染，每次打开重新挂载
  onClose: () => void = () => { };
  onSaved: () => void = () => { };
  @StorageProp('darkMode') isDark: boolean = false;
  @State deviceId: string = '';
  @State editingId: string = '';
  @State fTitle: string = '';
  @State fDescription: string = '';
  @State fCategory: string = '';
  @State fTrack: string = '';
  @State fPriority: string = '';
  @State fCompleted: boolean = false;
  @State fDueDate: string = '';
  @State fReminderBefore: string = '0';
  @State fTagsText: string = '';
  @State fSubtasks: Subtask[] = [];
  @State fRecurType: string = 'none';
  @State fRecurInterval: string = '';
  @State fAttachments: string[] = [];
  @State mdTab: string = 'edit';
  @State fTaskKind: string = 'human';
  @State fOwnersText: string = '';
  @State fAgentStatus: string = '';
  @State confirmVisible: boolean = false;

  private pal(): Palette {
    return palette(this.isDark);
  }

  private buttonRadius(): number {
    return this.isDark ? Radius.control : Radius.pill;
  }

  aboutToAppear(): void {
    Store.init(getContext(this) as common.Context).then(() => {
      Store.getDeviceId().then((id: string) => {
        this.deviceId = id;
      });
    });
    // 宿主条件渲染：每次打开 = 重新挂载，此处按 taskId 装载表单
    this.applyTaskId();
  }

  private resetForm(): void {
    this.editingId = '';
    this.fTitle = '';
    this.fDescription = '';
    this.fCategory = '';
    this.fTrack = '';
    this.fPriority = '';
    this.fCompleted = false;
    this.fDueDate = '';
    this.fReminderBefore = '0';
    this.fTagsText = '';
    this.fSubtasks = [];
    this.fRecurType = 'none';
    this.fRecurInterval = '';
    this.fAttachments = [];
    this.mdTab = 'edit';
    this.fTaskKind = 'human';
    this.fOwnersText = '';
    this.fAgentStatus = '';
  }

  private loadForm(t: Task): void {
    this.editingId = t.id;
    this.fTitle = t.title;
    this.fDescription = t.description;
    this.fCategory = t.category;
    this.fTrack = t.track;
    this.fPriority = t.priority;
    this.fCompleted = t.status === 'completed';
    this.fDueDate = t.dueDate;
    this.fReminderBefore = t.reminderBefore > 0 ? '' + t.reminderBefore : '0';
    this.fTagsText = t.tags.join(',');
    this.fSubtasks = t.subtasks.slice();
    this.fAttachments = t.attachments.slice();
    this.mdTab = 'edit';
    this.fTaskKind = t.taskKind;
    this.fOwnersText = t.agentOwners.join(',');
    this.fAgentStatus = t.agentStatus;
    if (t.recurrence !== null) {
      this.fRecurType = t.recurrence.type;
      this.fRecurInterval = '' + t.recurrence.interval;
    } else {
      this.fRecurType = 'none';
      this.fRecurInterval = '';
    }
  }

  // 打开时按 taskId 装载表单
  private applyTaskId(): void {
    if (this.taskId === '') {
      this.resetForm();
      return;
    }
    const t = SyncEngine.tasks.find((x: Task) => x.id === this.taskId);
    if (t) { this.loadForm(t); } else { this.resetForm(); }
  }

  private parseTags(raw: string): string[] {
    const out: string[] = [];
    const parts = raw.split(',');
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i].trim();
      if (p !== '') { out.push(p); }
    }
    return out;
  }

  private addSubtask(): void {
    const s = new Subtask();
    s.id = 'sub_' + Date.now().toString(36) + '_' + Math.floor(Math.random() * 0xffff).toString(36);
    s.title = '';
    s.completed = false;
    s.order = this.fSubtasks.length;
    this.fSubtasks.push(s);
    this.fSubtasks = this.fSubtasks.slice();
  }

  private removeSubtask(id: string): void {
    this.fSubtasks = this.fSubtasks.filter((s: Subtask) => s.id !== id);
  }

  async addAttachment(): Promise<void> {
    try {
      const url = await Attachments.pickImage();
      if (url === '') {
        this.getUIContext().getPromptAction().showToast({ message: '图片过大（压缩待做）或已取消' });
        return;
      }
      this.fAttachments.push(url);
      this.fAttachments = this.fAttachments.slice();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '选择图片失败' });
    }
  }

  private removeAttachment(index: number): void {
    this.fAttachments.splice(index, 1);
    this.fAttachments = this.fAttachments.slice();
  }

  async confirmDelete(): Promise<void> {
    const t = SyncEngine.tasks.find((x: Task) => x.id === this.editingId);
    if (t) {
      t.isDeleted = true;
      t.updatedAt = new Date().toISOString();
      t.version = t.version + 1;
      await SyncEngine.pushOne(t);
      SyncEngine.tasks = SyncEngine.tasks.filter((x: Task) => x.id !== this.editingId);
      this.onSaved();
    }
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.confirmVisible = false; });
    this.close();
  }

  async saveEdit(): Promise<void> {
    const now = new Date().toISOString();
    let t: Task;
    if (this.editingId === '') {
      t = new Task();
      t.id = 'task_' + Date.now().toString(36) + '_' + Math.floor(Math.random() * 0xffff).toString(36);
      t.createdAt = now;
      t.version = 1;
      t.deviceId = this.deviceId;
      t.subtasks = [];
      t.tags = [];
      t.attachments = [];
      t.recurrence = null;
      t.category = '';
      t.track = '';
      t.completedAt = '';
      t.dueTime = '';
    } else {
      const old = SyncEngine.tasks.find((x: Task) => x.id === this.editingId);
      t = old ? old : new Task();
      t.version = old ? old.version + 1 : 1;
    }
    t.title = this.fTitle;
    t.description = this.fDescription;
    t.category = this.fCategory.trim();
    t.track = this.fTrack.trim();
    t.priority = this.fPriority;
    t.status = this.fCompleted ? 'completed' : 'pending';
    t.completedAt = this.fCompleted ? now : '';
    t.dueDate = this.fDueDate;
    t.reminderBefore = this.fReminderBefore === '' ? 0 : parseInt(this.fReminderBefore, 10);
    t.tags = this.parseTags(this.fTagsText);
    t.subtasks = this.fSubtasks;
    t.attachments = this.fAttachments;
    if (this.fRecurType === 'none') {
      t.recurrence = null;
    } else {
      const rec = new Recurrence();
      rec.type = this.fRecurType;
      rec.interval = this.fRecurInterval === '' ? 1 : parseInt(this.fRecurInterval, 10);
      rec.endDate = '';
      t.recurrence = rec;
    }
    t.updatedAt = now;
    t.isDeleted = false;
    t.taskKind = this.fTaskKind;
    const owners: string[] = [];
    const ops = this.fOwnersText.split(',');
    for (let oi = 0; oi < ops.length; oi++) {
      const op = ops[oi].trim();
      if (op !== '') { owners.push(op); }
    }
    t.agentOwners = owners;
    if (this.fTaskKind === 'human') {
      t.agentStatus = '';
    } else if (t.agentStatus === '') {
      t.agentStatus = 'queued';
    }
    if (this.editingId === '') {
      SyncEngine.tasks.push(t);
    } else {
      const idx = SyncEngine.tasks.findIndex((x: Task) => x.id === this.editingId);
      if (idx >= 0) { SyncEngine.tasks[idx] = t; }
    }
    const ok = await SyncEngine.pushOne(t);
    this.onSaved();
    this.close();
    if (!ok) {
      this.getUIContext().getPromptAction().showToast({ message: '已离线保存，恢复后自动同步' });
    }
  }

  private close(): void {
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.onClose(); });
  }

  @Builder
  mdTabBtn(key: string, label: string) {
    Text(label)
      .fontSize(FontSize.secondary)
      .fontWeight(this.mdTab === key ? Weight.semibold : Weight.regular)
      .fontColor(this.mdTab === key ? this.pal().accent : this.pal().text2)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.mdTab === key ? this.pal().chip : 'transparent')
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.mdTab = key;
      })
  }

  @Builder
  priChip(key: string, label: string) {
    Text(label)
      .fontSize(FontSize.body)
      .fontWeight(Weight.regular)
      .fontColor(this.fPriority === key ? this.pal().accent : this.pal().text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.pal().chip)
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.fPriority = key;
      })
  }

  @Builder
  recurChip(key: string, label: string) {
    Text(label)
      .fontSize(FontSize.secondary)
      .fontWeight(Weight.regular)
      .fontColor(this.fRecurType === key ? this.pal().accent : this.pal().text)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.pal().chip)
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.fRecurType = key;
      })
  }

  @Builder
  kindChip(key: string, label: string) {
    Text(label)
      .fontSize(FontSize.secondary)
      .fontWeight(Weight.regular)
      .fontColor(this.fTaskKind === key ? this.pal().accent : this.pal().text)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.pal().chip)
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.fTaskKind = key;
      })
  }

  // 现有分类（最多 6 个，用于快捷填充）
  private existingCats(): string[] {
    const out: string[] = [];
    for (let i = 0; i < SyncEngine.tasks.length && out.length < 6; i++) {
      const c = SyncEngine.tasks[i].category;
      if (c !== '' && out.indexOf(c) < 0) { out.push(c); }
    }
    return out;
  }

  private dateStr(offsetDays: number): string {
    const d = new Date();
    d.setDate(d.getDate() + offsetDays);
    const m = ('0' + (d.getMonth() + 1)).slice(-2);
    const day = ('0' + d.getDate()).slice(-2);
    return d.getFullYear() + '-' + m + '-' + day;
  }

  /** 日期选择器（系统弹层，非手填） */
  private pickDueDate(): void {
    let sel = new Date();
    if (this.fDueDate.length >= 10) {
      const y = parseInt(this.fDueDate.substring(0, 4));
      const m = parseInt(this.fDueDate.substring(5, 7));
      const d = parseInt(this.fDueDate.substring(8, 10));
      sel = new Date(y, m - 1, d);
    }
    this.getUIContext().showDatePickerDialog({
      selected: sel,
      onDateAccept: (value: Date) => {
        const mm = ('0' + (value.getMonth() + 1)).slice(-2);
        const dd = ('0' + value.getDate()).slice(-2);
        this.fDueDate = value.getFullYear() + '-' + mm + '-' + dd;
      }
    });
  }

  /** 提醒选项 chip（选择式，替代手填分钟） */
  @Builder
  remChip(value: string, label: string) {
    Text(label)
      .fontSize(FontSize.helper)
      .fontWeight(this.fReminderBefore === value ? Weight.semibold : Weight.regular)
      .fontColor(this.fReminderBefore === value ? this.pal().accent : this.pal().text2)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(this.pal().chip)
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.fReminderBefore = value;
      })
  }

  @Builder
  quickDate(label: string, offset: number) {
    Text(label)
      .fontSize(FontSize.helper)
      .fontWeight(Weight.regular)
      .fontColor(this.pal().text2)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(this.pal().chip)
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.fDueDate = offset < 0 ? '' : this.dateStr(offset);
      })
  }

  @Builder
  editSheet() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          this.close();
        })
      Column() {
        // 头部：标题**居中**，关闭键贴右（Stack 三段式，保证真居中）
        Stack({ alignContent: Alignment.Center }) {
          Text(this.editingId === '' ? '新建任务' : '编辑任务')
            .fontSize(FontSize.panelTitle)
            .fontWeight(Weight.semibold)
            .fontColor(this.pal().text)
          Row() {
            Blank()
            Image($r('app.media.x'))
              .width(18)
              .height(18)
              .fillColor(this.pal().text3)
              .padding(4)
              .onClick(() => {
                this.close();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ bottom: Space.s1 })

        Row({ space: 4 }) {
          this.mdTabBtn('edit', '编辑')
          this.mdTabBtn('sub', '子任务')
          this.mdTabBtn('more', '更多')
        }
        .width('100%')
        .padding({ bottom: Space.s1 })

        Scroll() {
          Column({ space: Space.s2 }) {
            if (this.mdTab === 'edit') {
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

              TextArea({ text: this.fDescription, placeholder: '描述' })
                .fontSize(FontSize.body)
                .fontColor(this.pal().text)
                .placeholderColor(this.pal().text3)
                .backgroundColor(this.pal().card2)
                .borderRadius(Radius.control)
                .height(72)
                .onChange((v: string) => {
                  this.fDescription = v;
                })

              // 分类：选项式（现有分类一键选）+ 也能自己填
              Text('分类')
                .fontSize(FontSize.secondary)
                .fontWeight(Weight.regular)
                .fontColor(this.pal().text2)
              if (this.existingCats().length > 0) {
                Scroll() {
                  Row({ space: 6 }) {
                    ForEach(this.existingCats(), (c: string) => {
                      Text(c)
                        .fontSize(FontSize.helper)
                        .fontWeight(this.fCategory === c ? Weight.semibold : Weight.regular)
                        .fontColor(this.fCategory === c ? this.pal().accent : this.pal().text2)
                        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                        .backgroundColor(this.pal().chip)
                        .borderRadius(Radius.pill)
                        .onClick(() => {
                          this.fCategory = c;
                        })
                    }, (c: string) => c)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
              }
              TextInput({ text: this.fCategory, placeholder: '自定义分类' })
                .fontSize(FontSize.body)
                .fontColor(this.pal().text)
                .placeholderColor(this.pal().text3)
                .backgroundColor(this.pal().card2)
                .borderRadius(Radius.control)
                .height(40)
                .onChange((v: string) => {
                  this.fCategory = v;
                })

              TextInput({ text: this.fTrack, placeholder: '轨道' })
                .fontSize(FontSize.body)
                .fontColor(this.pal().text)
                .placeholderColor(this.pal().text3)
                .backgroundColor(this.pal().card2)
                .borderRadius(Radius.control)
                .height(40)
                .onChange((v: string) => {
                  this.fTrack = v;
                })

              // ── 属性区：优先级 / 截止 / 提醒 / 完成（重排：先选项、后开关）──
              Row({ space: 8 }) {
                Text('优先级')
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().text2)
                Blank()
                this.priChip('', '无')
                this.priChip('high', '高')
                this.priChip('medium', '中')
                this.priChip('low', '低')
              }
              .width('100%')

              Row({ space: 8 }) {
                Text('截止')
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().text2)
                Text(this.fDueDate === '' ? '未设置' : this.fDueDate)
                  .fontSize(FontSize.secondary)
                  .fontWeight(this.fDueDate === '' ? Weight.regular : Weight.semibold)
                  .fontColor(this.fDueDate === '' ? this.pal().text3 : this.pal().accent)
                Blank()
                Button('选择日期')
                  .height(32)
                  .padding({ left: 12, right: 12 })
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().text)
                  .backgroundColor(this.pal().chip)
                  .borderRadius(Radius.pill)
                  .onClick(() => {
                    this.pickDueDate();
                  })
                if (this.fDueDate !== '') {
                  Button('清除')
                    .height(32)
                    .padding({ left: 12, right: 12 })
                    .fontSize(FontSize.secondary)
                    .fontWeight(Weight.regular)
                    .fontColor(this.pal().text2)
                    .backgroundColor(this.pal().chip)
                    .borderRadius(Radius.pill)
                    .onClick(() => {
                      this.fDueDate = '';
                    })
                }
              }
              .width('100%')

              Row({ space: 8 }) {
                Text('提醒')
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().text2)
                Blank()
                this.remChip('0', '不提醒')
                this.remChip('5', '5分钟')
                this.remChip('15', '15分钟')
                this.remChip('30', '30分钟')
                this.remChip('60', '1小时')
                this.remChip('1440', '1天')
              }
              .width('100%')

              Row() {
                Text('完成')
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().text2)
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.fCompleted })
                  .selectedColor(this.pal().accent)
                  .onChange((on: boolean) => {
                    this.fCompleted = on;
                  })
              }
              .width('100%')
            } else if (this.mdTab === 'sub') {
              Row() {
                Text('子任务')
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().text2)
                Blank()
                Text('+ 添加')
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.semibold)
                  .fontColor(this.pal().text2)
                  .onClick(() => {
                    this.addSubtask();
                  })
              }

              ForEach(this.fSubtasks, (s: Subtask) => {
                Row({ space: 8 }) {
                  Toggle({ type: ToggleType.Checkbox, isOn: s.completed })
                    .selectedColor(this.pal().accent)
                    .onChange((on: boolean) => {
                      s.completed = on;
                    })
                  TextInput({ text: s.title, placeholder: '子任务' })
                    .fontSize(FontSize.body)
                    .fontColor(this.pal().text)
                    .placeholderColor(this.pal().text3)
                    .backgroundColor(this.pal().card2)
                    .borderRadius(Radius.control)
                    .height(36)
                    .layoutWeight(1)
                    .onChange((v: string) => {
                      s.title = v;
                    })
                  Image($r('app.media.x'))
                    .width(16)
                    .height(16)
                    .fillColor(this.pal().text3)
                    .onClick(() => {
                      this.removeSubtask(s.id);
                    })
                }
                .width('100%')
              }, (s: Subtask) => s.id)
            } else {
              // 协作模式（对齐 web 三档 human / ai_auto / ai_check）
              Row({ space: 8 }) {
                Text('协作模式')
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().text2)
                this.kindChip('human', '无')
                this.kindChip('ai_auto', 'AI全自动')
                this.kindChip('ai_check', 'AI+我确认')
              }
              TextInput({ text: this.fOwnersText, placeholder: 'Agent 归属（逗号分隔，如 workbuddy, codex）' })
                .fontSize(FontSize.body)
                .fontColor(this.pal().text)
                .placeholderColor(this.pal().text3)
                .backgroundColor(this.pal().card2)
                .borderRadius(Radius.control)
                .height(40)
                .onChange((v: string) => {
                  this.fOwnersText = v;
                })
              if (this.fTaskKind !== 'human' && this.fAgentStatus !== '') {
                Text('当前状态：' + agentStatusLabel(this.fAgentStatus))
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().accent)
              }

              Row({ space: 8 }) {
                Text('循环')
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().text2)
                this.recurChip('none', '无')
                this.recurChip('daily', '每天')
                this.recurChip('weekly', '每周')
                this.recurChip('monthly', '每月')
                if (this.fRecurType !== 'none') {
                  TextInput({ text: this.fRecurInterval, placeholder: '间隔' })
                    .fontSize(FontSize.secondary)
                    .fontColor(this.pal().text)
                    .placeholderColor(this.pal().text3)
                    .backgroundColor(this.pal().card2)
                    .borderRadius(Radius.control)
                    .height(32)
                    .width(52)
                    .onChange((v: string) => {
                      this.fRecurInterval = v;
                    })
                }
              }

              Row() {
                Text('附件')
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.regular)
                  .fontColor(this.pal().text2)
                Blank()
                Text('+ 添加图片')
                  .fontSize(FontSize.secondary)
                  .fontWeight(Weight.semibold)
                  .fontColor(this.pal().text2)
                  .onClick(() => {
                    this.addAttachment();
                  })
              }

              ForEach(this.fAttachments, (a: string, i: number) => {
                Row() {
                  Text('图片 ' + (i + 1))
                    .fontSize(FontSize.body)
                    .fontWeight(Weight.regular)
                    .fontColor(this.pal().text2)
                    .layoutWeight(1)
                  Image($r('app.media.x'))
                    .width(16)
                    .height(16)
                    .fillColor(this.pal().text3)
                    .onClick(() => {
                      this.removeAttachment(i);
                    })
                }
                .width('100%')
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .borderRadius(Radius.control)
                .backgroundColor(this.pal().card2)
              }, (a: string, i: number) => a + i)

              TextInput({ text: this.fTagsText, placeholder: '标签（逗号分隔，可选）' })
                .fontSize(FontSize.body)
                .fontColor(this.pal().text)
                .placeholderColor(this.pal().text3)
                .backgroundColor(this.pal().card2)
                .borderRadius(Radius.control)
                .height(40)
                .onChange((v: string) => {
                  this.fTagsText = v;
                })
            }
          }
          .width('100%')
          .padding({ bottom: Space.s1 })
        }
        .width('100%')
        .flexShrink(1)
        .scrollBar(BarState.Off)

        Row({ space: 12 }) {
          if (this.editingId !== '') {
            Button('删除')
              .height(TOUCH_TARGET)
              .layoutWeight(1)
              .fontSize(FontSize.body)
              .fontWeight(Weight.regular)
              .fontColor(this.pal().text)
              .backgroundColor(this.pal().card2)
              .borderRadius(this.buttonRadius())
              .onClick(() => {
                animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.confirmVisible = true; });
              })
          }
          Button('取消')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor(this.pal().text)
            .backgroundColor(this.pal().card2)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              this.close();
            })
          Button('保存')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
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
  confirmSheet() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.confirmVisible = false; });
        })
      Column({ space: Space.s2 }) {
        Text('删除任务？')
          .fontSize(FontSize.panelTitle)
          .fontWeight(Weight.semibold)
          .fontColor(this.pal().text)
        Text('删除后所有设备同步移除')
          .fontSize(FontSize.body)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text2)
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
              animateTo({ duration: 250, curve: Curve.EaseOut }, () => { this.confirmVisible = false; });
            })
          Button('删除')
            .height(TOUCH_TARGET)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontWeight(Weight.regular)
            .fontColor('#ffffff')
            .backgroundColor(this.pal().accent)
            .borderRadius(this.buttonRadius())
            .onClick(() => {
              this.confirmDelete();
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
    Stack() {
      this.editSheet()
      if (this.confirmVisible) {
        this.confirmSheet()
      }
    }
    .width('100%')
    .height('100%')
  }
}
