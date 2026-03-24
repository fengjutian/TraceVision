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
import { BreadDevice, DeviceStatus, ProximityLevel, BreadBatchInfo } from '../model/BreadDevice';
import { rssiToProximityLevel, RssiKalmanFilter } from '../utils/ProximityUtils';
import { Logger } from '../utils/Logger';
import { BLE_CONSTANTS, BREAD_PROTOCOL } from '../constants/AppConstants';

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
  /** 各设备 RSSI 卡尔曼滤波器 Map，key = deviceId（T52） */
  private _kalmanFilters: Map<string, RssiKalmanFilter> = new Map();
  /** 设备超时检测定时器 */
  private _lostCheckTimer: number = -1;
  /** 当前是否正在扫描 */
  private _isScanning: boolean = false;
  /** BLEDeviceFind 回调引用，用于精准注销（fix L3） */
  private _bleDeviceFindListener: ((results: Array<ble.ScanResult>) => void) | null = null;

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

  /**
   * 停止 BLE 扫描，清理资源
   */
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
    this._kalmanFilters.clear(); // T52：清理滤波器状态，避免重启扫描后使用旧状态
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
      const rawRssi: number = result.rssi;
      const now: number = Date.now();

      // T52：卡尔曼滤波平滑 RSSI，减少信号抖动导致的等级误判
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
          ...existing,
          rssi,
          proximityLevel: level,
          status: DeviceStatus.ACTIVE,
          lastSeenAt: now,
        };
        this._devices.set(deviceId, updated);
        this._emit(BLE_EVENTS.DEVICE_UPDATED, updated);
        Logger.debug('ProximityService', `Device updated: ${deviceId} raw=${rawRssi} filtered=${rssi}`);
      } else {
        const deviceName: string = this._parseDeviceName(result.data) ??
          `Bread-${deviceId.slice(-5)}`;
        const advertiseData: string = this._parseAdvertiseData(result.data);
        const batchInfo = this._parseManufacturerData(result.data); // T54
        const newDevice: BreadDevice = {
          deviceId,
          name: deviceName,
          rssi,
          proximityLevel: level,
          status: DeviceStatus.ACTIVE,
          lastSeenAt: now,
          advertiseData,
          batchInfo: batchInfo ?? undefined,
        };
        this._devices.set(deviceId, newDevice);
        this._emit(BLE_EVENTS.DEVICE_FOUND, newDevice);
        Logger.info('ProximityService', `New device found: ${deviceId} level=${level}`);
        // T53：异步查询完整设备名（GAP 名称），覆盖广播包解析结果
        this._fetchRemoteDeviceName(deviceId);
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

  /**
   * T54：从 BLE 广播原始数据解析私有 Manufacturer Data（AD Type 0xFF）
   * 协议格式详见 BreadBatchInfo 接口注释
   * 解析失败或不符合协议版本时返回 null
   */
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
        // AD Type 0xFF: Manufacturer Specific Data
        if (type === 0xFF && len >= BREAD_PROTOCOL.MIN_LENGTH) {
          const lo = bytes[offset + 2];
          const hi = bytes[offset + 3];
          const version = bytes[offset + 4];
          // 校验 Company ID 和协议版本
          if (lo !== BREAD_PROTOCOL.COMPANY_ID_LO ||
              hi !== BREAD_PROTOCOL.COMPANY_ID_HI ||
              version !== BREAD_PROTOCOL.VERSION) {
            offset += 1 + len;
            continue;
          }
          // 批次号：6 字节 ASCII，去除 null padding
          const batchBytes = bytes.slice(offset + 5, offset + 11);
          const batchId = new TextDecoder('ascii')
            .decode(batchBytes)
            .replace(/\x00/g, '')
            .trim();
          // 生产日期：byte[11]=YYMM高4，byte[12]=MMDD低4（紧凑编码）
          const dateByte0 = bytes[offset + 11];
          const dateByte1 = bytes[offset + 12];
          const year = 2000 + (dateByte0 & 0xFF);
          const month = (dateByte1 >> 4) & 0x0F;
          const day = dateByte1 & 0x0F;
          const productDate = `${year}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;
          // 温度等级
          const tempIdx = bytes[offset + 13] ?? 0;
          const tempLevel = BREAD_PROTOCOL.TEMP_LEVEL[tempIdx] ?? '常温';
          // 保质天数
          const shelfDays = bytes[offset + 14] ?? 0;

          Logger.info('ProximityService',
            `BatchInfo parsed: id=${batchId} date=${productDate} temp=${tempLevel} shelf=${shelfDays}d`);
          return { batchId, productDate, tempLevel, shelfDays };
        }
        offset += 1 + len;
      }
    } catch {
      // 解析失败静默降级
    }
    return null;
  }

  /**
   * T53：异步查询设备 GAP 名称（比广播包 AD Type 更权威的完整名称）
   * 查询成功且名称非空时，更新内部 Map 并 emit DEVICE_UPDATED 通知上层刷新
   */
  private _fetchRemoteDeviceName(deviceId: string): void {
    try {
      ble.getRemoteDeviceName(deviceId).then((name: string) => {
        if (!name || name.trim().length === 0) {
          return;
        }
        const device = this._devices.get(deviceId);
        if (!device) {
          return; // 设备可能已被移除
        }
        const updated: BreadDevice = { ...device, name: name.trim() };
        this._devices.set(deviceId, updated);
        this._emit(BLE_EVENTS.DEVICE_UPDATED, updated);
        Logger.info('ProximityService', `Remote name fetched: ${deviceId} → "${name.trim()}"`);
      }).catch((e: Error) => {
        // 部分设备不支持 GAP 名称查询，静默忽略
        Logger.debug('ProximityService', `getRemoteDeviceName failed for ${deviceId}: ${e.message}`);
      });
    } catch (e) {
      Logger.debug('ProximityService', `getRemoteDeviceName exception: ${(e as Error).message}`);
    }
  }
}
