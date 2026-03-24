/**
 * @file    面包设备详情页
 * @desc    展示单个面包设备的详细信息及实时 RSSI 曲线；
 *          当设备信号丢失（DEVICE_LOST 事件）时启动倒计时并自动关闭页面返回列表。
 *          设备快照通过路由参数传入，后续更新通过 emitter 订阅获取，
 *          不直接访问 ProximityService 单例（遵循分层架构）。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import router from '@ohos.router';
import emitter from '@ohos.events.emitter';
import { BreadDevice, DeviceStatus, ProximityLevel } from '../model/BreadDevice';
import { BLE_EVENTS, BleDeviceEventData } from '../service/ProximityService';
import { ProximityBadge } from '../components/business/ProximityBadge';
import { estimateDistance, proximityLevelToLabel } from '../utils/ProximityUtils';
import { AUTO_NAV_DELAY, RSSI_HISTORY_MAX } from '../constants/AppConstants';
import { Logger } from '../utils/Logger';

/** 路由传参结构：完整设备快照通过路由参数传递，不再从 Service 层直接读取 */
interface DetailRouteParams {
  deviceId: string;
  deviceName: string;
  deviceSnapshot: string; // JSON 序列化的 BreadDevice 快照
}

/** RSSI 历史记录点 */
interface RssiPoint {
  rssi: number;
  ts: number;
}

@Entry
@Component
struct BreadDetailPage {
  // ─── 路由参数 ─────────────────────────────────────────────────
  private _deviceId: string = '';
  private _deviceName: string = '';

  // ─── 响应式状态 ───────────────────────────────────────────────
  @State private device: BreadDevice | null = null;
  @State private rssiHistory: RssiPoint[] = [];
  @State private isAutoClosing: boolean = false;
  @State private autoCloseCountdown: number = 0;
  @State private closeHint: string = '';

  // ─── 非响应式私有字段 ─────────────────────────────────────────
  private _autoCloseTimer: number = -1;
  private _countdownTimer: number = -1;
  /** 保存 listener 引用，用于精准注销（避免 emitter.off(id) 注销所有同 id 监听者） */
  private _listenerUpdated: ((event: emitter.EventData) => void) | null = null;
  private _listenerLost: ((event: emitter.EventData) => void) | null = null;

  // ─── 生命周期 ────────────────────────────────────────────────

  aboutToAppear(): void {
    const params = router.getParams() as DetailRouteParams;
    this._deviceId = params?.deviceId ?? '';
    this._deviceName = params?.deviceName ?? '未知设备';

    // 设备快照通过路由参数传入，不直接访问 ProximityService
    if (params?.deviceSnapshot) {
      try {
        const snap: BreadDevice = JSON.parse(params.deviceSnapshot) as BreadDevice;
        this.device = snap;
        this.rssiHistory = [{ rssi: snap.rssi, ts: snap.lastSeenAt }];
      } catch {
        Logger.warn('BreadDetailPage', 'Failed to parse device snapshot from params');
      }
    }

    this._registerEvents();
    Logger.info('BreadDetailPage', `Opened for device: ${this._deviceId}`);
  }

  aboutToDisappear(): void {
    this._unregisterEvents();
    this._clearTimers();
    Logger.info('BreadDetailPage', `Closed for device: ${this._deviceId}`);
  }

  // ─── BLE 事件监听 ─────────────────────────────────────────────

  private _registerEvents(): void {
    const onUpdated = (event: emitter.EventData): void => {
      const data = event.data as BleDeviceEventData;
      if (data.device.deviceId !== this._deviceId) {
        return;
      }
      this.device = data.device;
      // 追加 RSSI 历史，使用时间戳作为 ForEach key（避免下标全量重渲染）
      this.rssiHistory = [
        ...this.rssiHistory.slice(-(RSSI_HISTORY_MAX - 1)),
        { rssi: data.device.rssi, ts: data.device.lastSeenAt },
      ];
      // 设备重新靠近时取消自动关闭
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

    emitter.on({ eventId: BLE_EVENTS.DEVICE_UPDATED }, onUpdated);
    emitter.on({ eventId: BLE_EVENTS.DEVICE_LOST }, onLost);

    this._listenerUpdated = onUpdated;
    this._listenerLost = onLost;
  }

  private _unregisterEvents(): void {
    // 精准注销，不影响 ViewModel 等其他组件注册的同 eventId 监听
    if (this._listenerUpdated) {
      emitter.off(BLE_EVENTS.DEVICE_UPDATED, this._listenerUpdated);
      this._listenerUpdated = null;
    }
    if (this._listenerLost) {
      emitter.off(BLE_EVENTS.DEVICE_LOST, this._listenerLost);
      this._listenerLost = null;
    }
  }

  // ─── 自动关闭逻辑 ─────────────────────────────────────────────

  /**
   * 设备离开后启动倒计时，到期自动返回列表页
   * 期间显示倒计时提示，用户可手动取消
   */
  private _scheduleAutoClose(): void {
    if (this.isAutoClosing) {
      return;
    }
    this.isAutoClosing = true;
    this.autoCloseCountdown = Math.ceil(AUTO_NAV_DELAY.CLOSE_DEBOUNCE_MS / 1000);
    this.closeHint = `设备已离开，${this.autoCloseCountdown}s 后自动关闭`;

    // 每秒更新倒计时文本
    this._countdownTimer = setInterval(() => {
      this.autoCloseCountdown -= 1;
      this.closeHint = `设备已离开，${this.autoCloseCountdown}s 后自动关闭`;
    }, 1000);

    // 到期执行关闭
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
    Logger.info('BreadDetailPage', 'Auto close cancelled (device returned)');
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

  // ─── UI ──────────────────────────────────────────────────────

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
          // 距离展示为区间范围，避免单点精度误导用户（Minor#12）
          this._buildMetric('估算距离', this._formatDistanceRange(this.device?.rssi ?? -100))
        }
        GridItem() {
          this._buildMetric('近距离等级', proximityLevelToLabel(this.device?.proximityLevel ?? ProximityLevel.UNKNOWN))
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
            const normalized: number = Math.max(0,
              Math.min(1, (point.rssi + 100) / 70)
            );
            const barH: number = 10 + normalized * 50;
            Column()
              .width(8)
              .height(barH)
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
          // 使用时间戳作为 key，避免下标导致全量重渲染（fix Critical#6）
          (point: RssiPoint) => `${point.ts}`
        )
      }
      .width('100%')
      .height(70)
      .alignItems(VerticalAlign.Bottom)

      if (this.rssiHistory.length > 0) {
        Row() {
          Text(`最低: ${Math.min(...this.rssiHistory.map(p => p.rssi))} dBm`)
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
          Blank()
          Text(`最高: ${Math.max(...this.rssiHistory.map(p => p.rssi))} dBm`)
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

  /**
   * 将 RSSI 转换为区间字符串展示，降低路径损耗模型的精度误导（fix Minor#12）
   * 误差约 ±50%，因此以 0.5m 为步进展示区间
   */
  private _formatDistanceRange(rssi: number): string {
    const center: number = estimateDistance(rssi);
    const low: number = Math.max(0, center * 0.5);
    const high: number = center * 1.5;
    if (low < 1) {
      return `< ${high.toFixed(1)} m`;
    }
    return `${low.toFixed(1)} ~ ${high.toFixed(1)} m`;
  }
}
