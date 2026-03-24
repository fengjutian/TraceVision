/**
 * @file    应用入口页面（Index）
 * @desc    应用启动后的首页，提供跳转面包追踪功能和面部感知守护功能的入口
 * @author  TraceVision Team
 * @date    2026-03-24
 */
import router from '@ohos.router';
import { ROUTES } from '../constants/AppConstants';

@Entry
@Component
struct Index {
  build() {
    Column({ space: 24 }) {
      Text('🍞')
        .fontSize(64)
        .margin({ top: 100 })

      Text('TraceVision')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text('面包近距离追踪系统')
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))

      Blank()

      // 面包 BLE 追踪入口
      Button('开始追踪')
        .width('80%')
        .height(48)
        .fontSize(16)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.brand_primary'))
        .borderRadius(24)
        .onClick(() => {
          router.pushUrl({ url: ROUTES.BREAD_TRACK });
        })

      // 面部识别守护入口
      Button('面部感知守护')
        .width('80%')
        .height(48)
        .fontSize(16)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.face_guard_btn'))
        .borderRadius(24)
        .onClick(() => {
          router.pushUrl({ url: ROUTES.FACE_GUARD });
        })

      Text('面部识别 · 靠近自动亮屏，离开自动熄屏')
        .fontSize(12)
        .fontColor($r('app.color.text_hint'))
        .margin({ bottom: 60 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .alignItems(HorizontalAlign.Center)
  }
}
