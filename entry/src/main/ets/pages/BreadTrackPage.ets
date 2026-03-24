/**
 * @file    面包追踪主页面
 * @desc    扫描附近面包设备，展示设备列表；
 *          当设备 RSSI 达到近距离阈值时自动导航到详情页；
 *          当设备信号丢失时自动返回列表页。
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import { ProximityViewModel } from '../viewmodel/ProximityViewModel';
import { BreadDeviceCard } from '../components/business/BreadDeviceCard';
import { BreadDevice, DeviceStatus } from '../model/BreadDevice';
import { AutoNavAction } from '../model/BreadDevice';
import { ROUTES } from '../constants/AppConstants';
import { Logger } from '../utils/Logger';

@Entry
@Component
struct BreadTrackPage {
  // ─── 状态 ────────────────────────────────────────────────────
  @State private viewModel: ProximityViewModel = new ProximityViewModel();
  /** 是否正在执行自动导航动画（防止重复触发） */
  @State private isNavigating: boolean = false;
  /** Toast 提示文本 */
  @State private toastMsg: string = '';
  @State private showToast: boolean = false;
  private _toastTimer: number = -1;

  // ─── 生命周期 ────────────────────────────────────────────────

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;

    // 注册自动导航回调
    this.viewModel.registerAutoNavCallback(
      (action: AutoNavAction, device: BreadDevice) => {
        this._handleAutoNav(action, device);
      }
    );

    // 异步初始化（检测蓝牙 + 申请权限 + 启动扫描）
    this.viewModel.init(context).catch((e: Error) => {
      Logger.error('BreadTrackPage', 'ViewModel init failed', e);
    });
  }

  aboutToDisappear(): void {
    this.viewModel.unregisterAutoNavCallback();
    this.viewModel.destroy();
    this._clearToastTimer();
  }

  /**
   * 从设置页返回后刷新状态（T46/T47：蓝牙或权限变更后重试）
   * 通过 router 的 onPageShow 生命周期触发
   */
  onPageShow(): void {
    const context = getContext(this) as common.UIAbilityContext;
    if (!this.viewModel.bluetoothEnabled || !this.viewModel.hasPermission) {
      this.viewModel.retryAfterSettings(context).catch((e: Error) => {
        Logger.error('BreadTrackPage', 'Retry after settings failed', e);
      });
    }
  }

  // ─── 自动导航处理 ─────────────────────────────────────────────

  /**
   * 响应 ViewModel 自动导航事件
   * OPEN：靠近 → 跳转详情页
   * CLOSE：离开 → 详情页返回（由详情页自己处理，此处仅记录日志）
   */
  private _handleAutoNav(action: AutoNavAction, device: BreadDevice): void {
    if (this.isNavigating) {
      return;
    }
    if (action === AutoNavAction.OPEN) {
      this.isNavigating = true;
      this._showToast(`「${device.name}」靠近，自动打开详情`);
      Logger.info('BreadTrackPage', `Auto open detail for ${device.deviceId}`);

      router.pushUrl({
        url: ROUTES.BREAD_DETAIL,
        params: {
          deviceId: device.deviceId,
          deviceName: device.name,
          deviceSnapshot: JSON.stringify(device),
        },
      }).then(() => {
        this.isNavigating = false;
      }).catch((e: Error) => {
        this.isNavigating = false;
        Logger.error('BreadTrackPage', 'Auto open navigation failed', e);
      });
    }
  }

  private _showToast(msg: string): void {
    this.toastMsg = msg;
    this.showToast = true;
    this._clearToastTimer();
    this._toastTimer = setTimeout(() => {
      this.showToast = false;
    }, 2500);
  }

  private _clearToastTimer(): void {
    if (this._toastTimer !== -1) {
      clearTimeout(this._toastTimer);
      this._toastTimer = -1;
    }
  }

  // ─── UI ──────────────────────────────────────────────────────

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 顶部导航栏
        this._buildHeader()

        // 扫描状态栏
        this._buildScanStatusBar()

        // 设备列表
        if (this.viewModel.devices.length === 0) {
          this._buildEmptyState()
        } else {
          this._buildDeviceList()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))

      // 自动导航 Toast
      if (this.showToast) {
        this._buildToast()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private _buildHeader() {
    Row() {
      Text('面包追踪')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Blank()

      // 扫描开关按钮
      Button(this.viewModel.scanSession.isScanning ? '停止' : '扫描')
        .fontSize(13)
        .fontColor($r('app.color.brand_primary'))
        .backgroundColor($r('app.color.brand_secondary'))
        .borderRadius(16)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .onClick(() => {
          if (this.viewModel.scanSession.isScanning) {
            this.viewModel.stopScan();
          } else {
            this.viewModel.startScan();
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 52, bottom: 12 })
    .backgroundColor($r('app.color.bg_card'))
  }

  @Builder
  private _buildScanStatusBar() {
    // T46：蓝牙未开启 → 显示引导横幅
    if (!this.viewModel.bluetoothEnabled) {
      this._buildAlertBanner(
        '蓝牙未开启',
        '请开启蓝牙以扫描附近面包设备',
        '前往开启',
        () => {
          const context = getContext(this) as common.UIAbilityContext;
          this.viewModel.openBluetoothSettings(context);
        }
      );
      return;
    }
    // T47：权限被拒 → 显示引导横幅
    if (this.viewModel.permissionDenied) {
      this._buildAlertBanner(
        '权限未授权',
        '需要蓝牙和位置权限，请在设置中开启',
        '前往设置',
        () => {
          const context = getContext(this) as common.UIAbilityContext;
          this.viewModel.openPermissionSettings(context);
        }
      );
      return;
    }
    // 正常扫描状态栏
    Row({ space: 6 }) {
      if (this.viewModel.scanSession.isScanning) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color($r('app.color.brand_primary'))
        Text('正在扫描附近面包设备...')
          .fontSize(12)
          .fontColor($r('app.color.brand_primary'))
      } else if (this.viewModel.scanSession.error) {
        Text(`⚠ ${this.viewModel.scanSession.error}`)
          .fontSize(12)
          .fontColor($r('app.color.proximity_far'))
      } else {
        Text('扫描已停止')
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor('#FFF8F0')
  }

  @Builder
  private _buildAlertBanner(
    title: string,
    desc: string,
    btnText: string,
    onPress: () => void
  ) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.proximity_far'))
        Text(desc)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button(btnText)
        .fontSize(12)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.proximity_far'))
        .borderRadius(14)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .onClick(onPress)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('#FFF1F0')
  }

  @Builder
  private _buildDeviceList() {
    List({ space: 10 }) {
      ForEach(
        this.viewModel.devices,
        (device: BreadDevice) => {
          ListItem() {
            BreadDeviceCard({
              device: device,
              isActive: this.viewModel.activeDeviceId === device.deviceId,
              onTap: (d: BreadDevice) => {
                // 手动点击也能跳转详情
                router.pushUrl({
                  url: ROUTES.BREAD_DETAIL,
                  params: {
                    deviceId: d.deviceId,
                    deviceName: d.name,
                    deviceSnapshot: JSON.stringify(d),
                  },
                });
              },
            })
          }
        },
        (device: BreadDevice) => device.deviceId
      )
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, top: 12, bottom: 24 })
  }

  @Builder
  private _buildEmptyState() {
    Column({ space: 12 }) {
      Text('🍞')
        .fontSize(48)
      Text('暂未发现附近面包设备')
        .fontSize(14)
        .fontColor($r('app.color.text_hint'))
      Text('请确保面包设备已开启，并靠近手机')
        .fontSize(12)
        .fontColor($r('app.color.text_hint'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private _buildToast() {
    Text(this.toastMsg)
      .fontSize(13)
      .fontColor(Color.White)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor('#CC333333')
      .borderRadius(20)
      .margin({ bottom: 40 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
  }
}
