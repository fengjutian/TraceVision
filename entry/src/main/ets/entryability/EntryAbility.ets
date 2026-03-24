/**
 * @file    应用 Ability 入口
 * @desc    Stage 模型 UIAbility，负责窗口初始化与路由启动；
 *          前后台切换时申请/释放 ContinuousTask，保持 BLE 后台扫描（T51）。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import UIAbility from '@ohos.app.ability.UIAbility';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import common from '@ohos.app.ability.common';
import { BackgroundTaskManager } from '../utils/BackgroundTaskManager';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    hilog.info(0xF001, 'TraceVision', 'EntryAbility onCreate');
  }

  onDestroy(): void {
    hilog.info(0xF001, 'TraceVision', 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0xF001, 'TraceVision', 'EntryAbility onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0xF001, 'TraceVision', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0xF001, 'TraceVision', 'loadContent success');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0xF001, 'TraceVision', 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0xF001, 'TraceVision', 'EntryAbility onForeground');
    // 回到前台：释放后台任务，由系统正常调度
    BackgroundTaskManager.stopContinuousTask(this.context as common.UIAbilityContext);
  }

  onBackground(): void {
    hilog.info(0xF001, 'TraceVision', 'EntryAbility onBackground');
    // 进入后台：申请 ContinuousTask 保持 BLE 扫描（T51）
    BackgroundTaskManager.startContinuousTask(this.context as common.UIAbilityContext);
  }
}

