/**
 * @file    应用全局常量
 * @desc    BLE 扫描参数、近距离阈值、自动关闭延迟等常量定义
 * @author  TraceVision Team
 * @date    2026-03-24
 */

/** BLE 服务与扫描相关常量 */
export namespace BLE_CONSTANTS {
  export const BREAD_SERVICE_UUID: string = '0000FFF0-0000-1000-8000-00805F9B34FB';
  export const SCAN_INTERVAL_MS: number = 2000;
  export const DEVICE_LOST_TIMEOUT_MS: number = 5000;
}

/** RSSI 近距离阈值（dBm） */
export namespace PROXIMITY_THRESHOLD {
  export const NEAR: number = -60;
  export const MEDIUM: number = -80;
  export const FAR: number = -100;
}

/** 自动开关页面延迟（ms） */
export namespace AUTO_NAV_DELAY {
  export const OPEN_DEBOUNCE_MS: number = 800;
  export const CLOSE_DEBOUNCE_MS: number = 3000;
}

/** AppStorage 全局 Key */
export namespace STORAGE_KEYS {
  export const SCAN_ENABLED: string = 'scanEnabled';
}

/** RSSI 历史记录最大条数 */
export const RSSI_HISTORY_MAX: number = 20;

/** T54：面包设备私有 Manufacturer Data 协议常量 */
export namespace BREAD_PROTOCOL {
  export const COMPANY_ID_LO: number = 0xFF;
  export const COMPANY_ID_HI: number = 0xBB;
  export const VERSION: number = 0x01;
  export const MIN_LENGTH: number = 13;
  export const TEMP_LEVEL: string[] = ['常温', '冷藏（4℃）', '冷冻（-18℃）'];
}

/** 路由页面路径 */
export namespace ROUTES {
  export const INDEX: string = 'pages/Index';
  export const BREAD_TRACK: string = 'pages/BreadTrackPage';
  export const BREAD_DETAIL: string = 'pages/BreadDetailPage';
  export const FACE_GUARD: string = 'pages/FaceGuardPage';
}

/** 面部识别相关常量 */
export namespace FACE_GUARD_CONSTANTS {
  /** 摄像头采图帧间隔（ms），降低 CPU 占用 */
  export const CAPTURE_INTERVAL_MS: number = 500;
  /** 无人脸持续多久后判定"离开"（ms） */
  export const LEAVE_CONFIRM_MS: number = 3000;
  /** 检测到人脸持续多久后判定"靠近"（ms） */
  export const ARRIVE_CONFIRM_MS: number = 800;
  /** 亮屏保持时长：超时后再次熄屏（ms，0=永不超时） */
  export const SCREEN_ON_KEEP_MS: number = 0;
}
