/**
 * @file    后台长时任务管理工具
 * @desc    封装 HarmonyOS ContinuousTask API，在应用进入后台时保持 BLE 扫描不被系统挂起。
 *          任务类型：bluetooth（蓝牙扫描），对应 module.json5 中 backgroundModes: ["bluetooth"]。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import common from '@ohos.app.ability.common';
import { Logger } from './Logger';

/** 后台任务通知 ID（需唯一，不与系统通知冲突） */
const BG_TASK_NOTIFICATION_ID: number = 1001;

export class BackgroundTaskManager {
  private static _isRunning: boolean = false;

  /**
   * 申请后台连续任务（进入后台时调用）
   * @param context - UIAbilityContext
   */
  static startContinuousTask(context: common.UIAbilityContext): void {
    if (BackgroundTaskManager._isRunning) {
      return;
    }
    try {
      const wantAgentInfo: backgroundTaskManager.WantAgentInfo = {
        wants: [{
          bundleName: context.applicationInfo.name,
          abilityName: 'EntryAbility',
        }],
        operationType: backgroundTaskManager.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [backgroundTaskManager.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };

      backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.BLUETOOTH_INTERACTION,
        wantAgentInfo
      ).then(() => {
        BackgroundTaskManager._isRunning = true;
        Logger.info('BackgroundTaskManager', 'Continuous BLE task started');
      }).catch((e: Error) => {
        Logger.warn('BackgroundTaskManager', `Start BG task failed: ${e.message}`);
      });
    } catch (e) {
      Logger.warn('BackgroundTaskManager', `startBackgroundRunning exception: ${(e as Error).message}`);
    }
  }

  /**
   * 释放后台连续任务（回到前台或停止扫描时调用）
   * @param context - UIAbilityContext
   */
  static stopContinuousTask(context: common.UIAbilityContext): void {
    if (!BackgroundTaskManager._isRunning) {
      return;
    }
    try {
      backgroundTaskManager.stopBackgroundRunning(context).then(() => {
        BackgroundTaskManager._isRunning = false;
        Logger.info('BackgroundTaskManager', 'Continuous BLE task stopped');
      }).catch((e: Error) => {
        Logger.warn('BackgroundTaskManager', `Stop BG task failed: ${e.message}`);
      });
    } catch (e) {
      Logger.warn('BackgroundTaskManager', `stopBackgroundRunning exception: ${(e as Error).message}`);
    }
  }

  /** 当前是否有后台任务在运行 */
  static isRunning(): boolean {
    return BackgroundTaskManager._isRunning;
  }
}
