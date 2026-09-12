import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { ApiClient } from '../common/ApiClient';
import { SyncEngine } from '../common/SyncEngine';
import { Store } from '../common/Storage';

/**
 * 桌面服务卡片扩展能力（v1.1）：
 * onAddForm 返回初始绑定数据；onUpdateForm（系统定时 10:30 或手动）拉最新任务数并 updateForm。
 */
export default class WidgetAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let today = '—';
    let pending = '—';
    if (SyncEngine.tasks.length > 0) {
      const d = new Date();
      const m = ('0' + (d.getMonth() + 1)).slice(-2);
      const day = ('0' + d.getDate()).slice(-2);
      const todayStr = d.getFullYear() + '-' + m + '-' + day;
      let t = 0;
      let p = 0;
      for (let i = 0; i < SyncEngine.tasks.length; i++) {
        const task = SyncEngine.tasks[i];
        if (task.dueDate === todayStr && task.status !== 'completed') { t++; }
        if (task.status === 'pending') { p++; }
      }
      today = '' + t;
      pending = '' + p;
    }
    return formBindingData.createFormBindingData({ 'todayCount': today, 'pendingCount': pending, 't1': '', 't2': '', 't3': '' });
  }

  onUpdateForm(formId: string): void {
    this.refresh(formId);
  }

  async refresh(formId: string): Promise<void> {
    try {
      await Store.init(this.context);
      const list = await SyncEngine.fullPull();
      const d = new Date();
      const m = ('0' + (d.getMonth() + 1)).slice(-2);
      const day = ('0' + d.getDate()).slice(-2);
      const todayStr = d.getFullYear() + '-' + m + '-' + day;
      let t = 0;
      let p = 0;
      const titles: string[] = [];
      for (let i = 0; i < list.length; i++) {
        const task = list[i];
        if (task.dueDate === todayStr && task.status !== 'completed') { t++; }
        if (task.status === 'pending') { p++; }
        if (task.dueDate === todayStr && task.status !== 'completed' && titles.length < 3) {
          titles.push(task.title);
        }
      }
      // v1.1：今日任务预览（最多 3 条标题）
      const data: Record<string, string> = {
        'todayCount': '' + t,
        'pendingCount': '' + p,
        't1': titles.length > 0 ? titles[0] : '',
        't2': titles.length > 1 ? titles[1] : '',
        't3': titles.length > 2 ? titles[2] : ''
      };
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (e) {
      // 更新失败忽略（ApiClient.status 备用）
      try {
        const s = await ApiClient.status();
        await formProvider.updateForm(formId, formBindingData.createFormBindingData({ 'todayCount': '—', 'pendingCount': '' + s.pendingCount, 't1': '', 't2': '', 't3': '' }));
      } catch (e2) {
        // 忽略
      }
    }
  }

  onFormEvent(formId: string, message: string): void {
    // 卡片消息事件（预留）
  }
}
