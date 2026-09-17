import Testing
@testable import EhViewerPreview

struct CardGridSizingTests {
    @Test("侧边栏动画中保留基准宽度与列数，卡片只等比缩放")
    func sidebarKeepsColumns() {
        var sizing = CardGridSizing()
        sizing.update(width: 750, windowWidth: 1000, target: 170, spacing: 16)
        #expect(sizing.columns == 4)
        let reference = sizing.referenceColumnWidth(spacing: 16)
        for width in [780.0, 820, 900, 1000, 850, 750] {
            sizing.update(width: width, windowWidth: 1000, target: 170, spacing: 16)
            #expect(sizing.columns == 4)
            #expect(sizing.referenceWidth == 750)
            #expect(sizing.referenceColumnWidth(spacing: 16) == reference)
            #expect(abs(sizing.currentColumnWidth(spacing: 16) - reference * sizing.scale(spacing: 16)) < 0.0001)
        }
        #expect(sizing.scale(spacing: 16) == 1)
    }

    @Test("真正改变窗口宽度时更新基准并重新计算列数")
    func windowResizeRebases() {
        var sizing = CardGridSizing()
        sizing.update(width: 750, windowWidth: 1000, target: 170, spacing: 16)
        sizing.update(width: 1000, windowWidth: 1000, target: 170, spacing: 16)
        sizing.update(width: 1250, windowWidth: 1250, target: 170, spacing: 16)
        #expect(sizing.referenceWidth == 1000)
        #expect(sizing.columns == 5)
        sizing.update(width: 1050, windowWidth: 1250, target: 170, spacing: 16)
        #expect(sizing.referenceWidth == 1000)
        #expect(sizing.columns == 5)
    }

    @Test("修改卡片大小时按当前内容宽度建立新基准")
    func userScaleRebases() {
        var sizing = CardGridSizing()
        sizing.update(width: 750, windowWidth: 1000, target: 170, spacing: 16)
        sizing.update(width: 750, windowWidth: 1000, target: 238, spacing: 16, force: true)
        #expect(sizing.columns == 3)
        #expect(sizing.scale(spacing: 16) == 1)
    }

    @Test("没有侧边栏的页面仍按内容宽度自适应")
    func compactResizeRemainsAdaptive() {
        var sizing = CardGridSizing()
        sizing.update(width: 366, windowWidth: 0, target: 104, spacing: 12)
        #expect(sizing.columns == 3)
        sizing.update(width: 500, windowWidth: 0, target: 104, spacing: 12)
        #expect(sizing.columns == 4)
        #expect(sizing.scale(spacing: 12) == 1)
    }
}
