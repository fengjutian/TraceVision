/**
 * @file    后台长时任务管理工具
 * @desc    封装 HarmonyOS ContinuousTask API，在应用进入后台时保持 BLE 扫描不被系统挂起。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import wantAgent, { WantAgent } from '@ohos.app.ability.wantAgent';
import common from '@ohos.app.ability.common';
import { Logger } from './Logger';

export class BackgroundTaskManager {
  private static _isRunning: boolean = false;

  /**
   * 申请后台连续任务（进入后台时调用）
   */
  static startContinuousTask(context: common.UIAbilityContext): void {
    if (BackgroundTaskManager._isRunning) {
      return;
    }
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context.applicationInfo.name,
          abilityName: 'EntryAbility',
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };

    wantAgent.getWantAgent(wantAgentInfo).then((agent: WantAgent) => {
      backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.BLUETOOTH_INTERACTION,
        agent
      ).then(() => {
        BackgroundTaskManager._isRunning = true;
        Logger.info('BackgroundTaskManager', 'Continuous BLE task started');
      }).catch((e: Error) => {
        Logger.warn('BackgroundTaskManager', `Start BG task failed: ${e.message}`);
      });
    }).catch((e: Error) => {
      Logger.warn('BackgroundTaskManager', `getWantAgent failed: ${e.message}`);
    });
  }

  /**
   * 释放后台连续任务（回到前台时调用）
   */
  static stopContinuousTask(context: common.UIAbilityContext): void {
    if (!BackgroundTaskManager._isRunning) {
      return;
    }
    backgroundTaskManager.stopBackgroundRunning(context).then(() => {
      BackgroundTaskManager._isRunning = false;
      Logger.info('BackgroundTaskManager', 'Continuous BLE task stopped');
    }).catch((e: Error) => {
      Logger.warn('BackgroundTaskManager', `Stop BG task failed: ${e.message}`);
    });
  }

  static isRunning(): boolean {
    return BackgroundTaskManager._isRunning;
  }
}
