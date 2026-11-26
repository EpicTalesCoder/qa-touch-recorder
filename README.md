# QA Touch Recorder (`QATouchRecorder.dylib`)

Thư viện `.dylib` **viết mới hoàn toàn từ đầu** cho iOS 16.x+ (`arm64`, non-jailbreak), phục vụ **QA / Debug UI nội bộ**:

- **Không can thiệp bộ nhớ**, không `mach_vm_*` / `libkrw` / `libkernrw`.
- **Không** phụ thuộc `CydiaSubstrate`, `ElleKit` hay `Substitute`.
- **Không** vượt DRM, không giả mạo định danh, không dùng private `IOHIDEvent` / `BKSHIDEvent` SPI.

## Phạm vi sử dụng & Cam kết phi thương mại (Debug / QA Only)

- Chỉ sử dụng cho mục đích debug, kiểm thử chất lượng (QA) trên các bản build thuộc quyền sở hữu hoặc được cấp phép kiểm thử hợp lệ.
- Tuyệt đối không sử dụng để can thiệp, gian lận hay tác động tới game/ứng dụng hoặc dịch vụ trực tuyến của bên thứ ba.
- Cam kết không sử dụng vào mục đích thương mại, mua bán hay phân phối lại kiếm lợi nhuận.

## Tính năng hiện có

1. **Menu nổi `QA` (Floating Overlay)**:
   - Nút nổi kéo-thả tự do trong vùng Safe Area của iPhone XS Max (`414×896 pt @3x`, Notch `44 pt` / Home Indicator `34 pt`).
   - Cửa sổ overlay `QATouchOverlayWindow` cho phép xuyên chạm bình thường xuống ứng dụng bên dưới và tự loại trừ mọi thao tác bấm nút/menu QA khỏi quá trình ghi.
2. **Ghi thao tác Chạm (`Tap`) & Vuốt (`Swipe`)**:
   - Quan sát sự kiện chạm chuẩn của `UIWindow` (`sendEvent:`) trong chính tiến trình app khi bật chế độ **Ghi**.
   - Tự phân loại `Tap` (độ dịch chuyển `< 12 pt`) và `Swipe` (độ dịch chuyển `>= 12 pt` kèm waypoints), lưu khoảng trễ (`delayBefore`) và thời lượng (`duration`).
3. **Phát lại & Lặp lại (`1x`, `3x`, `5x`, `10x`, `∞`) + Tốc độ (`0.5x`–`2x`)**:
   - Đánh dấu trực quan (vòng tròn Tap / đường dẫn Swipe) trên lớp overlay khi phát.
   - Lưu/tải/xóa kịch bản JSON tại `Documents/QATouchScripts/` trong sandbox app.

## Giới hạn kỹ thuật minh bạch trên iOS chưa Jailbreak

Do sử dụng **100% API công khai của UIKit** (an toàn trên iOS 16.x, không dùng private SPI dễ crash):

- **Hỗ trợ tốt**: `UIControl` (`UIButton`, `UISwitch`, `UISegmentedControl`, `UISlider`), `UITextField` / `UITextView`, `UITableViewCell`, `UICollectionViewCell`, `UIScrollView` (cuộn dọc/ngang và `pagingEnabled`), và các view hỗ trợ `accessibilityActivate`.
- **Không tự tổng hợp được chạm phần cứng mức thấp** cho canvas Metal/Unity/SpriteKit thuần, `WKWebView` DOM thuần, hoặc các view chỉ lắng nghe `touchesBegan:`/`UIGestureRecognizer` tùy biến không qua `UIControl`/`accessibilityActivate` (những trường hợp đó cần `XCUITest` runner).

## Kiểm thử & Build ra `.dylib` / `.deb`

```bash
# 1. Chạy unit test model + self-test trình đóng gói .deb trên macOS:
./build.sh test

# 2. Biên dịch QATouchRecorder.dylib (arm64, iOS 16.0+) và đóng gói .deb (cần Xcode iPhoneOS SDK):
./build.sh deb
# -> Đầu ra:
#    obj/QATouchRecorder.dylib
#    packages/com.local.qa-touch-recorder_0.1.0_iphoneos-arm.deb

# 3. Hoặc tự động build qua GitHub Actions (macos-15):
#    .github/workflows/build-deb.yml
```

> Lưu ý khi dùng với **ESign + TrollStore**: gói `.deb` đóng gói không chứa `Depends: mobilesubstrate`, đặt `QATouchRecorder.dylib` và `QATouchRecorder.plist` chuẩn dưới `Library/MobileSubstrate/DynamicLibraries/` để ESign tự trích xuất hoặc có thể inject thẳng file `QATouchRecorder.dylib`.
