/**
 * @file    FaceGuardPage.ets
 * @desc    面部识别守护页面。
 *          展示前置摄像头预览画面，实时显示人脸检测结果（置信度、人脸数量）；
 *          检测到人脸时自动亮屏（申请唤醒锁），离开后自动允许熄屏（释放唤醒锁）。
 * @author  TraceVision Team
 * @date    2026-03-25
 */
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import emitter from '@ohos.events.emitter';
import { FaceProximityViewModel, PresenceState } from '../viewmodel/FaceProximityViewModel';
import {
  FaceServiceState,
  PREVIEW_SIZE_EVENT_ID,
  PreviewSizeData,
} from '../service/FaceDetectionService';
import { Logger } from '../utils/Logger';

const TAG: string = 'FaceGuardPage';

@Entry
@Component
struct FaceGuardPage {
  @State private vm: FaceProximityViewModel = new FaceProximityViewModel();
  /**
   * 摄像头预览宽高比（width/height）。
   * 前置摄像头帧通常是横向（如 1920×1080 → 16/9），渲染到竖屏时系统旋转90°，
   * 所以 XComponent 实际显示比例应取倒数（height/width），即 9/16。
   * 默认 9/16，服务启动后根据实际 Profile 更新。
   */
  @State private _previewRatio: number = 9 / 16;
  /** XComponent surfaceId，由 onLoad 回调获取 */
  private _xComponentController: XComponentController = new XComponentController();

  // ─────────────────────────── 生命周期 ───────────────────────────

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.vm.init(context).then(() => {
      Logger.info(TAG, `Permission=${this.vm.hasPermission}`);
    });

