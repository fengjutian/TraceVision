/**
 * @file    近距离追踪 ViewModel
 * @desc    管理面包追踪页面的全部响应式状态，封装自动导航防抖逻辑。
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

/**
 * 面包追踪 ViewModel（每个页面实例持有一份）
 * 使用 @Observed 装饰，配合 @ObjectLink 实现细粒度更新
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

  /** 自动导航防抖定时器 Map，key = deviceId */
  private _autoNavTimers: Map<string, number> = new Map();
  /** 外部注册的自动导航回调 */
  private _autoNavCallback: AutoNavCallback | null = null;
  /** ProximityService 单例引用 */
  private _service: ProximityService = ProximityService.getInstance();

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
    this._service.startScan();
  }

  /** 停止 BLE 扫描 */
  stopScan(): void {
    this._service.stopScan();
  }

  /**
   * 注册自动导航回调（由页面在 aboutToAppear 中调用）
   * @param cb - 回调函数，接收 AutoNavAction 和触发设备
   */
  registerAutoNavCallback(cb: AutoNavCallback): void {
    this._autoNavCallback = cb;
  }

  /**
   * 取消注册自动导航回调（由页面在 aboutToDisappear 中调用）
   */
  unregisterAutoNavCallback(): void {
    this._autoNavCallback = null;
  }

  // ─── BLE 事件处理 ─────────────────────────────────────────────

  private _registerBleEvents(): void {
    emitter.on({ eventId: BLE_EVENTS.DEVICE_FOUND }, (event) => {
      const data = event.data as BleDeviceEventData;
      this._onDeviceFound(data.device);
    });
    emitter.on({ eventId: BLE_EVENTS.DEVICE_UPDATED }, (event) => {
      const data = event.data as BleDeviceEventData;
      this._onDeviceUpdated(data.device);
    });
    emitter.on({ eventId: BLE_EVENTS.DEVICE_LOST }, (event) => {
      const data = event.data as BleDeviceEventData;
      this._onDeviceLost(data.device);
    });
    emitter.on({ eventId: BLE_EVENTS.SCAN_STATE }, (event) => {
      const data = event.data as BleScanStateEventData;
      this.scanSession = {
        isScanning: data.isScanning,
        startedAt: data.isScanning ? Date.now() : null,
        error: data.error ?? null,
      };
    });
  }

  private _unregisterBleEvents(): void {
    emitter.off(BLE_EVENTS.DEVICE_FOUND);
    emitter.off(BLE_EVENTS.DEVICE_UPDATED);
    emitter.off(BLE_EVENTS.DEVICE_LOST);
    emitter.off(BLE_EVENTS.SCAN_STATE);
  }

  private _onDeviceFound(device: BreadDevice): void {
    this.devices = [...this.devices, device];
    this._scheduleAutoOpen(device);
  }

  private _onDeviceUpdated(device: BreadDevice): void {
    this.devices = this.devices.map(d =>
      d.deviceId === device.deviceId ? device : d
    );
    // 如果近距离等级变为 NEAR，尝试触发自动打开
    if (device.proximityLevel === ProximityLevel.NEAR &&
        this.activeDeviceId !== device.deviceId) {
      this._scheduleAutoOpen(device);
    }
  }

  private _onDeviceLost(device: BreadDevice): void {
    this.devices = this.devices.map(d =>
      d.deviceId === device.deviceId ? device : d
    );
    this._scheduleAutoClose(device);
  }

  // ─── 自动导航防抖逻辑 ─────────────────────────────────────────

  /**
   * 设备靠近时防抖调度自动打开
   * 防抖策略：若在 OPEN_DEBOUNCE_MS 内设备信号再次变远，取消打开
   */
  private _scheduleAutoOpen(device: BreadDevice): void {
    if (device.proximityLevel !== ProximityLevel.NEAR) {
      return;
    }
    // 清除同设备的关闭定时器（若有）
    this._cancelAutoNavTimer(device.deviceId + '_close');

    const timerId: number = setTimeout(() => {
      // 再次确认设备仍处于 NEAR 且 ACTIVE 状态
      const latest: BreadDevice | undefined = this.devices.find(
        d => d.deviceId === device.deviceId
      );
      if (latest?.proximityLevel === ProximityLevel.NEAR &&
          latest.status === DeviceStatus.ACTIVE &&
          this.activeDeviceId !== device.deviceId) {
        this.activeDeviceId = device.deviceId;
        Logger.info('ProximityViewModel', `Auto OPEN triggered for ${device.deviceId}`);
        this._autoNavCallback?.(AutoNavAction.OPEN, latest);
      }
      this._autoNavTimers.delete(device.deviceId + '_open');
    }, AUTO_NAV_DELAY.OPEN_DEBOUNCE_MS);

    this._autoNavTimers.set(device.deviceId + '_open', timerId);
  }

  /**
   * 设备离开时防抖调度自动关闭
   * 防抖策略：若在 CLOSE_DEBOUNCE_MS 内设备信号恢复，取消关闭
   */
  private _scheduleAutoClose(device: BreadDevice): void {
    if (this.activeDeviceId !== device.deviceId) {
      return;
    }
    // 清除同设备的打开定时器（若有）
    this._cancelAutoNavTimer(device.deviceId + '_open');

    const timerId: number = setTimeout(() => {
      // 再次确认设备仍处于 LOST 状态
      const latest: BreadDevice | undefined = this.devices.find(
        d => d.deviceId === device.deviceId
      );
      if (latest?.status === DeviceStatus.LOST &&
          this.activeDeviceId === device.deviceId) {
        this.activeDeviceId = null;
        Logger.info('ProximityViewModel', `Auto CLOSE triggered for ${device.deviceId}`);
        this._autoNavCallback?.(AutoNavAction.CLOSE, latest);
      }
      this._autoNavTimers.delete(device.deviceId + '_close');
    }, AUTO_NAV_DELAY.CLOSE_DEBOUNCE_MS);

    this._autoNavTimers.set(device.deviceId + '_close', timerId);
  }

  private _cancelAutoNavTimer(key: string): void {
    const timer: number | undefined = this._autoNavTimers.get(key);
    if (timer !== undefined) {
      clearTimeout(timer);
      this._autoNavTimers.delete(key);
    }
  }

  private _clearAllAutoNavTimers(): void {
    this._autoNavTimers.forEach((timerId: number) => clearTimeout(timerId));
    this._autoNavTimers.clear();
  }

  // ─── 权限申请 ─────────────────────────────────────────────────

  private async _requestPermissions(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, [
        'ohos.permission.ACCESS_BLUETOOTH',
        'ohos.permission.MANAGE_BLUETOOTH',
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
