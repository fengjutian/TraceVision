/**
 * @file    FaceDetectionService.ets
 * @desc    面部感知服务：
 *          - 前置摄像头：提供预览画面输出到 XComponent
 *          - 近距离传感器（Proximity Sensor）：检测用户靠近/离开
 *            distance == 0  → 用户靠近  → 广播 FACE_DETECTED 事件
 *            distance  > 0  → 用户离开  → 广播 FACE_LOST 事件
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import camera from '@ohos.multimedia.camera';
import sensor from '@ohos.sensor';
import emitter from '@ohos.events.emitter';
import { BusinessError } from '@ohos.base';
import { FACE_GUARD_CONSTANTS } from '../constants/AppConstants';
import { Logger } from '../utils/Logger';

/** emitter 事件 ID：检测到人脸（用户靠近） */
export const FACE_DETECTED_EVENT_ID: number = 300;
/** emitter 事件 ID：人脸消失（用户离开） */
export const FACE_LOST_EVENT_ID: number = 301;
/** emitter 事件 ID：服务状态变更 */
export const FACE_SERVICE_STATE_EVENT_ID: number = 302;

/** 服务运行状态 */
export enum FaceServiceState {
  IDLE = 'IDLE',
  RUNNING = 'RUNNING',
  ERROR = 'ERROR',
  NO_PERMISSION = 'NO_PERMISSION',
}

/** 检测结果数据（兼容 ViewModel 接口） */
export interface FaceDetectResult {
  hasFace: boolean;
  confidence: number;
  timestamp: number;
}

/** 服务状态变更事件数据 */
export interface FaceServiceStateData {
  state: FaceServiceState;
}

const TAG: string = 'FaceDetectionService';

/** 预览 Profile 评分条目（用于选取最佳预览分辨率） */
interface ScoredProfile {
  p: camera.Profile;
  ratioDiff: number;
  area: number;
}

/**
 * 面部感知服务（单例）
 *
 * 检测逻辑：
 *  - 近距离传感器 distance == 0  → 持续 ARRIVE_CONFIRM_MS 后触发 FACE_DETECTED
 *  - 近距离传感器 distance  > 0  → 持续 LEAVE_CONFIRM_MS  后触发 FACE_LOST
 */
class FaceDetectionService {
  private static _instance: FaceDetectionService | null = null;

  // ── 摄像头相关 ──────────────────────────────────────────────────
  private _cameraManager: camera.CameraManager | null = null;
  private _cameraSession: camera.PhotoSession | null = null;
  private _previewOutput: camera.PreviewOutput | null = null;
  private _surfaceId: string = '';

  // ── 传感器相关 ──────────────────────────────────────────────────
  private _proxCallback: ((data: sensor.ProximityResponse) => void) | null = null;
  /** 当前近距离状态：true = 靠近，false = 远离 */
  private _isNear: boolean = false;
  /** 防抖计时器 */
  private _debounceTimer: number = -1;

  private _state: FaceServiceState = FaceServiceState.IDLE;

  static getInstance(): FaceDetectionService {
    if (!FaceDetectionService._instance) {
      FaceDetectionService._instance = new FaceDetectionService();
    }
    return FaceDetectionService._instance;
  }

  get state(): FaceServiceState {
    return this._state;
  }

  /**
   * 启动服务
   * @param context   - UIAbility 上下文，用于获取 CameraManager
   * @param surfaceId - XComponent 的 SurfaceId，用于预览输出
   */
  async start(context: Context, surfaceId: string): Promise<void> {
    if (this._state === FaceServiceState.RUNNING) {
      Logger.info(TAG, 'Service already running.');
      return;
    }
    this._surfaceId = surfaceId;
    try {
      await this._initCamera(context);
      this._startProximitySensor();
      this._setState(FaceServiceState.RUNNING);
      Logger.info(TAG, 'FaceDetectionService started.');
    } catch (err) {
      const e = err as BusinessError;
      Logger.error(TAG, `Failed to start: ${e.message}`);
      this._setState(FaceServiceState.ERROR);
    }
  }

  /** 停止服务，释放摄像头与传感器资源 */
  async stop(): Promise<void> {
    this._stopProximitySensor();
    this._clearDebounce();
    await this._releaseCamera();
    this._setState(FaceServiceState.IDLE);
    Logger.info(TAG, 'FaceDetectionService stopped.');
  }

  // ─────────────────────────── 摄像头 ───────────────────────────

