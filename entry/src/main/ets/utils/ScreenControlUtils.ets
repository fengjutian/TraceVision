/**
 * @file    ScreenControlUtils.ets
 * @desc    屏幕控制工具：
 *          - 用户靠近：申请 RunningLock 阻止熄屏 + 恢复窗口亮度
 *          - 用户离开：将窗口亮度降为 0（视觉关屏）+ 释放 RunningLock
 *
 *          说明：鸿蒙普通应用无权调用 power.hibernate() 强制熄屏（需 system 级权限），
 *          因此采用 window.setWindowBrightness(0) 将窗口亮度降至最低来模拟"关屏"效果，
 *          同时释放唤醒锁让系统可按超时策略真正熄屏。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import runningLock from '@ohos.runningLock';
import window from '@ohos.window';
import display from '@ohos.display';
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base';
import { Logger } from './Logger';

const TAG: string = 'ScreenControlUtils';
const LOCK_NAME: string = 'FaceGuard_ScreenLock';
/** 窗口亮度范围：0.0（最暗/视觉关屏）~ 1.0（最亮）；-1 = 跟随系统 */
const BRIGHTNESS_OFF: number = 0.0;
const BRIGHTNESS_RESTORE: number = -1;

/** 屏幕控制工具（单例） */
class ScreenControlUtils {
  private static _instance: ScreenControlUtils | null = null;
  private _wakeLock: runningLock.RunningLock | null = null;

  static getInstance(): ScreenControlUtils {
    if (!ScreenControlUtils._instance) {
      ScreenControlUtils._instance = new ScreenControlUtils();
    }
    return ScreenControlUtils._instance;
  }

  /** 当前是否已持有唤醒锁 */
  get isScreenKeptOn(): boolean {
    return this._wakeLock !== null;
  }

  /**
   * 用户靠近：恢复窗口亮度（跟随系统）+ 申请唤醒锁，阻止系统自动熄屏。
   * @param context  - Ability 的 UIAbilityContext，用于获取当前窗口
   * @param timeoutMs - 唤醒锁持有时长（ms）；0 = 持有 1 小时直到主动释放
   */
  async keepScreenOn(context: common.UIAbilityContext, timeoutMs: number = 0): Promise<void> {
    // 1. 恢复窗口亮度为系统默认（-1 = 跟随系统亮度）
    await this._setWindowBrightness(context, BRIGHTNESS_RESTORE);

    // 2. 申请唤醒锁
    if (this._wakeLock) {
      Logger.info(TAG, 'Wake lock already held.');
      return;
    }
    try {
      const isSupported = await runningLock.isSupported(runningLock.RunningLockType.BACKGROUND);
      if (!isSupported) {
        Logger.info(TAG, 'RunningLock not supported on this device.');
        return;
      }
      this._wakeLock = await runningLock.create(LOCK_NAME, runningLock.RunningLockType.BACKGROUND);
      const holdMs: number = timeoutMs > 0 ? timeoutMs : 3600000;
      this._wakeLock.hold(holdMs);
      Logger.info(TAG, `Wake lock acquired, holdMs=${holdMs}.`);
    } catch (err) {
      const e = err as BusinessError;
      Logger.error(TAG, `Failed to acquire wake lock: ${e.message}`);
    }
  }

  /**
   * 用户离开：将窗口亮度降为 0（视觉关屏）+ 释放唤醒锁，让系统按超时策略真正熄屏。
   * @param context - Ability 的 UIAbilityContext，用于获取当前窗口
   */
  async turnScreenOff(context: common.UIAbilityContext): Promise<void> {
    // 1. 亮度降为 0 → 窗口立即变黑
    await this._setWindowBrightness(context, BRIGHTNESS_OFF);

    // 2. 释放唤醒锁，允许系统按超时策略真正熄屏
    await this._releaseWakeLock();
  }

  /**
   * 仅释放唤醒锁（不修改亮度），用于服务停止时清理资源。
   */
  async releaseScreenLock(): Promise<void> {
    await this._releaseWakeLock();
  }

  /**
   * 查询当前屏幕是否处于亮屏状态
   */
  isDisplayOn(): boolean {
    try {
      const defaultDisplay = display.getDefaultDisplaySync();
      return defaultDisplay.state === display.DisplayState.STATE_ON;
    } catch (err) {
      const e = err as BusinessError;
      Logger.error(TAG, `Failed to query display state: ${e.message}`);
      return false;
    }
  }

  // ─────────────────────────── 私有方法 ───────────────────────────

  /**
   * 设置当前窗口亮度
   * @param context   - UIAbilityContext
   * @param brightness - 0.0~1.0；-1 = 跟随系统
   */
  private async _setWindowBrightness(context: common.UIAbilityContext, brightness: number): Promise<void> {
    try {
      const win = await window.getLastWindow(context);
      await win.setWindowBrightness(brightness);
      Logger.info(TAG, `Window brightness set to ${brightness}.`);
    } catch (err) {
      const e = err as BusinessError;
      Logger.error(TAG, `Failed to set window brightness: ${e.message}`);
    }
  }

  /** 释放唤醒锁 */
  private async _releaseWakeLock(): Promise<void> {
    if (!this._wakeLock) {
      return;
    }
    try {
      this._wakeLock.unhold();
      this._wakeLock = null;
      Logger.info(TAG, 'Wake lock released.');
    } catch (err) {
      const e = err as BusinessError;
      Logger.error(TAG, `Failed to release wake lock: ${e.message}`);
    }
  }
}

export default ScreenControlUtils.getInstance();