    // 订阅预览尺寸事件：收到后更新 aspectRatio，使 XComponent 保持正确比例
    emitter.on({ eventId: PREVIEW_SIZE_EVENT_ID }, (event) => {
      const data = event.data as PreviewSizeData;
      const w: number = data.width;
      const h: number = data.height;
      Logger.info(TAG, `PREVIEW_SIZE received: ${w}x${h}`);

      // 摄像头帧横向（w > h），竖屏显示时系统旋转90° → 显示比例 = h/w（即 9/16）
      // 摄像头帧竖向（h > w），无旋转 → 显示比例 = w/h
      this._previewRatio = w > h ? h / w : w / h;
      // 注意：不调用 setXComponentSurfaceRect，避免将摄像头原始像素尺寸
      // 强制写入 Surface 导致与 XComponent 实际渲染尺寸（dp）不匹配而拉伸。
    });
  }

  aboutToDisappear(): void {
    emitter.off(PREVIEW_SIZE_EVENT_ID);
    this.vm.stopService();
  }

  // ─────────────────────────── 私有方法 ───────────────────────────

  private _onXComponentLoad(): void {
    const surfaceId = this._xComponentController.getXComponentSurfaceId();
    Logger.info(TAG, `XComponent loaded, surfaceId=${surfaceId}`);
    // 启动服务；Service 确定 Profile 后会 emit PREVIEW_SIZE_EVENT_ID
    // Page 在 aboutToAppear 已订阅，收到后自动设置 Surface 尺寸和 aspectRatio
    this.vm.startService(surfaceId);
  }

  private _presenceLabel(): string {
    switch (this.vm.presenceState) {
      case PresenceState.PRESENT:
        return '检测到人脸 · 屏幕保持亮起';
      case PresenceState.ABSENT:
        return '未检测到人脸 · 屏幕即将熄灭';
      default:
        return '人脸识别中...';
    }
  }

  private _presenceColor(): Resource {
    switch (this.vm.presenceState) {
      case PresenceState.PRESENT:
        return $r('app.color.state_present');
      case PresenceState.ABSENT:
        return $r('app.color.state_absent');
      default:
        return $r('app.color.text_hint');
    }
  }

  private _presenceIcon(): string {
    switch (this.vm.presenceState) {
      case PresenceState.PRESENT:
        return '😊';
      case PresenceState.ABSENT:
        return '😴';
      default:
        return '👁️';
    }
  }

  // ─────────────────────────── UI 构建 ───────────────────────────

  build() {
    Column() {
      // 顶部导航栏
      this._buildTopBar()

      if (!this.vm.hasPermission) {
        // 无权限提示
        this._buildPermissionDenied()
      } else if (this.vm.serviceState === FaceServiceState.ERROR) {
        // 服务错误提示
        this._buildErrorState()
      } else {
        // 摄像头预览 + 状态卡片
        this._buildMainContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  private _buildTopBar() {
    Row() {
      Text('‹ 返回')
        .fontSize(16)
        .fontColor($r('app.color.brand_primary'))
        .padding({ left: 16, right: 8, top: 4, bottom: 4 })
        .onClick(() => {
          this.vm.stopService();
          router.back();
        })

      Text('面部感知守护')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      // 占位，保持标题居中
      Blank()
        .width(24 + 16)
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.bg_card'))
  }

  @Builder
  private _buildMainContent() {
    Column({ space: 0 }) {
      // 摄像头预览区域
      Stack({ alignContent: Alignment.Bottom }) {
        XComponent({
          id: 'facePreview',
          type: XComponentType.SURFACE,
          controller: this._xComponentController,
        })
          .width('100%')
          .height('100%')
          .onLoad(() => {
            this._onXComponentLoad();
          })

        // 预览顶部：人脸识别实时状态角标
        Row({ space: 6 }) {
          // 状态指示灯
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(
              this.vm.presenceState === PresenceState.PRESENT ? '#00FF88' : '#FF4444'
            )
            .animation({ duration: 600, iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut })

          Text(this.vm.presenceState === PresenceState.PRESENT
            ? `人脸 ×${this.vm.faceCount}`
            : '未检测到人脸')
            .fontSize(12)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('#99000000')
        .borderRadius(20)
        .alignSelf(ItemAlign.Start)
        .margin({ top: 10, left: 10 })
        .alignItems(VerticalAlign.Center)
        .position({ x: 10, y: 10 })

        // 预览底部渐变遮罩 + 状态 + 置信度
        Column({ space: 6 }) {
          // 置信度进度条（仅 PRESENT 时显示）
          if (this.vm.presenceState === PresenceState.PRESENT) {
            Column({ space: 4 }) {
              Row() {
                Text('识别置信度')
                  .fontSize(11)
                  .fontColor('#CCFFFFFF')
                  .layoutWeight(1)
                Text(`${Math.round(this.vm.faceConfidence * 100)}%`)
                  .fontSize(11)
                  .fontColor('#FFFFFFFF')
                  .fontWeight(FontWeight.Medium)
              }
              .width('80%')

              // 进度条背景
              Stack({ alignContent: Alignment.Start }) {
                // 背景轨道
                Row()
                  .width('80%')
                  .height(4)
                  .borderRadius(2)
                  .backgroundColor('#33FFFFFF')
                // 进度填充
                Row()
                  .width(`${this.vm.faceConfidence * 80}%`)
                  .height(4)
                  .borderRadius(2)
                  .backgroundColor(
                    this.vm.faceConfidence >= 0.8 ? '#00FF88'
                      : this.vm.faceConfidence >= 0.5 ? '#FFCC00'
                      : '#FF6633'
                  )
                  .animation({ duration: 300, curve: Curve.EaseOut })
              }
              .width('80%')
            }
            .alignItems(HorizontalAlign.Center)
          }

          // 状态 icon + 文字
          Text(this._presenceIcon())
            .fontSize(32)
          Text(this.vm.presenceState === PresenceState.PRESENT ? '已检测到人脸' : '未检测到人脸')
            .fontSize(13)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
        }
        .padding({ bottom: 14, top: 20 })
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .linearGradient({
          direction: GradientDirection.Top,
          colors: [['#00000000', 0.0], ['#CC000000', 1.0]],
        })
      }
      .width('100%')
      .aspectRatio(this._previewRatio)
      .clip(true)

      // 状态卡片
      Column({ space: 16 }) {
        // 在场状态行
        Row({ space: 12 }) {
          Column()
            .width(12)
            .height(12)
            .borderRadius(6)
            .backgroundColor(this._presenceColor())
            .animation({
              duration: 800,
              iterations: this.vm.presenceState === PresenceState.PRESENT ? -1 : 1,
              playMode: PlayMode.Alternate,
              curve: Curve.EaseInOut,
            })

          Text(this._presenceLabel())
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
        }
        .padding({ left: 16, right: 16, top: 20 })
        .alignItems(VerticalAlign.Center)

        Divider()
          .height(1)
          .color($r('app.color.divider'))
          .margin({ left: 16, right: 16 })

        // 统计信息：4项（新增置信度）
        Row() {
          this._buildStatItem('检测次数', `${this.vm.detectedCount}`)
          Divider().vertical(true).height(36).color($r('app.color.divider'))
          this._buildStatItem('当前人脸', `${this.vm.faceCount}`)
          Divider().vertical(true).height(36).color($r('app.color.divider'))
          this._buildStatItem('置信度', this.vm.presenceState === PresenceState.PRESENT
            ? `${Math.round(this.vm.faceConfidence * 100)}%`
            : '--')
          Divider().vertical(true).height(36).color($r('app.color.divider'))
          this._buildStatItem('服务', this._serviceStateLabel())
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
        .padding({ left: 8, right: 8, bottom: 20 })

        // 原理说明
        Text('前置摄像头逐帧分析画面，检测到人脸时屏幕自动亮起；\n人脸离开视野后屏幕自动熄灭，保护隐私并节省电量。')
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
          .textAlign(TextAlign.Center)
          .margin({ left: 20, right: 20, bottom: 24 })
          .lineHeight(18)
      }
      .width('100%')
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius({ topLeft: 16, topRight: 16 })
      .margin({ top: -16 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private _buildStatItem(label: string, value: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_hint'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 12 })
  }

  @Builder
  private _buildPermissionDenied() {
    Column({ space: 20 }) {
      Text('📷')
        .fontSize(56)
        .margin({ top: 80 })

      Text('需要摄像头权限')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Text('面部感知功能需要访问前置摄像头，用于检测用户是否在设备前方。\n我们不会存储或上传任何图像数据。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ left: 32, right: 32 })
        .lineHeight(22)

      Button('前往设置授权')
        .width('70%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.brand_primary'))
        .borderRadius(22)
        .onClick(() => {
          this.vm.openPermissionSettings();
        })

      Button('返回')
        .width('70%')
        .height(44)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor(Color.Transparent)
        .borderRadius(22)
        .onClick(() => {
          router.back();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private _buildErrorState() {
    Column({ space: 20 }) {
      Text('⚠️')
        .fontSize(56)
        .margin({ top: 80 })

      Text('摄像头服务异常')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Text(this.vm.errorMessage || '请检查摄像头是否被其他应用占用，然后重试。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ left: 32, right: 32 })
        .lineHeight(22)

      Button('重试')
        .width('70%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.brand_primary'))
        .borderRadius(22)
        .onClick(() => {
          if (this.vm.surfaceId) {
            this.vm.startService(this.vm.surfaceId);
          }
        })
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  private _serviceStateLabel(): string {
    switch (this.vm.serviceState) {
      case FaceServiceState.RUNNING:
        return '正常';
      case FaceServiceState.ERROR:
        return '异常';
      case FaceServiceState.NO_PERMISSION:
        return '无权限';
      default:
        return '待机';
    }
  }
}
