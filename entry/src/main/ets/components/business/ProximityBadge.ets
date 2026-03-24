/**
 * @file    设备信号强度指示器组件
 * @desc    以三格图标直观展示 ProximityLevel，颜色编码：绿/黄/红
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import { ProximityLevel } from '../model/BreadDevice';
import { proximityLevelToLabel } from '../utils/ProximityUtils';

@Component
export struct ProximityBadge {
  @Prop level: ProximityLevel = ProximityLevel.UNKNOWN;

  private _getColor(): ResourceColor {
    switch (this.level) {
      case ProximityLevel.NEAR:   return $r('app.color.proximity_near');
      case ProximityLevel.MEDIUM: return $r('app.color.proximity_medium');
      case ProximityLevel.FAR:    return $r('app.color.proximity_far');
      default:                    return $r('app.color.text_hint');
    }
  }

  private _getIcon(): string {
    switch (this.level) {
      case ProximityLevel.NEAR:   return '●●●';
      case ProximityLevel.MEDIUM: return '●●○';
      case ProximityLevel.FAR:    return '●○○';
      default:                    return '○○○';
    }
  }

  build() {
    Row({ space: 4 }) {
      Text(this._getIcon())
        .fontSize(12)
        .fontColor(this._getColor())
        .letterSpacing(2)
      Text(proximityLevelToLabel(this.level))
        .fontSize(11)
        .fontColor(this._getColor())
    }
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .backgroundColor(this._getColor())
    .opacity(0.15)
    .borderRadius(10)
    .overlay(
      Row({ space: 4 }) {
        Text(this._getIcon())
          .fontSize(12)
          .fontColor(this._getColor())
          .letterSpacing(2)
        Text(proximityLevelToLabel(this.level))
          .fontSize(11)
          .fontColor(this._getColor())
      }
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    )
  }
}
