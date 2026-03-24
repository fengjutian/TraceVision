/**
 * @file    FaceDetectionService.ets
 * @desc    面部感知服务：
 *          - 前置摄像头：输出预览画面到 XComponent
 *          - 摄像头帧分析：通过 ImageAnalyzerController 触发逐帧人脸检测
 *            检测到人脸  → 广播 FACE_DETECTED 事件（携带置信度、人脸数）
 *            未检测到脸  → 广播 FACE_LOST 事件
 * @author  TraceVision Team
 * @date    2026-03-25
 */
import camera from '@ohos.multimedia.camera';
import image from '@ohos.multimedia.image';
import emitter from '@ohos.events.emitter';
import { BusinessError } from '@ohos.base';
import { FACE_GUARD_CONSTANTS } from '../constants/AppConstants';
import { Logger } from '../utils/Logger';

/** emitter 事件 ID：检测到人脸 */
export const FACE_DETECTED_EVENT_ID: number = 300;
/** emitter 事件 ID：人脸消失 */
export const FACE_LOST_EVENT_ID: number = 301;
/** emitter 事件 ID：服务状态变更 */
export const FACE_SERVICE_STATE_EVENT_ID: number = 302;
/** emitter 事件 ID：预览尺寸确定（携带实际 Profile 的像素宽高） */
export const PREVIEW_SIZE_EVENT_ID: number = 303;

/** 服务运行状态 */
export enum FaceServiceState {
  IDLE = 'IDLE',
  RUNNING = 'RUNNING',
  ERROR = 'ERROR',
  NO_PERMISSION = 'NO_PERMISSION',
}

/** 检测结果数据 */
export interface FaceDetectResult {
  hasFace: boolean;
  /** 人脸数量（0 表示未检测到） */
  faceCount: number;
  /** 置信度 0.0~1.0（无人脸时为 0） */
  confidence: number;
  timestamp: number;
}

/** 服务状态变更事件数据 */
export interface FaceServiceStateData {
  state: FaceServiceState;
}

/** 预览尺寸事件数据（像素单位，未经旋转的原始 Profile 尺寸） */
export interface PreviewSizeData {
  width: number;
  height: number;
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
 * 检测逻辑（基于摄像头帧 + 防抖）：
 *  - 连续 ARRIVE_CONFIRM_MS 帧均检测到人脸  → 触发 FACE_DETECTED
 *  - 连续 LEAVE_CONFIRM_MS  帧均未检测到脸  → 触发 FACE_LOST
 */
class FaceDetectionService {
  private static _instance: FaceDetectionService | null = null;

  // ── 摄像头相关 ──────────────────────────────────────────────────
  private _cameraManager: camera.CameraManager | null = null;
  private _cameraSession: camera.PhotoSession | null = null;
  private _previewOutput: camera.PreviewOutput | null = null;
  private _photoOutput: camera.PhotoOutput | null = null;
  private _surfaceId: string = '';
  /** 实际选用的预览宽度（px） */
  previewWidth: number = 0;
  /** 实际选用的预览高度（px） */
  previewHeight: number = 0;

