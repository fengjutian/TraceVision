/**
 * @file    BLE 近距离感知服务
 * @desc    封装 HarmonyOS BLE 扫描 API，持续监听附近面包设备的 RSSI 变化，
 *          通过 EventHub 向上层广播设备发现、更新、丢失事件。
 *          核心职责：设备扫描、RSSI 解析、设备超时检测。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import ble from '@ohos.bluetooth.ble';
import access from '@ohos.bluetooth.access';
import { BusinessError } from '@ohos.base';
import emitter from '@ohos.events.emitter';
import { BreadDevice, DeviceStatus, ProximityLevel } from '../model/BreadDevice';
import { rssiToProximityLevel } from '../utils/ProximityUtils';
import { Logger } from '../utils/Logger';
import { BLE_CONSTANTS } from '../constants/AppConstants';

/** EventHub 事件 ID 常量 */
export const BLE_EVENTS = {
  DEVICE_FOUND:   1001,
  DEVICE_UPDATED: 1002,
  DEVICE_LOST:    1003,
  SCAN_STATE:     1004,
} as const;

/** BLE 扫描事件数据结构 */
export interface BleDeviceEventData {
  device: BreadDevice;
}

export interface BleScanStateEventData {
  isScanning: boolean;
  error?: string;
}

/**
 * BLE 近距离感知服务（单例）
 * 负责 BLE 扫描生命周期管理与设备状态维护
 */
export class ProximityService {
  private static _instance: ProximityService | null = null;

  /** 已发现设备 Map，key = deviceId */
  private _devices: Map<string, BreadDevice> = new Map();
  /** 设备超时检测定时器 */
  private _lostCheckTimer: number = -1;
  /** 当前是否正在扫描 */
  private _isScanning: boolean = false;

  private constructor() {}

  /** 获取单例 */
  static getInstance(): ProximityService {
    if (!ProximityService._instance) {
      ProximityService._instance = new ProximityService();
    }
    return ProximityService._instance;
  }

  /**
   * 启动 BLE 扫描
   * 需提前确认已获得 ACCESS_BLUETOOTH + LOCATION 权限
   */
  startScan(): void {
    if (this._isScanning) {
      Logger.warn('ProximityService', 'Already scanning, skip startScan');
      return;
    }

    try {
      const scanFilter: ble.ScanFilter[] = [
        { serviceUuid: BLE_CONSTANTS.BREAD_SERVICE_UUID },
      ];
      const scanOptions: ble.ScanOptions = {
        interval: BLE_CONSTANTS.SCAN_INTERVAL_MS,
        dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY,
        matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE,
      };

      ble.on('BLEDeviceFind', (results: Array<ble.ScanResult>) => {
        this._onScanResult(results);
      });

      ble.startBLEScan(scanFilter, scanOptions);
      this._isScanning = true;
      this._startLostCheck();

      Logger.info('ProximityService', 'BLE scan started');
      this._emitScanState(true);
    } catch (e) {
      const err = e as BusinessError;
      Logger.error('ProximityService', 'Failed to start BLE scan', err.message);
      this._emitScanState(false, err.message);
    }
  }

  /**
   * 停止 BLE 扫描，清理资源
   */
  stopScan(): void {
    if (!this._isScanning) {
      return;
    }
    try {
      ble.off('BLEDeviceFind');
      ble.stopBLEScan();
    } catch (e) {
      Logger.warn('ProximityService', 'stopBLEScan error (may be already stopped)');
    }
    this._isScanning = false;
    this._stopLostCheck();
    Logger.info('ProximityService', 'BLE scan stopped');
    this._emitScanState(false);
  }

  /** 获取当前全部设备快照 */
  getDevices(): BreadDevice[] {
    return Array.from(this._devices.values());
  }

  /** 检查蓝牙是否可用 */
  isBluetoothEnabled(): boolean {
    try {
      return access.getState() === access.BluetoothState.STATE_ON;
    } catch {
      return false;
    }
  }

  // ─── 私有方法 ────────────────────────────────────────────────

