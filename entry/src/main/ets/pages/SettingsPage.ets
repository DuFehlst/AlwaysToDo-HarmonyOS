import { common } from '@kit.AbilityKit';
import { FontSize, Palette, Space, Weight, palette } from '../common/Theme';
import { ApiClient } from '../common/ApiClient';
import { SystemBars } from '../common/SystemBars';

/**
 * 设置 Tab（P1·2 占位 + P1·3 服务状态接入）。
 * 深色外观 = 双主题验收点；服务状态行 = P1·3 验收（App 拉 https 后端 /api/status）。
 * 状态：@StorageProp（只读，键缺失不崩）+ AppStorage.setOrCreate 显式回写；
 * 色板用方法 pal()（getter 在 build/update 管线会求值 undefined）。
 */
@Component
export struct SettingsPage {
  @StorageProp('darkMode') isDark: boolean = false;
  @State statusText: string = '连接中…';

  private pal(): Palette {
    return palette(this.isDark);
  }

  aboutToAppear(): void {
    this.loadStatus();
  }

  async loadStatus(): Promise<void> {
    try {
      const s = await ApiClient.status();
      this.statusText = '服务 ' + s.status + ' · 任务 ' + s.taskCount + ' · 设备 ' + s.deviceCount;
    } catch (e) {
      this.statusText = '无法连接';
    }
  }

  build() {
    Column() {
      Row() {
        Text('深色外观')
          .fontSize(FontSize.body)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.isDark })
          .selectedColor(this.pal().accent)
          .onChange((on: boolean) => {
            AppStorage.setOrCreate<boolean>('darkMode', on);
            SystemBars.apply(getContext(this) as common.Context, on);
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: Space.s2, right: Space.s2 })

      Row() {
        Text('服务状态')
          .fontSize(FontSize.body)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text)
        Blank()
        Text(this.statusText)
          .fontSize(FontSize.secondary)
          .fontWeight(Weight.regular)
          .fontColor(this.pal().text2)
      }
      .width('100%')
      .height(48)
      .padding({ left: Space.s2, right: Space.s2 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().bg)
  }
}