  // ── 帧分析相关 ──────────────────────────────────────────────────
  /** 帧分析输出 */
  private _videoOutput: camera.VideoOutput | null = null;
  /** 是否正在执行人脸检测（防止重入） */
  private _detecting: boolean = false;
  /** 上次检测时间戳（限制检测帧率） */
  private _lastDetectTs: number = 0;
  /** 当前是否检测到人脸（用于防抖状态机） */
  private _hasFace: boolean = false;
  /** 防抖计时器 */
  private _debounceTimer: number = -1;
  /** 帧分析用图像接收器 */
  private _imageReceiver: image.ImageReceiver | null = null;

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
   * @param context   - UIAbility 上下文
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
      this._setState(FaceServiceState.RUNNING);
      Logger.info(TAG, 'FaceDetectionService started.');
    } catch (err) {
      const e = err as BusinessError;
      Logger.error(TAG, `Failed to start: ${e.message}`);
      this._setState(FaceServiceState.ERROR);
      throw err;
    }
  }

  /** 停止服务，释放摄像头资源 */
  async stop(): Promise<void> {
    this._clearDebounce();
    this._detecting = false;
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

    this._cameraSession = this._cameraManager.createSession(
      camera.SceneMode.NORMAL_PHOTO
    ) as camera.PhotoSession;

    this._cameraSession.beginConfig();

    const cameraInput = this._cameraManager.createCameraInput(frontCamera);
    await cameraInput.open();
    this._cameraSession.addInput(cameraInput);

    // 选择最接近 16:9 的预览分辨率
    const previewProfile = this._getBestPreviewProfile(frontCamera);
    this.previewWidth = previewProfile.size.width;
    this.previewHeight = previewProfile.size.height;

    // 通知 UI 更新宽高比
    const sizeData: PreviewSizeData = { width: this.previewWidth, height: this.previewHeight };
    emitter.emit({ eventId: PREVIEW_SIZE_EVENT_ID }, { data: sizeData });
    Logger.info(TAG, `Preview profile: ${this.previewWidth}x${this.previewHeight}`);

    // 预览输出（显示到 XComponent）
    this._previewOutput = this._cameraManager.createPreviewOutput(
      previewProfile,
      this._surfaceId
    );
    this._cameraSession.addOutput(this._previewOutput);

    // ── 帧分析输出（用于人脸检测） ──────────────────────────────
    // 用较小分辨率的 ImageReceiver 减少分析延迟（640×480 足够人脸检测精度）
    const analyzeWidth: number = 640;
    const analyzeHeight: number = 480;
    this._imageReceiver = image.createImageReceiver(
      analyzeWidth,
      analyzeHeight,
      image.ImageFormat.JPEG,
      2
    );
    const analyzeSurfaceId = await this._imageReceiver.getReceivingSurfaceId();

    // 选取与分析尺寸最匹配的 photo profile（用来走帧分析，而非拍照）
    const photoProfile = this._getBestPhotoProfile(frontCamera, analyzeWidth, analyzeHeight);
    this._photoOutput = this._cameraManager.createPhotoOutput(photoProfile, analyzeSurfaceId);
    this._cameraSession.addOutput(this._photoOutput);

    // 注册帧可用回调，触发人脸检测
    this._imageReceiver.on('imageArrival', () => {
      this._onFrameArrived();
    });

    await this._cameraSession.commitConfig();
    await this._cameraSession.start();
    Logger.info(TAG, `Camera started (preview: ${this.previewWidth}x${this.previewHeight}, analyze: ${analyzeWidth}x${analyzeHeight}).`);
  }

  /**
   * 选取最佳预览 Profile（最接近 16:9，分辨率不超过 1920×1080）
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

    scored.sort((a, b) => {
      if (Math.abs(a.ratioDiff - b.ratioDiff) > 0.05) {
        return a.ratioDiff - b.ratioDiff;
      }
      return b.area - a.area;
    });

    const best = scored.find((s) => s.area <= 1920 * 1080);
    return best ? best.p : scored[0].p;
  }

  /**
   * 选取用于帧分析的 Photo Profile（分辨率最接近目标且不超过 target 的档位）
   */
  private _getBestPhotoProfile(device: camera.CameraDevice, targetW: number, targetH: number): camera.Profile {
    const profiles = this._cameraManager!.getSupportedOutputCapability(
      device,
      camera.SceneMode.NORMAL_PHOTO
    ).photoProfiles;

    const targetArea: number = targetW * targetH;
    // 优先选不超过目标面积的最大分辨率
    const notExceeded = profiles.filter((p) => p.size.width * p.size.height <= targetArea * 2);
    const pool = notExceeded.length > 0 ? notExceeded : profiles;

    return pool.reduce((best, cur) => {
      const bestDiff = Math.abs(best.size.width * best.size.height - targetArea);
      const curDiff = Math.abs(cur.size.width * cur.size.height - targetArea);
      return curDiff < bestDiff ? cur : best;
    });
  }

  // ─────────────────────────── 帧分析 & 人脸检测 ─────────────────

  /**
   * 每帧回调：限频 + 异步人脸检测
   * 检测频率由 CAPTURE_INTERVAL_MS 控制（默认 500ms 一次）
   */
  private _onFrameArrived(): void {
    const now = Date.now();
    // 限制检测频率
    if (now - this._lastDetectTs < FACE_GUARD_CONSTANTS.CAPTURE_INTERVAL_MS) {
      // 丢弃当前帧，但仍需消费 ImageReceiver 队列，防止溢出
      this._consumeFrame();
      return;
    }
    if (this._detecting) {
      this._consumeFrame();
      return;
    }
    this._lastDetectTs = now;
    this._detecting = true;
    this._detectFaceInFrame();
  }

  /** 消费（丢弃）ImageReceiver 队列中的当前帧，防止积压 */
  private _consumeFrame(): void {
    if (!this._imageReceiver) {
      return;
    }
    this._imageReceiver.readNextImage().then((img) => {
      img.release().catch(() => {});
    }).catch(() => {});
  }

  /**
   * 从 ImageReceiver 读取当前帧并进行人脸检测
   * 使用 @ohos.ai.vision.faceDetector（API 12+）逐帧分析
   */
  private _detectFaceInFrame(): void {
    if (!this._imageReceiver) {
      this._detecting = false;
      return;
    }

    this._imageReceiver.readNextImage().then(async (img: image.Image) => {
      try {
        // 获取 JPEG 组件数据
        const component = await img.getComponent(image.ComponentType.JPEG);
        const pixelBuffer: ArrayBuffer = component.byteBuffer;

        // 创建 PixelMap 用于人脸检测
        const imageSource = image.createImageSource(pixelBuffer);
        const pixelMap = await imageSource.createPixelMap({ editable: false });

        // ── 调用 Vision Kit 人脸检测 ──────────────────────────────
        // @ohos.ai.vision.faceDetector  API 12+
        // 动态 import 以避免低版本设备报错
        const faceDetectorModule = await import('@ohos.ai.vision.faceDetector');
        const faceDetector = faceDetectorModule.default;

        const detectResult = await faceDetector.detect(pixelMap);
        const faceCount: number = detectResult ? detectResult.length : 0;
        const confidence: number = faceCount > 0
          ? Math.max(...detectResult.map((f: { score: number }) => f.score ?? 1.0))
          : 0.0;

        Logger.info(TAG, `Face detect: count=${faceCount}, confidence=${confidence.toFixed(2)}`);
        this._onDetectResult(faceCount > 0, faceCount, confidence);

        pixelMap.release().catch(() => {});
        imageSource.release();
      } catch (err) {
        const e = err as BusinessError;
        Logger.warn(TAG, `Face detect error: ${e.message}`);
        // 检测失败时当作"未检测到人脸"处理，不改变当前状态
      } finally {
        img.release().catch(() => {});
        this._detecting = false;
      }
    }).catch((err: BusinessError) => {
      Logger.warn(TAG, `readNextImage error: ${err.message}`);
      this._detecting = false;
    });
  }

  /**
   * 根据检测结果更新状态机并发射防抖事件
   * @param detected   - 是否检测到人脸
   * @param faceCount  - 人脸数量
   * @param confidence - 最高置信度
   */
  private _onDetectResult(detected: boolean, faceCount: number, confidence: number): void {
    if (detected === this._hasFace) {
      // 状态无变化：如果是 PRESENT 状态，仍需持续上报以更新置信度
      if (detected) {
        const result: FaceDetectResult = {
          hasFace: true,
          faceCount,
          confidence,
          timestamp: Date.now(),
        };
        emitter.emit({ eventId: FACE_DETECTED_EVENT_ID }, { data: result });
      }
      return;
    }

    // 状态发生变化，启动防抖确认
    this._clearDebounce();
    const confirmMs: number = detected
      ? FACE_GUARD_CONSTANTS.ARRIVE_CONFIRM_MS
      : FACE_GUARD_CONSTANTS.LEAVE_CONFIRM_MS;

    this._debounceTimer = setTimeout(() => {
      this._debounceTimer = -1;
      this._hasFace = detected;
      const result: FaceDetectResult = {
        hasFace: detected,
        faceCount: detected ? faceCount : 0,
        confidence: detected ? confidence : 0.0,
        timestamp: Date.now(),
      };
      if (detected) {
        emitter.emit({ eventId: FACE_DETECTED_EVENT_ID }, { data: result });
        Logger.info(TAG, `Face DETECTED (count=${faceCount}, conf=${confidence.toFixed(2)}) → Emit FACE_DETECTED.`);
      } else {
        emitter.emit({ eventId: FACE_LOST_EVENT_ID }, { data: result });
        Logger.info(TAG, 'Face LOST → Emit FACE_LOST.');
      }
    }, confirmMs);
  }

  // ─────────────────────────── 资源释放 ───────────────────────────

  private async _releaseCamera(): Promise<void> {
    try {
      if (this._imageReceiver) {
        this._imageReceiver.release().catch(() => {});
        this._imageReceiver = null;
      }
      if (this._cameraSession) {
        await this._cameraSession.stop();
        await this._cameraSession.release();
        this._cameraSession = null;
      }
      if (this._previewOutput) {
        await this._previewOutput.release();
        this._previewOutput = null;
      }
      if (this._photoOutput) {
        await this._photoOutput.release();
        this._photoOutput = null;
      }
    } catch (err) {
      const e = err as BusinessError;
      Logger.error(TAG, `Release camera error: ${e.message}`);
    }
  }

  // ─────────────────────────── 工具 ───────────────────────────────

  private _clearDebounce(): void {
    if (this._debounceTimer !== -1) {
      clearTimeout(this._debounceTimer);
      this._debounceTimer = -1;
    }
  }

  private _setState(state: FaceServiceState): void {
    this._state = state;
    const stateData: FaceServiceStateData = { state };
    emitter.emit({ eventId: FACE_SERVICE_STATE_EVENT_ID }, { data: stateData });
  }
}

export default FaceDetectionService.getInstance();
