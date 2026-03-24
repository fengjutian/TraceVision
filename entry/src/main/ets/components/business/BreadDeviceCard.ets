/**
 * @file    面包设备卡片组件
 * @desc    展示单个面包设备的名称、RSSI、近距离等级及最后更新时间
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import { BreadDevice, DeviceStatus } from '../model/BreadDevice';
import { estimateDistance } from '../utils/ProximityUtils';
import { ProximityBadge } from './ProximityBadge';

/** 点击回调类型 */
export type DeviceCardClickCallback = (device: BreadDevice) => void;

@Component
export struct BreadDeviceCard {
  @Prop device: BreadDevice = {} as BreadDevice;
  @Prop isActive: boolean = false;
  onTap: DeviceCardClickCallback = () => {};

  private _formatTime(ts: number): string {
    const d = new Date(ts);
    const hh = d.getHours().toString().padStart(2, '0');
    const mm = d.getMinutes().toString().padStart(2, '0');
    const ss = d.getSeconds().toString().padStart(2, '0');
    return `${hh}:${mm}:${ss}`;
  }

  build() {
    Column({ space: 8 }) {
      // 顶部：设备名 + 在线状态
      Row() {
        Row({ space: 6 }) {
          Circle({ width: 8, height: 8 })
            .fill(this.device.status === DeviceStatus.ACTIVE
              ? $r('app.color.proximity_near')
              : $r('app.color.proximity_far'))
          Text(this.device.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }

        Blank()

        ProximityBadge({ level: this.device.proximityLevel })
      }
      .width('100%')

      // 中间：RSSI + 估算距离
      Row({ space: 16 }) {
        Column({ space: 2 }) {
          Text('信号强度')
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
          Text(`${this.device.rssi} dBm`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }

        Column({ space: 2 }) {
          Text('估算距离')
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
          Text(`≈ ${estimateDistance(this.device.rssi).toFixed(1)} m`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }

        Column({ space: 2 }) {
          Text('最后更新')
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
          Text(this._formatTime(this.device.lastSeenAt))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .width('100%')

      // 底部：设备 ID
      Text(`ID: ${this.device.deviceId}`)
        .fontSize(10)
        .fontColor($r('app.color.text_hint'))
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(12)
    .border({
      width: this.isActive ? 2 : 0,
      color: $r('app.color.brand_primary'),
    })
    .shadow({ radius: 4, color: '#00000010', offsetX: 0, offsetY: 2 })
    .opacity(this.device.status === DeviceStatus.LOST ? 0.5 : 1.0)
    .animation({ duration: 300, curve: Curve.EaseOut })
    .onClick(() => this.onTap(this.device))
  }
}
