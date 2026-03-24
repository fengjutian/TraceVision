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

/** AppStorage 全局 Key */
export const STORAGE_KEYS = {
  ACTIVE_BREAD_DEVICE_ID: 'activeBreadDeviceId',
  SCAN_ENABLED: 'scanEnabled',
} as const;

/** RSSI 历史记录最大条数（fix Major#7：常量化，不放在页面实例变量里） */
export const RSSI_HISTORY_MAX: number = 20;

/** 路由页面路径 */
export const ROUTES = {
  INDEX: 'pages/Index',
  BREAD_TRACK: 'pages/BreadTrackPage',
  BREAD_DETAIL: 'pages/BreadDetailPage',
} as const;
