/**
 * @file    应用入口页面（Index）
 * @desc    应用启动后的首页，提供跳转面包追踪功能的入口
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
        .margin({ top: 120 })

      Text('TraceVision')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text('面包近距离追踪系统')
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))

      Blank()

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

      Text('靠近设备时自动打开详情，离开时自动关闭')
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
