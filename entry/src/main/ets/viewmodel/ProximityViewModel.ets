/**
 * @file    近距离追踪 ViewModel
 * @desc    管理面包追踪页面的全部响应式状态，封装自动打开防抖逻辑。
 *          自动关闭逻辑由 BreadDetailPage 独立处理，ViewModel 只维护列表状态。
 *          展示层只调用此 ViewModel，不直接操作 ProximityService。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import emitter from '@ohos.events.emitter';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import { BreadDevice, DeviceStatus, ProximityLevel, ScanSession, AutoNavAction } from '../model/BreadDevice';
import { ProximityService, BLE_EVENTS, BleDeviceEventData, BleScanStateEventData } from '../service/ProximityService';
import { Logger } from '../utils/Logger';
import { AUTO_NAV_DELAY } from '../constants/AppConstants';

/** 自动导航回调函数类型 */
export type AutoNavCallback = (action: AutoNavAction, device: BreadDevice) => void;

// ─── 非响应式辅助类（不能放在 @Observed 里的私有状态） ─────────────────────
class ViewModelInternals {
  /** 自动打开防抖定时器 Map，key = deviceId + '_open' */
  autoNavTimers: Map<string, number> = new Map();
  /** 外部注册的自动导航回调 */
  autoNavCallback: AutoNavCallback | null = null;
  /** ProximityService 单例引用 */
  service: ProximityService = ProximityService.getInstance();
  /** emitter listener 引用，用于精准注销 */
  listenerFound: ((event: emitter.EventData) => void) | null = null;
  listenerUpdated: ((event: emitter.EventData) => void) | null = null;
  listenerLost: ((event: emitter.EventData) => void) | null = null;
  listenerScan: ((event: emitter.EventData) => void) | null = null;
}

/**
 * 面包追踪 ViewModel（每个页面实例持有一份）
 * 使用 @Observed 装饰，仅包含 UI 响应式字段，配合 @ObjectLink 实现细粒度更新
 */
@Observed
export class ProximityViewModel {
  /** 当前扫描到的全部设备列表 */
  devices: BreadDevice[] = [];
  /** 扫描会话状态 */
  scanSession: ScanSession = { isScanning: false, startedAt: null, error: null };
  /** 权限是否已授权 */
  hasPermission: boolean = false;
  /** 当前自动打开的设备 ID（null 表示无） */
  activeDeviceId: string | null = null;

  /** 非响应式私有状态（Map / callback / service 等不应放在 @Observed 类里） */
  private readonly _internals: ViewModelInternals = new ViewModelInternals();

  // ─── 生命周期 ─────────────────────────────────────────────────

  /**
   * 初始化：请求权限 → 注册事件 → 自动启动扫描
   * @param context - Ability 上下文，用于权限申请
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    this.hasPermission = await this._requestPermissions(context);
    if (!this.hasPermission) {
      this.scanSession = { ...this.scanSession, error: '蓝牙或位置权限未授权' };
      return;
    }
    this._registerBleEvents();
    this.startScan();
  }

  /**
   * 销毁：停止扫描、注销事件、清理定时器
   */
  destroy(): void {
    this.stopScan();
    this._unregisterBleEvents();
    this._clearAllAutoNavTimers();
    Logger.info('ProximityViewModel', 'Destroyed and cleaned up');
  }

  // ─── 公开操作 ─────────────────────────────────────────────────

  /** 启动 BLE 扫描 */
  startScan(): void {
    if (!this.hasPermission) {
      Logger.warn('ProximityViewModel', 'Cannot scan: no permission');
      return;
    }
    this._internals.service.startScan();
  }

  /** 停止 BLE 扫描 */
  stopScan(): void {
    this._internals.service.stopScan();
  }

  /**
   * 注册自动导航回调（由页面在 aboutToAppear 中调用）
   * @param cb - 回调函数，接收 AutoNavAction 和触发设备
   */
  registerAutoNavCallback(cb: AutoNavCallback): void {
    this._internals.autoNavCallback = cb;
  }

  /**
   * 取消注册自动导航回调（由页面在 aboutToDisappear 中调用）
   */
  unregisterAutoNavCallback(): void {
    this._internals.autoNavCallback = null;
  }

  /**
   * 详情页关闭时通知 ViewModel 重置 activeDeviceId
   * 确保下次同设备靠近仍能触发自动打开
   */
  notifyDetailClosed(deviceId: string): void {
    if (this.activeDeviceId === deviceId) {
      this.activeDeviceId = null;
      Logger.info('ProximityViewModel', `activeDeviceId reset for ${deviceId}`);
    }
  }

  // ─── BLE 事件处理 ─────────────────────────────────────────────