  private _onScanResult(results: Array<ble.ScanResult>): void {
    for (const result of results) {
      const deviceId: string = result.deviceId;
      const rssi: number = result.rssi;
      const level: ProximityLevel = rssiToProximityLevel(rssi);
      const now: number = Date.now();

      if (this._devices.has(deviceId)) {
        const existing: BreadDevice = this._devices.get(deviceId)!;
        const updated: BreadDevice = {
          ...existing,
          rssi,
          proximityLevel: level,
          status: DeviceStatus.ACTIVE,
          lastSeenAt: now,
        };
        this._devices.set(deviceId, updated);
        this._emit(BLE_EVENTS.DEVICE_UPDATED, updated);
        Logger.debug('ProximityService', `Device updated: ${deviceId} rssi=${rssi}`);
      } else {
        // fix Major#9：ScanResult 无 deviceName / serviceUuids 字段
        // 设备名从广播数据原始包尝试解析，解析失败时使用设备 ID 后缀作为降级名称
        const deviceName: string = this._parseDeviceName(result.data) ??
          `Bread-${deviceId.slice(-5)}`;
        const advertiseData: string = this._parseAdvertiseData(result.data);
        const newDevice: BreadDevice = {
          deviceId,
          name: deviceName,
          rssi,
          proximityLevel: level,
          status: DeviceStatus.ACTIVE,
          lastSeenAt: now,
          advertiseData,
        };
        this._devices.set(deviceId, newDevice);
        this._emit(BLE_EVENTS.DEVICE_FOUND, newDevice);
        Logger.info('ProximityService', `New device found: ${deviceId} level=${level}`);
      }
    }
  }

  /** 启动定时器周期检测设备是否超时丢失 */
  private _startLostCheck(): void {
    this._lostCheckTimer = setInterval(() => {
      const now: number = Date.now();
      this._devices.forEach((device: BreadDevice, id: string) => {
        if (device.status === DeviceStatus.ACTIVE &&
            now - device.lastSeenAt > BLE_CONSTANTS.DEVICE_LOST_TIMEOUT_MS) {
          const lost: BreadDevice = { ...device, status: DeviceStatus.LOST };
          this._devices.set(id, lost);
          this._emit(BLE_EVENTS.DEVICE_LOST, lost);
          Logger.info('ProximityService', `Device lost: ${id}`);
        }
      });
    }, BLE_CONSTANTS.DEVICE_LOST_TIMEOUT_MS / 2);
  }

  private _stopLostCheck(): void {
    if (this._lostCheckTimer !== -1) {
      clearInterval(this._lostCheckTimer);
      this._lostCheckTimer = -1;
    }
  }

  private _emit(eventId: number, device: BreadDevice): void {
    emitter.emit({ eventId }, { data: { device } as BleDeviceEventData });
  }

  private _emitScanState(isScanning: boolean, error?: string): void {
    const data: BleScanStateEventData = { isScanning, error };
    emitter.emit({ eventId: BLE_EVENTS.SCAN_STATE }, { data });
  }

  private _parseAdvertiseData(rawData: ArrayBuffer | undefined): string {
    // 将原始广播数据转为十六进制字符串，供上层展示
    if (!rawData || rawData.byteLength === 0) {
      return '';
    }
    try {
      const bytes = new Uint8Array(rawData);
      return Array.from(bytes)
        .map(b => b.toString(16).padStart(2, '0'))
        .join(' ')
        .toUpperCase();
    } catch {
      return '';
    }
  }

  /**
   * 从 BLE 广播原始数据中尝试解析 Complete/Shortened Local Name（AD Type 0x08/0x09）
   * 解析失败返回 null，由调用方使用降级名称
   */
  private _parseDeviceName(rawData: ArrayBuffer | undefined): string | null {
    if (!rawData || rawData.byteLength === 0) {
      return null;
    }
    try {
      const bytes = new Uint8Array(rawData);
      let offset = 0;
      while (offset + 1 < bytes.length) {
        const len = bytes[offset];
        if (len === 0) {
          break;
        }
        const type = bytes[offset + 1];
        // AD Type 0x08: Shortened Local Name / 0x09: Complete Local Name
        if ((type === 0x08 || type === 0x09) && len > 1) {
          const nameBytes = bytes.slice(offset + 2, offset + 1 + len);
          return new TextDecoder('utf-8').decode(nameBytes);
        }
        offset += 1 + len;
      }
    } catch {
      // 解析失败静默降级
    }
    return null;
  }
}
