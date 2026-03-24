/**
 * @file    FaceProximityViewModel.ets
 * @desc    面部识别状态管理 ViewModel。
 *          负责：权限申请 → 启动 FaceDetectionService → 订阅检测事件 →
 *          控制 ScreenControlUtils → 向 UI 暴露可观测状态。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import emitter from '@ohos.events.emitter';
import Want from '@ohos.app.ability.Want';
import { BusinessError } from '@ohos.base';
import common from '@ohos.app.ability.common';
import { FACE_GUARD_CONSTANTS } from '../constants/AppConstants';
import FaceDetectionService, {
  FACE_DETECTED_EVENT_ID,
  FACE_LOST_EVENT_ID,
  FACE_SERVICE_STATE_EVENT_ID,
  FaceDetectResult,
  FaceServiceState,
  FaceServiceStateData,
} from '../service/FaceDetectionService';
import ScreenControlUtils from '../utils/ScreenControlUtils';
import { Logger } from '../utils/Logger';

const TAG: string = 'FaceProximityViewModel';

/** 用户在场状态 */
export enum PresenceState {
  UNKNOWN = 'UNKNOWN',
  PRESENT = 'PRESENT',
  ABSENT = 'ABSENT',
}

@Observed
export class FaceProximityViewModel {
  /** 摄像头权限状态 */
  hasPermission: boolean = false;
  /** 权限被拒绝（用于引导用户去设置页） */
  permissionDenied: boolean = false;
  /** 服务是否正在运行 */
  isServiceRunning: boolean = false;
  /** 当前用户在场状态 */
  presenceState: PresenceState = PresenceState.UNKNOWN;
  /** 服务错误信息（空字符串表示无错误） */
  errorMessage: string = '';
  /** 已检测到人脸次数（统计） */
  detectedCount: number = 0;
  /** 上次检测时间戳（ms） */
  lastDetectTime: number = 0;
  /** 当前帧中检测到的人脸数量（0 表示无人脸） */
  faceCount: number = 0;
  /** 当前人脸检测置信度 0.0~1.0 */
  faceConfidence: number = 0.0;
  /** 摄像头预览 SurfaceId（由 XComponent 回调后设置） */
  surfaceId: string = '';
  /** 服务状态 */
  serviceState: FaceServiceState = FaceServiceState.IDLE;
  /** 摄像头实际预览宽度（用于 UI 计算宽高比，0 表示未知） */
  previewWidth: number = 0;
  /** 摄像头实际预览高度（用于 UI 计算宽高比，0 表示未知） */
  previewHeight: number = 0;

  private _context: common.UIAbilityContext | null = null;

  /**
   * 初始化：申请摄像头权限
   * @param context - UIAbility 上下文
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    this._context = context;
    await this._requestCameraPermission();
  }

  /**
   * 在获取到 SurfaceId 后启动摄像头检测服务
   * @param surfaceId - XComponent 返回的 surfaceId
   */
  async startService(surfaceId: string): Promise<void> {
    if (!this.hasPermission) {
      Logger.info(TAG, 'No camera permission, cannot start service.');
      return;
    }
    if (this.isServiceRunning) {
      return;
    }
    this.surfaceId = surfaceId;
    this._registerEvents();
    try {
      await FaceDetectionService.start(this._context!, surfaceId);
      this.isServiceRunning = true;
      this.errorMessage = '';
      // 读取实际选取的预览尺寸，供 UI 正确设置 XComponent 宽高比
      this.previewWidth = FaceDetectionService.previewWidth;
      this.previewHeight = FaceDetectionService.previewHeight;
      Logger.info(TAG, 'FaceDetectionService started via ViewModel.');
    } catch (err) {
      const e = err as BusinessError;
      this.errorMessage = `启动失败：${e.message}`;
      Logger.error(TAG, `Start service failed: ${e.message}`);
    }
  }

  /** 停止检测服务并释放屏幕锁 */
  async stopService(): Promise<void> {
    this._unregisterEvents();
    await FaceDetectionService.stop();
    await ScreenControlUtils.releaseScreenLock();
    this.isServiceRunning = false;
    this.presenceState = PresenceState.UNKNOWN;
    this.faceCount = 0;
    this.faceConfidence = 0.0;
    Logger.info(TAG, 'FaceDetectionService stopped via ViewModel.');
  }

  /** 前往应用权限设置页 */
  openPermissionSettings(): void {
    if (!this._context) {
      return;
    }
    const settingsWant: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: {
        pushParams: 'com.tracevision.app',
      },
    };
    this._context.startAbility(settingsWant).catch((err: BusinessError) => {
      Logger.error(TAG, `Open settings failed: ${err.message}`);
    });
  }

  /** 从设置页返回后重新检查权限 */
  async retryAfterSettings(): Promise<void> {
    await this._requestCameraPermission();
  }

  // ─────────────────────────── 私有方法 ───────────────────────────

  /** 动态申请摄像头权限 */
  private async _requestCameraPermission(): Promise<void> {
    if (!this._context) {
      return;
    }
    const permissions: Permissions[] = ['ohos.permission.CAMERA'];
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(this._context, permissions);
      const granted = result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      this.hasPermission = granted;
      this.permissionDenied = !granted;
      Logger.info(TAG, `Camera permission granted=${granted}`);
    } catch (err) {
      const e = err as BusinessError;
      this.hasPermission = false;
      this.permissionDenied = true;
      Logger.error(TAG, `Request camera permission error: ${e.message}`);
    }
  }

  /** 注册 emitter 事件监听 */
  private _registerEvents(): void {
    emitter.on({ eventId: FACE_DETECTED_EVENT_ID }, async (event) => {
      const result = event.data as FaceDetectResult;
      this.lastDetectTime = result.timestamp;
      this.faceCount = result.faceCount ?? 1;
      this.faceConfidence = result.confidence ?? 1.0;
      if (this.presenceState !== PresenceState.PRESENT) {
        this.detectedCount++;
        this.presenceState = PresenceState.PRESENT;
        await ScreenControlUtils.keepScreenOn(this._context!, FACE_GUARD_CONSTANTS.SCREEN_ON_KEEP_MS);
        Logger.info(TAG, `User PRESENT (faces=${this.faceCount}, conf=${this.faceConfidence.toFixed(2)}) → screen kept on.`);
      }
    });

    emitter.on({ eventId: FACE_LOST_EVENT_ID }, async (event) => {
      const result = event.data as FaceDetectResult;
      this.lastDetectTime = result.timestamp;
      this.faceCount = 0;
      this.faceConfidence = 0.0;
      if (this.presenceState !== PresenceState.ABSENT) {
        this.presenceState = PresenceState.ABSENT;
        await ScreenControlUtils.turnScreenOff(this._context!);
        Logger.info(TAG, 'User ABSENT → screen turned off.');
      }
    });

    emitter.on({ eventId: FACE_SERVICE_STATE_EVENT_ID }, (event) => {
      const data = event.data as FaceServiceStateData;
      this.serviceState = data.state;
      if (data.state === FaceServiceState.ERROR) {
        this.errorMessage = '摄像头服务异常，请重启应用。';
        this.isServiceRunning = false;
      }
    });
  }

  /** 注销 emitter 事件监听 */
  private _unregisterEvents(): void {
    emitter.off(FACE_DETECTED_EVENT_ID);
    emitter.off(FACE_LOST_EVENT_ID);
    emitter.off(FACE_SERVICE_STATE_EVENT_ID);
  }
}
