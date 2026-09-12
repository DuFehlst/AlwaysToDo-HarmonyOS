import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { Task } from './Models';

/**
 * 系统通知（P2·6 + v1.1 深链）——按 reminderBefore 为到期任务调度系统提醒。
 * 点通知拉起 App 并携带 taskId（reminderAgentManager.WantAgent = {pkgName, abilityName, parameters}，
 * 类型已从 SDK d.ts 核对——不是 wantAgent.getWantAgent()）。
 * 权限：ohos.permission.PUBLISH_AGENT_REMINDER（清单已声明）。
 */
export class Reminders {
  /** 申请通知权限（用户侧一次授权，拒绝也不阻断） */
  static async requestEnable(): Promise<void> {
    try {
      await notificationManager.requestEnableNotification();
    } catch (e) {
      // 用户拒绝或已授权，忽略
    }
  }

  /** 为所有到期任务调度提醒（只调度未来触发点；旧的/已过的跳过） */
  static async schedule(tasks: Task[]): Promise<void> {
    const now = Date.now();
    for (let i = 0; i < tasks.length; i++) {
      const t = tasks[i];
      if (t.reminderBefore <= 0) { continue; }
      const trigger = Reminders.triggerMs(t);
      if (trigger <= now) { continue; }
      const secondsUntil = Math.floor((trigger - now) / 1000);
      const params: Record<string, Object> = { 'taskId': t.id };
      const wa: reminderAgentManager.WantAgent = {
        pkgName: 'com.always.todosync',
        abilityName: 'EntryAbility',
        parameters: params
      };
      const req: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        triggerTimeInSeconds: secondsUntil,
        title: t.title,
        content: '任务到期',
        expiredContent: '任务已过期',
        notificationId: Math.abs(Reminders.hashId(t.id)) % 100000 + 1,
        wantAgent: wa
      };
      try {
        await reminderAgentManager.publishReminder(req);
      } catch (e) {
        // 单个任务调度失败不阻断其余
      }
    }
  }

  /** dueDate + dueTime（无则 09:00） - reminderBefore 分钟 → 触发毫秒 */
  private static triggerMs(t: Task): number {
    const time = t.dueTime === '' ? '09:00' : t.dueTime;
    const dt = new Date(t.dueDate + 'T' + time + ':00').getTime();
    return dt - t.reminderBefore * 60 * 1000;
  }

  private static hashId(id: string): number {
    let h = 0;
    for (let i = 0; i < id.length; i++) {
      h = (h * 31 + id.charCodeAt(i)) % 2147483647;
    }
    return h;
  }
}
