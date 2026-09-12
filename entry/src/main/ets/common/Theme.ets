/**
 * Theme.ets — ui-standard（design.md v1.1）token 落地，全工程唯一权威值源
 *
 * 平台等价映射（design.md CSS → ArkUI：设计意图不变，仅实现翻译）：
 * - 字体栈 -apple-system/…/PingFang SC → 鸿蒙系统字体 HarmonyOS Sans（系统默认，无需显式设置）
 * - 衬线 "New York"/Songti SC（logo/阅读正文）→ fontFamily('serif')（P2 正文阅读区启用）
 * - font-variant-numeric: tabular-nums → .fontFeature('tnum')（数字等宽）
 * - backdrop blur(20px) saturate(180%) → .backdropBlur(20).saturate(1.8)（玻璃层，P2 起用）
 * - 浮层唯一例外影 0 10px 30px rgba(0,0,0,.14) → .shadow({radius:30,color:'rgba(0,0,0,0.14)',offsetY:10})
 * - 字重 300/400/600 → Weight.light/regular = FontWeight.Light/Regular；semibold = 数值 fontWeight(600)
 *   （鸿蒙 FontWeight 枚举无 SemiBold/600 档；禁 Medium=500、Bold=700）
 * - 8pt 网格 → Space；动效 150–300ms → Motion
 */

export const DARK_MODE_KEY: string = 'darkMode';

// 字号阶梯（design.md §1.1；去碎档：同级不混邻近档）
export class FontSize {
  static readonly pageTitle: number = 20;   // 页面标题 20/600
  static readonly panelTitle: number = 17;  // 面板标题 17/600
  static readonly listTitle: number = 15;   // 列表标题 15/600
  static readonly body: number = 14;        // 正文 14
  static readonly listBody: number = 13;     // 列表正文 13
  static readonly secondary: number = 12;   // 副文字 12
  static readonly groupLabel: number = 11;  // 分组标签 11/600
  static readonly helper: number = 10;      // 辅助 10
}

// 圆角分档（§1.4：卡片 16 / 次级 12 / 控件 8 / pill 999）
export class Radius {
  static readonly card: number = 16;
  static readonly secondary: number = 12;
  static readonly control: number = 8;
  static readonly pill: number = 999;
}

// 8pt 网格基准（§2.4）
export class Space {
  static readonly s1: number = 8;
  static readonly s2: number = 16;
  static readonly s3: number = 24;
}

// 动效 150–300ms 统一缓动（§2.7）
export class Motion {
  static readonly fast: number = 150;
  static readonly base: number = 300;
}

// 触控目标下限（§2.4）
export const TOUCH_TARGET: number = 44;

// 字重（design.md §1.1 只许 300/400/600）：
// 鸿蒙 FontWeight 枚举无 600 档（无 SemiBold），故 600 用数值 fontWeight(600)；
// 禁 Medium(=500) / Bold(=700)。
export class Weight {
  static readonly light: number = 300;      // FontWeight.Light
  static readonly regular: number = 400;    // FontWeight.Regular
  static readonly semibold: number = 600;   // 数值 600（枚举缺档）
}

// 双主题色板（§1.4 精确值；亮 = Apple 白，暗 = Linear 暗）
export class Palette {
  accent: string = '#0066cc';
  accentHover: string = '#0071e3';
  bg: string = '#f5f5f7';
  sidebar: string = 'rgba(245,245,247,0.72)';
  card: string = '#ffffff';
  card2: string = '#f5f5f7';
  text: string = '#1d1d1f';
  text2: string = '#333333';
  text3: string = '#7a7a7a';
  border: string = '#e0e0e0';
  border2: string = '#d1d1d6';
  chip: string = 'rgba(0,0,0,0.05)';
  up: string = '#c0392b';
  down: string = '#1e8e5a';
}

// 注意（2026-09-07 闪退教训）：禁止模块级 `new Palette()`——
// ArkTS 不保证模块级副作用初始化先于 @Entry 首帧执行，曾导致
// palette() 返回 undefined → "Cannot read property card of undefined"。
// 无缓存：每次按需构造，绝不留模块级可变状态 → palette() 永不返回 undefined。
function makeDark(): Palette {
  const p = new Palette();
  p.accent = '#5e6ad2';
  p.accentHover = '#828fff';
  p.bg = '#010102';
  p.sidebar = 'rgba(15,16,17,0.72)';
  p.card = '#0f1011';
  p.card2 = '#141516';
  p.text = '#f7f8f8';
  p.text2 = '#d0d6e0';
  p.text3 = '#8a8f98';
  p.border = '#23252a';
  p.border2 = '#34343a';
  p.chip = 'rgba(255,255,255,0.06)';
  p.up = '#ff6b5e';
  p.down = '#3ad07f';
  return p;
}

export function palette(dark: boolean): Palette {
  return dark ? makeDark() : new Palette();
}