  private async _initCamera(context: Context): Promise<void> {
    this._cameraManager = camera.getCameraManager(context);
    const cameras: camera.CameraDevice[] = this._cameraManager.getSupportedCameras();

    // 优先前置摄像头
    const frontCamera = cameras.find(
      (c) => c.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT
    ) ?? cameras[0];

    if (!frontCamera) {
      throw new Error('No available camera device found.');
    }
    Logger.info(TAG, `Using camera: ${frontCamera.cameraId}`);

    // 仅需预览输出（近距离传感器负责检测，摄像头只显示预览）
    this._cameraSession = this._cameraManager.createSession(
      camera.SceneMode.NORMAL_PHOTO
    ) as camera.PhotoSession;

    this._cameraSession.beginConfig();

    const cameraInput = this._cameraManager.createCameraInput(frontCamera);
    await cameraInput.open();
    this._cameraSession.addInput(cameraInput);

    // 选择最接近 16:9 的预览分辨率，避免预览画面拉伸
    const previewProfile = this._getBestPreviewProfile(frontCamera);
    this._previewOutput = this._cameraManager.createPreviewOutput(
      previewProfile,
      this._surfaceId
    );
    this._cameraSession.addOutput(this._previewOutput);

    await this._cameraSession.commitConfig();
    await this._cameraSession.start();
    Logger.info(TAG, `Camera preview started (${previewProfile.size.width}x${previewProfile.size.height}).`);
  }

  /**
   * 选取最佳预览 Profile：
   * 优先宽高比最接近 16:9，在同比例中选分辨率最高（但不超过 1920x1080）的档位。
   */
  private _getBestPreviewProfile(device: camera.CameraDevice): camera.Profile {
    const profiles = this._cameraManager!.getSupportedOutputCapability(
      device,
      camera.SceneMode.NORMAL_PHOTO
    ).previewProfiles;

    const TARGET_RATIO: number = 16 / 9;

    const scored: ScoredProfile[] = profiles.map((p): ScoredProfile => {
      const ratio: number = p.size.width / p.size.height;
      const ratioDiff: number = Math.abs(ratio - TARGET_RATIO);
      const area: number = p.size.width * p.size.height;
      return { p, ratioDiff, area };
    });

    // 按比例差升序 → 面积降序，取第一个不超过 1920×1080 的
    scored.sort((a, b) => {
      if (Math.abs(a.ratioDiff - b.ratioDiff) > 0.05) {
        return a.ratioDiff - b.ratioDiff;
      }
      return b.area - a.area;
    });

    const best = scored.find((s) => s.area <= 1920 * 1080);
    return best ? best.p : scored[0].p;
  }

  private async _releaseCamera(): Promise<void> {
    try {
      if (this._cameraSession) {
        await this._cameraSession.stop();
        await this._cameraSession.release();
        this._cameraSession = null;
      }
      if (this._previewOutput) {
        await this._previewOutput.release();
        this._previewOutput = null;
      }
    } catch (err) {
      const e = err as BusinessError;
      Logger.error(TAG, `Release camera error: ${e.message}`);
    }
  }

  // ─────────────────────────── 近距离传感器 ───────────────────────

  private _startProximitySensor(): void {
    this._proxCallback = (data: sensor.ProximityResponse) => {
      // distance == 0 → 靠近；distance > 0 → 远离
      const isNear: boolean = data.distance === 0;
      if (isNear === this._isNear) {
        return; // 状态未变，忽略
      }
      this._isNear = isNear;
      this._clearDebounce();

      const confirmMs: number = isNear
        ? FACE_GUARD_CONSTANTS.ARRIVE_CONFIRM_MS
        : FACE_GUARD_CONSTANTS.LEAVE_CONFIRM_MS;

      this._debounceTimer = setTimeout(() => {
        this._debounceTimer = -1;
        if (isNear) {
          const result: FaceDetectResult = { hasFace: true, confidence: 1.0, timestamp: Date.now() };
          emitter.emit({ eventId: FACE_DETECTED_EVENT_ID }, { data: result });
          Logger.info(TAG, 'Proximity NEAR → Emit FACE_DETECTED.');
        } else {
          const result: FaceDetectResult = { hasFace: false, confidence: 0.0, timestamp: Date.now() };
          emitter.emit({ eventId: FACE_LOST_EVENT_ID }, { data: result });
          Logger.info(TAG, 'Proximity FAR → Emit FACE_LOST.');
        }
      }, confirmMs);
    };

    try {
      sensor.on(sensor.SensorId.PROXIMITY, this._proxCallback, { interval: 200000000 });
      Logger.info(TAG, 'Proximity sensor subscribed.');
    } catch (err) {
      const e = err as BusinessError;
      Logger.error(TAG, `Failed to subscribe proximity sensor: ${e.message}`);
      this._setState(FaceServiceState.ERROR);
    }
  }

  private _stopProximitySensor(): void {
    if (this._proxCallback) {
      try {
        sensor.off(sensor.SensorId.PROXIMITY, this._proxCallback);
        Logger.info(TAG, 'Proximity sensor unsubscribed.');
      } catch (err) {
        const e = err as BusinessError;
        Logger.error(TAG, `Failed to unsubscribe proximity sensor: ${e.message}`);
      }
      this._proxCallback = null;
    }
  }

  private _clearDebounce(): void {
    if (this._debounceTimer !== -1) {
      clearTimeout(this._debounceTimer);
      this._debounceTimer = -1;
    }
  }

  // ─────────────────────────── 工具 ───────────────────────────────

  private _setState(state: FaceServiceState): void {
    this._state = state;
    const stateData: FaceServiceStateData = { state };
    emitter.emit({ eventId: FACE_SERVICE_STATE_EVENT_ID }, { data: stateData });
  }
}

export default FaceDetectionService.getInstance();
