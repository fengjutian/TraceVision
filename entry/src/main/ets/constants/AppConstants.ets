/**
 * @file    应用全局常量
 * @desc    BLE 扫描参数、近距离阈值、自动关闭延迟等常量定义
 * @author  TraceVision Team
 * @date    2026-03-24
 */

/** BLE 服务与扫描相关常量 */
export const BLE_CONSTANTS = {
  /** 面包设备广播服务 UUID（需与硬件对齐） */
  BREAD_SERVICE_UUID: '0000FFF0-0000-1000-8000-00805F9B34FB',
  /** BLE 扫描间隔（ms） */
  SCAN_INTERVAL_MS: 2000,
  /** 设备信号丢失超时（ms）：超过此时间未收到广播视为设备离开 */
  DEVICE_LOST_TIMEOUT_MS: 5000,
} as const;

/** RSSI 近距离阈值（dBm） */
export const PROXIMITY_THRESHOLD = {
  /** 近距离：RSSI >= -60 dBm，约 0~1m */
  NEAR: -60,
  /** 中距离：-60 > RSSI >= -80 dBm，约 1~3m */
  MEDIUM: -80,
  /** 远距离：RSSI < -80 dBm，3m 以上 */
  FAR: -100,
} as const;

/** 自动开关页面延迟（ms） */
export const AUTO_NAV_DELAY = {
  /** 靠近后延迟多少 ms 再自动打开详情页（防抖） */
  OPEN_DEBOUNCE_MS: 800,
  /** 离开后延迟多少 ms 再自动关闭详情页（防抖） */
  CLOSE_DEBOUNCE_MS: 3000,
} as const;

/** AppStorage 全局 Key（T50：用于持久化扫描开关状态） */
export const STORAGE_KEYS = {
  /** 扫描开关状态：boolean，true = 用户上次选择了开启扫描 */
  SCAN_ENABLED: 'scanEnabled',
} as const;

/** RSSI 历史记录最大条数（fix Major#7：常量化，不放在页面实例变量里） */
export const RSSI_HISTORY_MAX: number = 20;

/**
 * T54：面包设备私有 Manufacturer Data 协议常量
 * AD Type 0xFF，Company ID = 0xFFBB（小端序），协议版本 0x01
 */
export const BREAD_PROTOCOL = {
  /** Manufacturer Data Company ID（小端序两字节） */
  COMPANY_ID_LO: 0xFF,
  COMPANY_ID_HI: 0xBB,
  /** 当前支持的协议版本 */
  VERSION: 0x01,
  /** Manufacturer Data 最小有效字节长度（含 Company ID 2B + Version 1B） */
  MIN_LENGTH: 13,
  /** 温度等级映射 */
  TEMP_LEVEL: ['常温', '冷藏（4℃）', '冷冻（-18℃）'],
} as const;

/** 路由页面路径 */
export const ROUTES = {
  INDEX: 'pages/Index',
  BREAD_TRACK: 'pages/BreadTrackPage',
  BREAD_DETAIL: 'pages/BreadDetailPage',
} as const;
