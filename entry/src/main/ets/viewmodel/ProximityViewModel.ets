/**
 * @file    近距离追踪 ViewModel
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import emitter from '@ohos.events.emitter';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';
import { BreadDevice, DeviceStatus, ProximityLevel, ScanSession, AutoNavAction } from '../model/BreadDevice';
import { ProximityService, BLE_EVENTS, BleDeviceEventData, BleScanStateEventData } from '../service/ProximityService';
import { Logger } from '../utils/Logger';
import { AUTO_NAV_DELAY, STORAGE_KEYS } from '../constants/AppConstants';

export type AutoNavCallback = (action: AutoNavAction, device: BreadDevice) => void;

interface PermissionResult {
  granted: boolean;
  denied: boolean;
}

let _activeViewModel: ProximityViewModel | null = null;
export function getActiveViewModel(): ProximityViewModel | null {
  return _activeViewModel;
}

class ViewModelInternals {
  autoNavTimers: Map<string, number> = new Map();
  autoNavCallback: AutoNavCallback | null = null;
  service: ProximityService = ProximityService.getInstance();
  listenerFound: ((event: emitter.EventData) => void) | null = null;
  listenerUpdated: ((event: emitter.EventData) => void) | null = null;
  listenerLost: ((event: emitter.EventData) => void) | null = null;
  listenerScan: ((event: emitter.EventData) => void) | null = null;
}

@Observed
export class ProximityViewModel {
  devices: BreadDevice[] = [];
  scanSession: ScanSession = { isScanning: false, startedAt: null, error: null };
  hasPermission: boolean = false;
  permissionDenied: boolean = false;
  bluetoothEnabled: boolean = true;
  activeDeviceId: string | null = null;

  private readonly _internals: ViewModelInternals = new ViewModelInternals();

  async init(context: common.UIAbilityContext): Promise<void> {
    _activeViewModel = this;

    this.bluetoothEnabled = this._internals.service.isBluetoothEnabled();
    if (!this.bluetoothEnabled) {
      this.scanSession = {
        isScanning: false,
        startedAt: null,
        error: '蓝牙未开启，请先开启蓝牙',
      };
      Logger.warn('ProximityViewModel', 'Bluetooth is disabled');
      return;
    }

    const permResult: PermissionResult = await this._requestPermissionsWithDetail(context);
    this.hasPermission = permResult.granted;
    this.permissionDenied = permResult.denied;

    if (!this.hasPermission) {
      this.scanSession = {
        isScanning: false,
        startedAt: null,
        error: '蓝牙或位置权限未授权',
      };
      return;
    }
    this._registerBleEvents();
    const scanEnabled: boolean = AppStorage.get<boolean>(STORAGE_KEYS.SCAN_ENABLED) ?? true;
    if (scanEnabled) {
      this.startScan();
    }
  }

  async retryAfterSettings(context: common.UIAbilityContext): Promise<void> {
    this.bluetoothEnabled = this._internals.service.isBluetoothEnabled();
    if (!this.bluetoothEnabled) {
      this.scanSession = {
        isScanning: false,
        startedAt: null,
        error: '蓝牙未开启，请先开启蓝牙',
      };
      return;
    }
    if (!this.hasPermission) {
      await this.init(context);
      return;
    }
    if (!this.scanSession.isScanning) {
      this.startScan();
    }
  }

  openBluetoothSettings(context: common.UIAbilityContext): void {
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'bluetooth',
    };
    context.startAbility(want).catch((e: Error) => {
      Logger.warn('ProximityViewModel', `Open BT settings failed: ${e.message}`);
    });
  }

  openPermissionSettings(context: common.UIAbilityContext): void {
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: { 'pushParams': context.applicationInfo.name },
    };
    context.startAbility(want).catch((e: Error) => {
      Logger.warn('ProximityViewModel', `Open permission settings failed: ${e.message}`);
    });
  }

  destroy(): void {
    _activeViewModel = null;
    this.stopScan();
    this._unregisterBleEvents();
    this._clearAllAutoNavTimers();
    Logger.info('ProximityViewModel', 'Destroyed and cleaned up');
  }

  startScan(): void {
    if (!this.hasPermission) {
      Logger.warn('ProximityViewModel', 'Cannot scan: no permission');
      return;
    }
    AppStorage.setOrCreate<boolean>(STORAGE_KEYS.SCAN_ENABLED, true);
    this._internals.service.startScan();
  }

  stopScan(): void {
    AppStorage.setOrCreate<boolean>(STORAGE_KEYS.SCAN_ENABLED, false);
    this._internals.service.stopScan();
  }

  registerAutoNavCallback(cb: AutoNavCallback): void {
    this._internals.autoNavCallback = cb;
  }

  unregisterAutoNavCallback(): void {
    this._internals.autoNavCallback = null;
  }

  notifyDetailClosed(deviceId: string): void {
    if (this.activeDeviceId === deviceId) {
      this.activeDeviceId = null;
      Logger.info('ProximityViewModel', `activeDeviceId reset for ${deviceId}`);
    }
  }

  private _registerBleEvents(): void {
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

    emitter.on({ eventId: BLE_EVENTS['DEVICE_FOUND'] }, onFound);
    emitter.on({ eventId: BLE_EVENTS['DEVICE_UPDATED'] }, onUpdated);
    emitter.on({ eventId: BLE_EVENTS['DEVICE_LOST'] }, onLost);
    emitter.on({ eventId: BLE_EVENTS['SCAN_STATE'] }, onScan);

    this._internals.listenerFound = onFound;
    this._internals.listenerUpdated = onUpdated;
    this._internals.listenerLost = onLost;
    this._internals.listenerScan = onScan;
  }

  private _unregisterBleEvents(): void {
    if (this._internals.listenerFound) {
      emitter.off(BLE_EVENTS['DEVICE_FOUND'], this._internals.listenerFound);
      this._internals.listenerFound = null;
    }
    if (this._internals.listenerUpdated) {
      emitter.off(BLE_EVENTS['DEVICE_UPDATED'], this._internals.listenerUpdated);
      this._internals.listenerUpdated = null;
    }
    if (this._internals.listenerLost) {
      emitter.off(BLE_EVENTS['DEVICE_LOST'], this._internals.listenerLost);
      this._internals.listenerLost = null;
    }
    if (this._internals.listenerScan) {
      emitter.off(BLE_EVENTS['SCAN_STATE'], this._internals.listenerScan);
      this._internals.listenerScan = null;
    }
  }

  private _onDeviceFound(device: BreadDevice): void {
    const newList: BreadDevice[] = [];
    for (const d of this.devices) {
      newList.push(d);
    }
    newList.push(device);
    this.devices = newList;
    this._scheduleAutoOpen(device);
  }

  private _onDeviceUpdated(device: BreadDevice): void {
    this.devices = this.devices.map(d =>
      d.deviceId === device.deviceId ? device : d
    );
    if (device.proximityLevel === ProximityLevel.NEAR &&
        this.activeDeviceId !== device.deviceId) {
      this._scheduleAutoOpen(device);
    }
  }

  private _onDeviceLost(device: BreadDevice): void {
    this.devices = this.devices.map(d =>
      d.deviceId === device.deviceId ? device : d
    );
  }

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
      if (!latest ||
          latest.proximityLevel !== ProximityLevel.NEAR ||
          latest.status !== DeviceStatus.ACTIVE) {
        this._internals.autoNavTimers.delete(openKey);
        return;
      }
      if (this.activeDeviceId !== null && this.activeDeviceId !== device.deviceId) {
        const activeDevice = this.devices.find(d => d.deviceId === this.activeDeviceId);
        if (activeDevice &&
            activeDevice.status === DeviceStatus.ACTIVE &&
            activeDevice.rssi >= latest.rssi) {
          this._internals.autoNavTimers.delete(openKey);
          return;
        }
      }
      if (this.activeDeviceId !== device.deviceId) {
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

  private async _requestPermissionsWithDetail(
    context: common.UIAbilityContext
  ): Promise<PermissionResult> {
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
      const anyDenied: boolean = result.authResults.some(
        r => r !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
      );
      Logger.info('ProximityViewModel', `Permissions granted: ${granted}`);
      return { granted, denied: anyDenied && !granted };
    } catch (e) {
      Logger.error('ProximityViewModel', 'Permission request failed', e as Error);
      return { granted: false, denied: false };
    }
  }
}
