import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

/**
 * 系统栏配色（2026-09-12 实测结论）：
 * 手机底部 y≈2750-2848 那条全宽纯白 #FFFFFF 不在 App 窗口内，是**系统导航栏**默认底色；
 * 它与悬浮 dock 胶囊连成一片 → 看起来像「dock 下多了一层白板」。
 * 这里把状态栏/导航栏刷成页面同色并跟随主题，从根上消除该白带。
 */
export class SystemBars {
  /** 应用系统栏配色（light: #F5F5F7 / dark: #010102） */
  static apply(ctx: common.Context, dark: boolean): void {
    try {
      window.getLastWindow(ctx).then((win: window.Window) => {
        win.setWindowSystemBarProperties({
          statusBarColor: dark ? '#010102' : '#F5F5F7',
          navigationBarColor: dark ? '#010102' : '#F5F5F7',
          statusBarContentColor: dark ? '#FFFFFF' : '#000000'
        }).catch(() => {
        });
      }).catch(() => {
      });
    } catch (e) {
      // 非窗口环境（卡片等）忽略
    }
  }
}
