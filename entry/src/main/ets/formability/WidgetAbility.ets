import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { Task } from '../common/Models';
import { SyncEngine } from '../common/SyncEngine';
import { Store } from '../common/Storage';
import { WidgetData } from '../common/WidgetData';

/**
 * 桌面服务卡片扩展能力（v2.0 · P0+P1）：
 * - onAddForm：按 want 里的 form_dimension 决定布局档位（1x2 / 2x2 / 2x4 / 4x4），注册 formId 到 Preferences
 * - onUpdateForm：系统定时（form_config：每小时 + 10:30）触发 → 全量拉取后刷新
 * - onFormEvent：卡片内勾选完成（message: {toggle: taskId}）→ 就地完成 + 推服务端 + 原地刷新（不打开 App）
 * - onRemoveForm：从注册表移除
 */
export default class WidgetAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let dim = '2x2';
    if (want.parameters) {
      const d = want.parameters['ohos.extra.param.key.form_dimension'] as number;
      if (d !== undefined) { dim = WidgetData.dimLabel(d); }
    }
    const formId = want.parameters ? (want.parameters['ohos.extra.param.key.form_id'] as string) : '';
    if (formId !== undefined && formId !== '') {
      Store.init(this.context).then(() => {
        Store.addFormId(formId, dim);
      });
    }
    return formBindingData.createFormBindingData(WidgetData.build(dim, SyncEngine.tasks));
  }

  onUpdateForm(formId: string): void {
    this.refresh(formId);
  }

  onRemoveForm(formId: string): void {
    Store.init(this.context).then(() => {
      Store.removeFormId(formId);
    });
  }

  /** 卡片内交互（message 事件）：目前只处理「勾选完成」 */
  onFormEvent(formId: string, message: string): void {
    let taskId = '';
    try {
      const p = JSON.parse(message) as Record<string, string>;
      const v = p['toggle'];
      if (v !== undefined) { taskId = v; }
    } catch (e) {
      taskId = '';
    }
    if (taskId === '') { return; }
    this.complete(formId, taskId);
  }

  private async complete(formId: string, taskId: string): Promise<void> {
    try {
      await Store.init(this.context);
      // 先在本地缓存里就地完成（卡片立刻有反馈），再推服务端
      const list = SyncEngine.tasks;
      let target: Task | null = null;
      for (let i = 0; i < list.length; i++) {
        if (list[i].id === taskId) { target = list[i]; break; }
      }
      if (target !== null) {
        target.status = 'completed';
        target.completedAt = new Date().toISOString();
        target.updatedAt = target.completedAt;
        target.version = target.version + 1;
        await SyncEngine.pushOne(target);
      }
      await this.refresh(formId);
    } catch (e) {
      // 失败忽略：下次定时刷新会纠正
    }
  }

  async refresh(formId: string): Promise<void> {
    try {
      await Store.init(this.context);
      const list = await SyncEngine.fullPull();
      const dim = await Store.getFormDim(formId);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(WidgetData.build(dim, list)));
    } catch (e) {
      // 离线：保留卡片上一次的内容，不把卡片刷成占位符
    }
  }
}
