/**
 * @file    RSSI 近距离解析工具
 * @desc    将原始 RSSI 值转换为 ProximityLevel 枚举，提供距离估算；
 *          包含一维卡尔曼滤波器，用于平滑 RSSI 波动，减少等级误触发（T52）。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import { ProximityLevel } from '../model/BreadDevice';
import { PROXIMITY_THRESHOLD } from '../constants/AppConstants';

/**
 * 一维卡尔曼滤波器（T52）
 * 用于平滑 BLE RSSI 信号波动，降低因短暂信号波动导致的等级误判
 *
 * 参数说明：
 *   R（测量噪声协方差）越大 → 越信任预测，滤波更平滑但响应更慢
 *   Q（过程噪声协方差）越大 → 越信任测量值，响应更快但平滑效果减弱
 */
export class RssiKalmanFilter {
  private _x: number;        // 状态估计值
  private _p: number;        // 估计误差协方差
  private readonly _q: number; // 过程噪声协方差
  private readonly _r: number; // 测量噪声协方差

  /**
   * @param initialRssi - 初始 RSSI 值（设备首次发现时的值）
   * @param q           - 过程噪声，默认 0.5（适中响应速度）
   * @param r           - 测量噪声，默认 3.0（BLE 典型波动为 ±3~5dBm）
   */
  constructor(initialRssi: number, q: number = 0.5, r: number = 3.0) {
    this._x = initialRssi;
    this._p = 1.0;
    this._q = q;
    this._r = r;
  }

  /**
   * 输入原始 RSSI，返回平滑后的 RSSI
   * @param measured - 当前帧原始测量值（dBm）
   */
  filter(measured: number): number {
    // 预测步骤
    this._p = this._p + this._q;
    // 更新步骤
    const k: number = this._p / (this._p + this._r); // 卡尔曼增益
    this._x = this._x + k * (measured - this._x);
    this._p = (1 - k) * this._p;
    return this._x;
  }

  /** 获取当前平滑值（不更新状态） */
  get value(): number {
    return this._x;
  }
}

/**
 * 根据 RSSI 值判断近距离等级
 * @param rssi - 蓝牙信号强度（dBm，负值，越接近 0 越强）
 * @returns    对应的 ProximityLevel
 */
export function rssiToProximityLevel(rssi: number): ProximityLevel {
  if (rssi >= PROXIMITY_THRESHOLD.NEAR) {
    return ProximityLevel.NEAR;
  }
  if (rssi >= PROXIMITY_THRESHOLD.MEDIUM) {
    return ProximityLevel.MEDIUM;
  }
  return ProximityLevel.FAR;
}

/**
 * 将 ProximityLevel 转换为可读中文描述
 * @param level - 近距离等级
 * @returns 中文描述字符串
 */
export function proximityLevelToLabel(level: ProximityLevel): string {
  const labelMap: Record<ProximityLevel, string> = {
    [ProximityLevel.NEAR]: '近距离（< 1m）',
    [ProximityLevel.MEDIUM]: '中距离（1~3m）',
    [ProximityLevel.FAR]: '远距离（> 3m）',
    [ProximityLevel.UNKNOWN]: '未知',
  };
  return labelMap[level] ?? '未知';
}

/**
 * 使用对数路径损耗模型估算设备距离（仅供参考）
 * @param rssi     - 当前 RSSI（建议传入滤波后的值）
 * @param txPower  - 设备标称发射功率（dBm），默认 -59
 * @returns        估算距离（米），rssi=0 时返回 -1
 */
export function estimateDistance(rssi: number, txPower: number = -59): number {
  if (rssi === 0) {
    return -1;
  }
  const ratio: number = rssi / txPower;
  if (ratio < 1.0) {
    return Math.pow(ratio, 10);
  }
  return 0.89976 * Math.pow(ratio, 7.7095) + 0.111;
}

