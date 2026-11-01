#ifndef C_VIRTUAL_DISPLAY_BRIDGE_H
#define C_VIRTUAL_DISPLAY_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 桥接层错误码.
typedef enum {
    VDX_STATUS_OK = 0,
    VDX_STATUS_UNAVAILABLE = 1,
    VDX_STATUS_INVALID_ARGUMENT = 2,
    VDX_STATUS_CREATE_FAILED = 3,
    VDX_STATUS_APPLY_FAILED = 4,
    VDX_STATUS_INVALID_DISPLAY_ID = 5,
} VDXStatus;

/// 虚拟屏可用的显示模式.
typedef struct {
    uint32_t width;
    uint32_t height;
    double refresh_rate;
} VDXDisplayMode;

/// 桥接层错误信息, message 始终以 NUL 结尾.
typedef struct {
    VDXStatus status;
    char message[512];
} VDXError;

/// 虚拟屏句柄, 由 VDXDisplayCreate 返回, 用 VDXDisplayDestroy 释放.
typedef void *VDXDisplayHandle;

/// 当前系统是否提供 CGVirtualDisplay 私有类.
bool VDXBridgeIsAvailable(void);

/// 创建一块虚拟屏.
///
/// name 为显示名称, max_pixels_* 为最大像素尺寸, size_mm_* 为物理尺寸(毫米),
/// modes 为声明的显示模式列表, hi_dpi 非 0 时开启 HiDPI.
/// 成功时返回非 NULL 句柄, 失败时返回 NULL 并填充 error.
VDXDisplayHandle VDXDisplayCreate(const char *name,
                                  uint32_t max_pixels_wide,
                                  uint32_t max_pixels_high,
                                  double size_mm_wide,
                                  double size_mm_high,
                                  uint32_t serial_number,
                                  uint32_t product_id,
                                  uint32_t vendor_id,
                                  const VDXDisplayMode *modes,
                                  size_t mode_count,
                                  uint32_t hi_dpi,
                                  VDXError *error);

/// 返回虚拟屏对应的 CGDirectDisplayID, 无效句柄返回 0.
uint32_t VDXDisplayGetID(VDXDisplayHandle handle);

/// 销毁虚拟屏, 句柄失效后不可再使用.
void VDXDisplayDestroy(VDXDisplayHandle handle);

#ifdef __cplusplus
}
#endif

#endif
