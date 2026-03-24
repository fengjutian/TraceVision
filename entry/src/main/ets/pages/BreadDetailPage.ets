/**
 * @file    面包设备详情页
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import router from '@ohos.router';
import emitter from '@ohos.events.emitter';
import { BreadDevice, DeviceStatus, ProximityLevel } from '../model/BreadDevice';
import { BLE_EVENTS, BleDeviceEventData } from '../service/ProximityService';
import { getActiveViewModel } from '../viewmodel/ProximityViewModel';
import { ProximityBadge } from '../components/business/ProximityBadge';
import { estimateDistance, proximityLevelToLabel } from '../utils/ProximityUtils';
import { AUTO_NAV_DELAY, RSSI_HISTORY_MAX } from '../constants/AppConstants';
import { Logger } from '../utils/Logger';

interface DetailRouteParams {
  deviceId: string;
  deviceName: string;
  deviceSnapshot: string;
}

interface RssiPoint {
  rssi: number;
  ts: number;
}

@Entry
@Component
struct BreadDetailPage {
  private _deviceId: string = '';
  private _deviceName: string = '';

  @State private device: BreadDevice | null = null;
  @State private rssiHistory: RssiPoint[] = [];
  @State private isAutoClosing: boolean = false;
  @State private autoCloseCountdown: number = 0;
  @State private closeHint: string = '';

  private _autoCloseTimer: number = -1;
  private _countdownTimer: number = -1;
  private _listenerUpdated: ((event: emitter.EventData) => void) | null = null;
  private _listenerLost: ((event: emitter.EventData) => void) | null = null;

  aboutToAppear(): void {
    const params = router.getParams() as DetailRouteParams;
    this._deviceId = params?.deviceId ?? '';
    this._deviceName = params?.deviceName ?? '未知设备';

    if (params?.deviceSnapshot) {
      try {
        const snap: BreadDevice = JSON.parse(params.deviceSnapshot) as BreadDevice;
        this.device = snap;
        this.rssiHistory = [{ rssi: snap.rssi, ts: snap.lastSeenAt }];
      } catch {
        Logger.warn('BreadDetailPage', 'Failed to parse device snapshot');
      }
    }
    this._registerEvents();
    Logger.info('BreadDetailPage', `Opened for device: ${this._deviceId}`);
  }

  aboutToDisappear(): void {
    this._unregisterEvents();
    this._clearTimers();
    getActiveViewModel()?.notifyDetailClosed(this._deviceId);
    Logger.info('BreadDetailPage', `Closed for device: ${this._deviceId}`);
  }

  private _registerEvents(): void {
    const onUpdated = (event: emitter.EventData): void => {
      const data = event.data as BleDeviceEventData;
      if (data.device.deviceId !== this._deviceId) {
        return;
      }
      this.device = data.device;
      const slice = this.rssiHistory.slice(-(RSSI_HISTORY_MAX - 1));
      const newPoint: RssiPoint = { rssi: data.device.rssi, ts: data.device.lastSeenAt };
      const newHistory: RssiPoint[] = [];
      for (const p of slice) {
        newHistory.push(p);
      }
      newHistory.push(newPoint);
      this.rssiHistory = newHistory;
      if (data.device.proximityLevel === ProximityLevel.NEAR && this.isAutoClosing) {
        this._cancelAutoClose();
      }
    };

    const onLost = (event: emitter.EventData): void => {
      const data = event.data as BleDeviceEventData;
      if (data.device.deviceId !== this._deviceId) {
        return;
      }
      Logger.info('BreadDetailPage', 'Device lost signal, scheduling auto close');
      this.device = data.device;
      this._scheduleAutoClose();
    };

    emitter.on({ eventId: BLE_EVENTS['DEVICE_UPDATED'] }, onUpdated);
    emitter.on({ eventId: BLE_EVENTS['DEVICE_LOST'] }, onLost);
    this._listenerUpdated = onUpdated;
    this._listenerLost = onLost;
  }

  private _unregisterEvents(): void {
    if (this._listenerUpdated) {
      emitter.off(BLE_EVENTS['DEVICE_UPDATED'], this._listenerUpdated);
      this._listenerUpdated = null;
    }
    if (this._listenerLost) {
      emitter.off(BLE_EVENTS['DEVICE_LOST'], this._listenerLost);
      this._listenerLost = null;
    }
  }

  private _scheduleAutoClose(): void {
    if (this.isAutoClosing) {
      return;
    }
    this.isAutoClosing = true;
    this.autoCloseCountdown = Math.ceil(AUTO_NAV_DELAY.CLOSE_DEBOUNCE_MS / 1000);
    this.closeHint = `设备已离开，${this.autoCloseCountdown}s 后自动关闭`;

    this._countdownTimer = setInterval(() => {
      this.autoCloseCountdown -= 1;
      this.closeHint = `设备已离开，${this.autoCloseCountdown}s 后自动关闭`;
    }, 1000);

    this._autoCloseTimer = setTimeout(() => {
      Logger.info('BreadDetailPage', `Auto close executed for ${this._deviceId}`);
      this._clearTimers();
      router.back();
    }, AUTO_NAV_DELAY.CLOSE_DEBOUNCE_MS);
  }

  private _cancelAutoClose(): void {
    this.isAutoClosing = false;
    this.closeHint = '';
    this._clearTimers();
    Logger.info('BreadDetailPage', 'Auto close cancelled');
  }

  private _clearTimers(): void {
    if (this._autoCloseTimer !== -1) {
      clearTimeout(this._autoCloseTimer);
      this._autoCloseTimer = -1;
    }
    if (this._countdownTimer !== -1) {
      clearInterval(this._countdownTimer);
      this._countdownTimer = -1;
    }
  }

  private _formatDistanceRange(rssi: number): string {
    const center: number = estimateDistance(rssi);
    if (center < 0) {
      return '--';
    }
    const low: number = Math.max(0, center * 0.5);
    const high: number = center * 1.5;
    if (low < 1) {
      return `< ${high.toFixed(1)} m`;
    }
    return `${low.toFixed(1)} ~ ${high.toFixed(1)} m`;
  }

  private _rssiMin(): number {
    let min: number = 0;
    for (const p of this.rssiHistory) {
      if (min === 0 || p.rssi < min) {
        min = p.rssi;
      }
    }
    return min;
  }

  private _rssiMax(): number {
    let max: number = 0;
    for (const p of this.rssiHistory) {
      if (max === 0 || p.rssi > max) {
        max = p.rssi;
      }
    }
    return max;
  }

  private _barHeight(rssi: number): number {
    const normalized: number = Math.max(0, Math.min(1, (rssi + 100) / 70));
    return 10 + normalized * 50;
  }

  build() {
    Column() {
      this._buildHeader()
      if (this.isAutoClosing) {
        this._buildAutoCloseBanner()
      }
      Scroll() {
        Column({ space: 16 }) {
          this._buildInfoCard()
          this._buildRssiHistory()
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  private _buildHeader() {
    Row() {
      Button() {
        Text('‹')
          .fontSize(24)
          .fontColor($r('app.color.text_primary'))
      }
      .backgroundColor(Color.Transparent)
      .onClick(() => router.back())

      Text(this._deviceName)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Button()
        .width(40)
        .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 50, bottom: 12 })
    .backgroundColor($r('app.color.bg_card'))
  }

  @Builder
  private _buildAutoCloseBanner() {
    Row({ space: 8 }) {
      Text('📡')
        .fontSize(14)
      Text(this.closeHint)
        .fontSize(13)
        .fontColor($r('app.color.proximity_far'))
        .layoutWeight(1)
      Button('取消')
        .fontSize(12)
        .fontColor($r('app.color.brand_primary'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .onClick(() => this._cancelAutoClose())
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('#FFF3CD')
    .animation({ duration: 300, curve: Curve.EaseIn })
  }

  @Builder
  private _buildInfoCard() {
    Column({ space: 14 }) {
      Row() {
        Row({ space: 6 }) {
          Circle({ width: 10, height: 10 })
            .fill(this.device?.status === DeviceStatus.ACTIVE
              ? $r('app.color.proximity_near')
              : $r('app.color.proximity_far'))
          Text(this.device?.status === DeviceStatus.ACTIVE ? '在线' : '信号丢失')
            .fontSize(13)
            .fontColor(this.device?.status === DeviceStatus.ACTIVE
              ? $r('app.color.proximity_near')
              : $r('app.color.proximity_far'))
        }
        Blank()
        if (this.device) {
          ProximityBadge({ level: this.device.proximityLevel })
        }
      }
      .width('100%')

      Divider().color($r('app.color.divider'))

      Grid() {
        GridItem() {
          this._buildMetric('RSSI', `${this.device?.rssi ?? '--'} dBm`)
        }
        GridItem() {
          this._buildMetric('估算距离', this._formatDistanceRange(this.device?.rssi ?? -100))
        }
        GridItem() {
          this._buildMetric('近距离等级',
            proximityLevelToLabel(this.device?.proximityLevel ?? ProximityLevel.UNKNOWN))
        }
        GridItem() {
          this._buildMetric('设备 ID', this.device?.deviceId.slice(-8) ?? '--')
        }
      }
      .columnsTemplate('1fr 1fr')
      .rowsGap(12)
      .columnsGap(12)
      .width('100%')

      if (this.device?.advertiseData) {
        Divider().color($r('app.color.divider'))
        Text(`广播数据: ${this.device.advertiseData}`)
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
      }

      if (this.device?.batchInfo) {
        Divider().color($r('app.color.divider'))
        Column({ space: 8 }) {
          Text('批次信息')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Grid() {
            GridItem() {
              this._buildMetric('批次号', this.device.batchInfo.batchId || '--')
            }
            GridItem() {
              this._buildMetric('生产日期', this.device.batchInfo.productDate)
            }
            GridItem() {
              this._buildMetric('储存要求', this.device.batchInfo.tempLevel)
            }
            GridItem() {
              this._buildMetric('保质期', `${this.device.batchInfo.shelfDays} 天`)
            }
          }
          .columnsTemplate('1fr 1fr')
          .rowsGap(10)
          .columnsGap(12)
          .width('100%')
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(12)
    .shadow({ radius: 4, color: '#00000010', offsetX: 0, offsetY: 2 })
  }

  @Builder
  private _buildMetric(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_hint'))
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private _buildRssiHistory() {
    Column({ space: 10 }) {
      Text('RSSI 历史')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Row({ space: 2 }) {
        ForEach(
          this.rssiHistory,
          (point: RssiPoint) => {
            Column()
              .width(8)
              .height(this._barHeight(point.rssi))
              .backgroundColor(
                point.rssi >= -60
                  ? $r('app.color.proximity_near')
                  : point.rssi >= -80
                    ? $r('app.color.proximity_medium')
                    : $r('app.color.proximity_far')
              )
              .borderRadius(2)
              .animation({ duration: 200, curve: Curve.EaseOut })
          },
          (point: RssiPoint) => `${point.ts}`
        )
      }
      .width('100%')
      .height(70)
      .alignItems(VerticalAlign.Bottom)

      if (this.rssiHistory.length > 0) {
        Row() {
          Text(`最低: ${this._rssiMin()} dBm`)
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
          Blank()
          Text(`最高: ${this._rssiMax()} dBm`)
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(12)
    .shadow({ radius: 4, color: '#00000010', offsetX: 0, offsetY: 2 })
  }
}
