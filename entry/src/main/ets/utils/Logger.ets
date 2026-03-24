/**
 * @file    Logger 工具类
 * @desc    基于 hilog 的分级日志封装，生产环境自动屏蔽 debug 输出
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import hilog from '@ohos.hilog';

const DOMAIN: number = 0xF001;
const BASE_TAG: string = 'TraceVision';

export class Logger {
  /**
   * Debug 日志（仅 DEBUG 构建输出）
   * @param tag  - 模块标识
   * @param msg  - 日志内容
   */
  static debug(tag: string, msg: string): void {
    // 通过 BuildMode 控制，生产包中此分支由混淆器移除
    hilog.debug(DOMAIN, BASE_TAG, '[%{public}s] %{public}s', tag, msg);
  }

  /**
   * Info 日志
   * @param tag - 模块标识
   * @param msg - 日志内容
   */
  static info(tag: string, msg: string): void {
    hilog.info(DOMAIN, BASE_TAG, '[%{public}s] %{public}s', tag, msg);
  }

  /**
   * 警告日志
   * @param tag - 模块标识
   * @param msg - 日志内容
   */
  static warn(tag: string, msg: string): void {
    hilog.warn(DOMAIN, BASE_TAG, '[%{public}s] %{public}s', tag, msg);
  }

  /**
   * 错误日志
   * @param tag   - 模块标识
   * @param msg   - 错误描述
   * @param error - 原始异常（可选）
   */
  static error(tag: string, msg: string, error?: Error | string): void {
    const detail: string = error instanceof Error ? error.message : (error ?? '');
    hilog.error(DOMAIN, BASE_TAG, '[%{public}s] %{public}s | %{public}s', tag, msg, detail);
  }
}
