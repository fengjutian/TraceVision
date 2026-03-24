/**
 * @file    RSSI 近距离解析工具
 * @desc    将原始 RSSI 值转换为 ProximityLevel 枚举，提供距离估算
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import { ProximityLevel } from '../model/BreadDevice';
import { PROXIMITY_THRESHOLD } from '../constants/AppConstants';

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
 * @param rssi     - 当前 RSSI
 * @param txPower  - 设备标称发射功率（dBm），默认 -59
 * @returns        估算距离（米）
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
