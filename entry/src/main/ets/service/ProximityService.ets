/**
 * @file    BLE 近距离感知服务
 * @desc    封装 HarmonyOS BLE 扫描 API，持续监听附近面包设备的 RSSI 变化，
 *          通过 emitter 向上层广播设备发现、更新、丢失事件。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import ble from '@ohos.bluetooth.ble';
import access from '@ohos.bluetooth.access';
import { BusinessError } from '@ohos.base';
import emitter from '@ohos.events.emitter';
import util from '@ohos.util';
import { BreadDevice, DeviceStatus, ProximityLevel, BreadBatchInfo } from '../model/BreadDevice';
import { rssiToProximityLevel, RssiKalmanFilter } from '../utils/ProximityUtils';
import { Logger } from '../utils/Logger';
import { BLE_CONSTANTS, BREAD_PROTOCOL } from '../constants/AppConstants';

/** EventHub 事件 ID 常量 */
export namespace BLE_EVENTS {
  export const DEVICE_FOUND:   number = 1001;
  export const DEVICE_UPDATED: number = 1002;
  export const DEVICE_LOST:    number = 1003;
  export const SCAN_STATE:     number = 1004;
}

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
 */
export class ProximityService {
  private static _instance: ProximityService | null = null;

  private _devices: Map<string, BreadDevice> = new Map();
  private _kalmanFilters: Map<string, RssiKalmanFilter> = new Map();
  private _lostCheckTimer: number = -1;
  private _isScanning: boolean = false;
  private _bleDeviceFindListener: ((results: Array<ble.ScanResult>) => void) | null = null;

  private constructor() {}

  static getInstance(): ProximityService {
    if (!ProximityService._instance) {
      ProximityService._instance = new ProximityService();
    }
    return ProximityService._instance;
  }

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

      const onDeviceFind = (results: Array<ble.ScanResult>): void => {
        this._onScanResult(results);
      };
      this._bleDeviceFindListener = onDeviceFind;
      ble.on('BLEDeviceFind', onDeviceFind);
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

  stopScan(): void {
    if (!this._isScanning) {
      return;
    }
    try {
      if (this._bleDeviceFindListener) {
        ble.off('BLEDeviceFind', this._bleDeviceFindListener);
        this._bleDeviceFindListener = null;
      } else {
        ble.off('BLEDeviceFind');
      }
      ble.stopBLEScan();
    } catch (e) {
      Logger.warn('ProximityService', 'stopBLEScan error (may be already stopped)');
    }
    this._isScanning = false;
    this._stopLostCheck();
    this._kalmanFilters.clear();
    Logger.info('ProximityService', 'BLE scan stopped');
    this._emitScanState(false);
  }

  getDevices(): BreadDevice[] {
    return Array.from(this._devices.values());
  }

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
      const rawRssi: number = result.rssi;
      const now: number = Date.now();

      let filter = this._kalmanFilters.get(deviceId);
      if (!filter) {
        filter = new RssiKalmanFilter(rawRssi);
        this._kalmanFilters.set(deviceId, filter);
      }
      const rssi: number = Math.round(filter.filter(rawRssi));
      const level: ProximityLevel = rssiToProximityLevel(rssi);

