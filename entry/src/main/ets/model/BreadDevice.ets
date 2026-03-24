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
  /** 当前 RSSI 信号强度（dBm，卡尔曼滤波后的值） */
  rssi: number;
  /** 近距离等级 */
  proximityLevel: ProximityLevel;
  /** 设备状态 */
  status: DeviceStatus;
  /** 最近一次信号更新时间（Unix ms） */
  lastSeenAt: number;
  /** 设备广播数据（原始十六进制字符串，供调试） */
  advertiseData?: string;
  /** T54：解析出的面包批次信息（Manufacturer Data 协议） */
  batchInfo?: BreadBatchInfo;
}

/**
 * T54：面包批次信息（从 BLE Manufacturer Data 解析）
 *
 * 私有协议格式（AD Type 0xFF）：
 *   Byte 0-1 : Company ID（固定 0xFFBB，小端序）
 *   Byte 2   : 协议版本（当前 0x01）
 *   Byte 3-8 : 批次号（6 字节 ASCII，不足补 0x00）
 *   Byte 9-10: 生产日期（YYMMDD 紧凑编码：年低8位、月高4+日低4）
 *   Byte 11  : 温度等级（0=常温 / 1=冷藏 / 2=冷冻）
 *   Byte 12  : 保质天数（0~255）
 */
export interface BreadBatchInfo {
  /** 批次号，如 "B240301" */
  batchId: string;
  /** 生产日期，格式 YYYY-MM-DD */
  productDate: string;
  /** 温度等级描述 */
  tempLevel: string;
  /** 保质天数 */
  shelfDays: number;
}

/** 扫描会话状态 */
export interface ScanSession {
  isScanning: boolean;
  startedAt: number | null;
  error: string | null;
}

/** 自动导航动作类型（ViewModel 仅产生 OPEN，自动关闭由 BreadDetailPage 独立处理） */
export enum AutoNavAction {
  OPEN = 'OPEN',
}