  private _registerBleEvents(): void {
    // 保存每个 listener 引用，供精准注销使用（fix: emitter.off(id) 会注销所有同 id 监听者）
    const onFound = (event: emitter.EventData): void => {
      const data = event.data as BleDeviceEventData;
      this._onDeviceFound(data.device);
    };
    const onUpdated = (event: emitter.EventData): void => {
      const data = event.data as BleDeviceEventData;
      this._onDeviceUpdated(data.device);
    };
    const onLost = (event: emitter.EventData): void => {
      const data = event.data as BleDeviceEventData;
      this._onDeviceLost(data.device);
    };
    const onScan = (event: emitter.EventData): void => {
      const data = event.data as BleScanStateEventData;
      this.scanSession = {
        isScanning: data.isScanning,
        startedAt: data.isScanning ? Date.now() : null,
        error: data.error ?? null,
      };
    };

    emitter.on({ eventId: BLE_EVENTS.DEVICE_FOUND }, onFound);
    emitter.on({ eventId: BLE_EVENTS.DEVICE_UPDATED }, onUpdated);
    emitter.on({ eventId: BLE_EVENTS.DEVICE_LOST }, onLost);
    emitter.on({ eventId: BLE_EVENTS.SCAN_STATE }, onScan);

    this._internals.listenerFound = onFound;
    this._internals.listenerUpdated = onUpdated;
    this._internals.listenerLost = onLost;
    this._internals.listenerScan = onScan;
  }

  private _unregisterBleEvents(): void {
    // 精准注销：只移除本实例注册的 listener，不影响其他页面的监听者
    if (this._internals.listenerFound) {
      emitter.off(BLE_EVENTS.DEVICE_FOUND, this._internals.listenerFound);
      this._internals.listenerFound = null;
    }
    if (this._internals.listenerUpdated) {
      emitter.off(BLE_EVENTS.DEVICE_UPDATED, this._internals.listenerUpdated);
      this._internals.listenerUpdated = null;
    }
    if (this._internals.listenerLost) {
      emitter.off(BLE_EVENTS.DEVICE_LOST, this._internals.listenerLost);
      this._internals.listenerLost = null;
    }
    if (this._internals.listenerScan) {
      emitter.off(BLE_EVENTS.SCAN_STATE, this._internals.listenerScan);
      this._internals.listenerScan = null;
    }
  }

  private _onDeviceFound(device: BreadDevice): void {
    this.devices = [...this.devices, device];
    this._scheduleAutoOpen(device);
  }

  private _onDeviceUpdated(device: BreadDevice): void {
    this.devices = this.devices.map(d =>
      d.deviceId === device.deviceId ? device : d
    );
    // 近距离等级变为 NEAR，且当前不是已激活设备时，尝试触发自动打开
    if (device.proximityLevel === ProximityLevel.NEAR &&
        this.activeDeviceId !== device.deviceId) {
      this._scheduleAutoOpen(device);
    }
  }

  private _onDeviceLost(device: BreadDevice): void {
    // 只更新列表状态；自动关闭导航由 BreadDetailPage 自行处理
    this.devices = this.devices.map(d =>
      d.deviceId === device.deviceId ? device : d
    );
  }

  // ─── 自动打开防抖逻辑 ─────────────────────────────────────────

  /**
   * 设备靠近时防抖调度自动打开
   * 防抖策略：若在 OPEN_DEBOUNCE_MS 内设备信号再次变远，取消打开
   */
  private _scheduleAutoOpen(device: BreadDevice): void {
    if (device.proximityLevel !== ProximityLevel.NEAR) {
      return;
    }

    const openKey: string = device.deviceId + '_open';
    this._cancelAutoNavTimer(openKey);

    const timerId: number = setTimeout(() => {
      const latest: BreadDevice | undefined = this.devices.find(
        d => d.deviceId === device.deviceId
      );
      if (latest?.proximityLevel === ProximityLevel.NEAR &&
          latest.status === DeviceStatus.ACTIVE &&
          this.activeDeviceId !== device.deviceId) {
        this.activeDeviceId = device.deviceId;
        Logger.info('ProximityViewModel', `Auto OPEN triggered for ${device.deviceId}`);
        this._internals.autoNavCallback?.(AutoNavAction.OPEN, latest);
      }
      this._internals.autoNavTimers.delete(openKey);
    }, AUTO_NAV_DELAY.OPEN_DEBOUNCE_MS);

    this._internals.autoNavTimers.set(openKey, timerId);
  }

  private _cancelAutoNavTimer(key: string): void {
    const timer: number | undefined = this._internals.autoNavTimers.get(key);
    if (timer !== undefined) {
      clearTimeout(timer);
      this._internals.autoNavTimers.delete(key);
    }
  }

  private _clearAllAutoNavTimers(): void {
    this._internals.autoNavTimers.forEach((timerId: number) => clearTimeout(timerId));
    this._internals.autoNavTimers.clear();
  }

  // ─── 权限申请 ─────────────────────────────────────────────────

  private async _requestPermissions(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, [
        'ohos.permission.ACCESS_BLUETOOTH',
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION',
      ]);
      const granted: boolean = result.authResults.every(
        r => r === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
      );
      Logger.info('ProximityViewModel', `Permissions granted: ${granted}`);
      return granted;
    } catch (e) {
      Logger.error('ProximityViewModel', 'Permission request failed', e as Error);
      return false;
    }
  }
}
