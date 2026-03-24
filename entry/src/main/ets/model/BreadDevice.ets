/**
 * @file    数据模型定义
 * @desc    BLE 设备、近距离等级、追踪状态等核心数据模型
 * @author  TraceVision Team
 * @date    2026-03-24
 */

/** 近距离等级枚举 */
export enum ProximityLevel {
  NEAR = 'NEAR',
  MEDIUM = 'MEDIUM',
  FAR = 'FAR',
  UNKNOWN = 'UNKNOWN',
}

/** 设备连接状态 */
export enum DeviceStatus {
  ACTIVE = 'ACTIVE',    // 信号正常，设备在范围内
  LOST = 'LOST',        // 信号丢失，设备已离开
}

/** 面包追踪设备信息 */
export interface BreadDevice {
  /** 设备 MAC 地址，全局唯一标识 */
  deviceId: string;
  /** 设备广播名称 */
  name: string;
  /** 当前 RSSI 信号强度（dBm） */
  rssi: number;
  /** 近距离等级 */
  proximityLevel: ProximityLevel;
  /** 设备状态 */
  status: DeviceStatus;
  /** 最近一次信号更新时间（Unix ms） */
  lastSeenAt: number;
  /** 设备广播数据（可扩展解析面包批次信息） */
  advertiseData?: string;
}

/** 扫描会话状态 */
export interface ScanSession {
  isScanning: boolean;
  startedAt: number | null;
  error: string | null;
}

/** 自动导航动作类型 */
export enum AutoNavAction {
  OPEN = 'OPEN',
  CLOSE = 'CLOSE',
  NONE = 'NONE',
}