      if (this._devices.has(deviceId)) {
        const existing: BreadDevice = this._devices.get(deviceId)!;
        const updated: BreadDevice = {
          deviceId: existing.deviceId,
          name: existing.name,
          rssi: rssi,
          proximityLevel: level,
          status: DeviceStatus.ACTIVE,
          lastSeenAt: now,
          advertiseData: existing.advertiseData,
          batchInfo: existing.batchInfo,
        };
        this._devices.set(deviceId, updated);
        this._emit(BLE_EVENTS.DEVICE_UPDATED, updated);
      } else {
        const deviceName: string = this._parseDeviceName(result.data) ?? `Bread-${deviceId.slice(-5)}`;
        const advertiseData: string = this._parseAdvertiseData(result.data);
        const batchInfo: BreadBatchInfo | null = this._parseManufacturerData(result.data);
        const newDevice: BreadDevice = {
          deviceId: deviceId,
          name: deviceName,
          rssi: rssi,
          proximityLevel: level,
          status: DeviceStatus.ACTIVE,
          lastSeenAt: now,
          advertiseData: advertiseData,
          batchInfo: batchInfo ?? undefined,
        };
        this._devices.set(deviceId, newDevice);
        this._emit(BLE_EVENTS.DEVICE_FOUND, newDevice);
        Logger.info('ProximityService', `New device found: ${deviceId} level=${level}`);
        this._fetchRemoteDeviceName(deviceId);
      }
    }
  }

  private _startLostCheck(): void {
    this._lostCheckTimer = setInterval(() => {
      const now: number = Date.now();
      this._devices.forEach((device: BreadDevice, id: string) => {
        if (device.status === DeviceStatus.ACTIVE &&
            now - device.lastSeenAt > BLE_CONSTANTS.DEVICE_LOST_TIMEOUT_MS) {
          const lost: BreadDevice = {
            deviceId: device.deviceId,
            name: device.name,
            rssi: device.rssi,
            proximityLevel: device.proximityLevel,
            status: DeviceStatus.LOST,
            lastSeenAt: device.lastSeenAt,
            advertiseData: device.advertiseData,
            batchInfo: device.batchInfo,
          };
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
    if (!rawData || rawData.byteLength === 0) {
      return '';
    }
    try {
      const bytes = new Uint8Array(rawData);
      const parts: string[] = [];
      bytes.forEach((b: number) => {
        parts.push(b.toString(16).padStart(2, '0'));
      });
      return parts.join(' ').toUpperCase();
    } catch {
      return '';
    }
  }

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
        if ((type === 0x08 || type === 0x09) && len > 1) {
          const nameBytes = bytes.slice(offset + 2, offset + 1 + len);
          const decoder = util.TextDecoder.create('utf-8');
          return decoder.decodeWithStream(nameBytes);
        }
        offset += 1 + len;
      }
    } catch {
      // 静默降级
    }
    return null;
  }

  private _parseManufacturerData(rawData: ArrayBuffer | undefined): BreadBatchInfo | null {
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
        if (type === 0xFF && len >= BREAD_PROTOCOL.MIN_LENGTH) {
          const lo = bytes[offset + 2];
          const hi = bytes[offset + 3];
          const version = bytes[offset + 4];
          if (lo !== BREAD_PROTOCOL.COMPANY_ID_LO ||
              hi !== BREAD_PROTOCOL.COMPANY_ID_HI ||
              version !== BREAD_PROTOCOL.VERSION) {
            offset += 1 + len;
            continue;
          }
          const batchBytes = bytes.slice(offset + 5, offset + 11);
          const decoder = util.TextDecoder.create('utf-8');
          const batchId = decoder.decodeWithStream(batchBytes).replace(/\x00/g, '').trim();
          const dateByte0 = bytes[offset + 11];
          const dateByte1 = bytes[offset + 12];
          const year = 2000 + (dateByte0 & 0xFF);
          const month = (dateByte1 >> 4) & 0x0F;
          const day = dateByte1 & 0x0F;
          const productDate = `${year}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;
          const tempIdx = bytes[offset + 13] ?? 0;
          const tempLevel = BREAD_PROTOCOL.TEMP_LEVEL[tempIdx] ?? '常温';
          const shelfDays = bytes[offset + 14] ?? 0;
          return { batchId, productDate, tempLevel, shelfDays };
        }
        offset += 1 + len;
      }
    } catch {
      // 静默降级
    }
    return null;
  }

  private _fetchRemoteDeviceName(deviceId: string): void {
    // ble.getRemoteDeviceName 在当前 API 版本需要先建立 GATT 连接，
    // 此处静默跳过，设备名由广播包解析结果提供
    Logger.debug('ProximityService', `Skip remote name fetch for ${deviceId} (requires GATT)`);
  }
}
