import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { DARK_MODE_KEY } from '../common/Theme';
import { SystemBars } from '../common/SystemBars';
import { SyncEngine } from '../common/SyncEngine';
import { WidgetData } from '../common/WidgetData';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 通知深链：提醒点按携带 taskId → 待办页打开对应任务（冷启动路径）
    if (AppStorage.get<string>('pendingTaskId') === undefined) {
      AppStorage.setOrCreate<string>('pendingTaskId', '');
    }
    if (AppStorage.get<string>('pendingNew') === undefined) {
      AppStorage.setOrCreate<string>('pendingNew', '');
    }
    if (want.parameters) {
      // 卡片 router 事件（扁平写法 {action,abilityName,params}）参数落在 want.parameters.params 里；
      // 通知深链则是平铺的 taskId/pendingNew —— 两种都收
      let tid = want.parameters['taskId'] as string;
      let pnew = want.parameters['pendingNew'] as string;
      const nested = want.parameters['params'] as Record<string, string>;
      if (nested) {
        if (!tid && nested['taskId']) { tid = nested['taskId']; }
        if (!pnew && nested['pendingNew']) { pnew = nested['pendingNew']; }
      }
      hilog.info(DOMAIN, 'testTag', 'want params: %{public}s', JSON.stringify(want.parameters));
      if (tid) {
        AppStorage.setOrCreate<string>('pendingTaskId', tid);
      }
      if (pnew === '1') {
        AppStorage.setOrCreate<string>('pendingNew', '1');
      }
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 主题键必须在页面组件创建前存在（SettingsPage 的 @StorageLink 依赖，键缺失会启动崩溃）
    AppStorage.setOrCreate<boolean>(DARK_MODE_KEY, false);
    AppStorage.setOrCreate<boolean>('showWatched', false);

    // 数据变更后刷新桌面卡片（完成/新增任务 → 卡片立刻跟上）
    SyncEngine.onChanged = () => {
      WidgetData.refreshAll();
    };
    // 进入 App 也顺手刷新一次卡片（内存为空时 refreshAll 会先拉一次，不会把卡片刷成 0）
    WidgetData.refreshAll();

    // 系统栏刷页面同色（消除底部系统导航栏纯白带 → 见 SystemBars 注释）
    SystemBars.apply(this.context, false);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}