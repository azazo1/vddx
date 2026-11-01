#import "CVirtualDisplayBridge.h"

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

NS_ASSUME_NONNULL_BEGIN

/// 进程内共享的串行队列, 交给 CGVirtualDisplayDescriptor 用于内部回调.
static dispatch_queue_t VDXBridgeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_queue_attr_t attr =
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        queue = dispatch_queue_create("dev.vddx.virtual-display", attr);
    });
    return queue;
}

static void VDXFillError(VDXError *_Nullable error, VDXStatus status, NSString *message) {
    if (error == NULL) {
        return;
    }
    error->status = status;
    const char *text = message.UTF8String;
    strlcpy(error->message, text != NULL ? text : "", sizeof(error->message));
}

/// 只有存在对应 selector 时才调用, 避免私有类版本差异导致崩溃.
static void VDXSetUInt(id target, NSString *selectorName, uint32_t value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) {
        return;
    }
    ((void (*)(id, SEL, uint32_t))objc_msgSend)(target, selector, value);
}

static void VDXSetSize(id target, NSString *selectorName, CGSize value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) {
        return;
    }
    ((void (*)(id, SEL, CGSize))objc_msgSend)(target, selector, value);
}

static void VDXSetPoint(id target, NSString *selectorName, CGPoint value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) {
        return;
    }
    ((void (*)(id, SEL, CGPoint))objc_msgSend)(target, selector, value);
}

static void VDXSetObject(id target, NSString *selectorName, id value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) {
        return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(target, selector, value);
}

#pragma mark - 句柄

@interface VDXDisplayBox : NSObject
@property (nonatomic, strong) id display;
@property (nonatomic, assign) uint32_t displayID;
@end

@implementation VDXDisplayBox
@end

#pragma mark - 存活注册表

// 进程内所有未销毁的虚拟屏. 进程正常退出 (exit/atexit) 时兜底统一销毁,
// 避免 Swift 对象释放顺序或异常终止路径留下残留的虚拟屏.
static NSMutableSet<VDXDisplayBox *> *gLiveBoxes;
static dispatch_once_t gLiveBoxesOnce;

static void VDXDestroyAllLiveBoxes(void);

static NSMutableSet<VDXDisplayBox *> *VDXLiveBoxes(void) {
    dispatch_once(&gLiveBoxesOnce, ^{
        gLiveBoxes = [NSMutableSet set];
        atexit(VDXDestroyAllLiveBoxes);
    });
    return gLiveBoxes;
}

static void VDXDestroyAllLiveBoxes(void) {
    @synchronized (VDXDisplayBox.class) {
        NSMutableSet<VDXDisplayBox *> *boxes = gLiveBoxes;
        if (boxes == nil) {
            return;
        }
        NSArray<VDXDisplayBox *> *snapshot = [boxes allObjects];
        [boxes removeAllObjects];
        gLiveBoxes = nil;
        for (VDXDisplayBox *box in snapshot) {
            box.display = nil;
        }
    }
}

#pragma mark - 公开接口

bool VDXBridgeIsAvailable(void) {
    return objc_getClass("CGVirtualDisplay") != NULL &&
           objc_getClass("CGVirtualDisplayDescriptor") != NULL &&
           objc_getClass("CGVirtualDisplayMode") != NULL &&
           objc_getClass("CGVirtualDisplaySettings") != NULL;
}

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
                                  VDXError *error) {
    if (name == NULL || modes == NULL || mode_count == 0) {
        VDXFillError(error, VDX_STATUS_INVALID_ARGUMENT, @"显示名称与显示模式不能为空");
        return NULL;
    }
    if (!VDXBridgeIsAvailable()) {
        VDXFillError(error, VDX_STATUS_UNAVAILABLE, @"当前系统不提供 CGVirtualDisplay 私有接口");
        return NULL;
    }

    Class descriptorClass = objc_getClass("CGVirtualDisplayDescriptor");
    Class displayClass = objc_getClass("CGVirtualDisplay");
    Class modeClass = objc_getClass("CGVirtualDisplayMode");
    Class settingsClass = objc_getClass("CGVirtualDisplaySettings");

    id descriptor = ((id (*)(id, SEL))objc_msgSend)(descriptorClass, @selector(new));
    if (descriptor == nil) {
        VDXFillError(error, VDX_STATUS_CREATE_FAILED, @"无法实例化 CGVirtualDisplayDescriptor");
        return NULL;
    }

    NSString *displayName = [NSString stringWithUTF8String:name];
    VDXSetObject(descriptor, @"setName:", displayName ?: @"VDDX");
    VDXSetObject(descriptor, @"setDispatchQueue:", VDXBridgeQueue());
    VDXSetUInt(descriptor, @"setMaxPixelsWide:", MAX(max_pixels_wide, 1));
    VDXSetUInt(descriptor, @"setMaxPixelsHigh:", MAX(max_pixels_high, 1));
    VDXSetSize(descriptor, @"setSizeInMillimeters:", CGSizeMake(size_mm_wide, size_mm_high));
    VDXSetUInt(descriptor, @"setSerialNum:", serial_number);
    VDXSetUInt(descriptor, @"setProductID:", product_id);
    VDXSetUInt(descriptor, @"setVendorID:", vendor_id);
    // sRGB / Rec.709 primaries, 与主流显示器一致.
    VDXSetPoint(descriptor, @"setRedPrimary:", CGPointMake(0.64, 0.33));
    VDXSetPoint(descriptor, @"setGreenPrimary:", CGPointMake(0.30, 0.60));
    VDXSetPoint(descriptor, @"setBluePrimary:", CGPointMake(0.15, 0.06));
    VDXSetPoint(descriptor, @"setWhitePoint:", CGPointMake(0.3127, 0.3290));

    id display = ((id (*)(id, SEL, id))objc_msgSend)(
        ((id (*)(id, SEL))objc_msgSend)(displayClass, @selector(alloc)),
        @selector(initWithDescriptor:),
        descriptor);
    if (display == nil) {
        VDXFillError(error, VDX_STATUS_CREATE_FAILED, @"CGVirtualDisplay 初始化失败");
        return NULL;
    }

    id settings = ((id (*)(id, SEL))objc_msgSend)(settingsClass, @selector(new));
    NSMutableArray<id> *modeObjects = [NSMutableArray arrayWithCapacity:mode_count];
    for (size_t index = 0; index < mode_count; index++) {
        VDXDisplayMode spec = modes[index];
        if (spec.width == 0 || spec.height == 0 || spec.refresh_rate <= 0) {
            continue;
        }
        id mode = ((id (*)(id, SEL, uint32_t, uint32_t, double))objc_msgSend)(
            ((id (*)(id, SEL))objc_msgSend)(modeClass, @selector(alloc)),
            @selector(initWithWidth:height:refreshRate:),
            spec.width,
            spec.height,
            spec.refresh_rate);
        if (mode != nil) {
            [modeObjects addObject:mode];
        }
    }
    if (modeObjects.count == 0) {
        VDXFillError(error, VDX_STATUS_INVALID_ARGUMENT, @"没有有效的显示模式");
        return NULL;
    }
    VDXSetObject(settings, @"setModes:", modeObjects);
    VDXSetUInt(settings, @"setHiDPI:", hi_dpi != 0 ? 1 : 0);

    BOOL applied = ((BOOL (*)(id, SEL, id))objc_msgSend)(display, @selector(applySettings:), settings);
    if (!applied) {
        VDXFillError(error, VDX_STATUS_APPLY_FAILED, @"applySettings 返回失败");
        return NULL;
    }

    uint32_t displayID = ((uint32_t (*)(id, SEL))objc_msgSend)(display, @selector(displayID));
    if (displayID == 0) {
        VDXFillError(error, VDX_STATUS_INVALID_DISPLAY_ID, @"applySettings 成功但 displayID 无效");
        return NULL;
    }

    VDXDisplayBox *box = [[VDXDisplayBox alloc] init];
    box.display = display;
    box.displayID = displayID;
    @synchronized (VDXDisplayBox.class) {
        [VDXLiveBoxes() addObject:box];
    }
    VDXFillError(error, VDX_STATUS_OK, @"");
    return (__bridge_retained void *)box;
}

uint32_t VDXDisplayGetID(VDXDisplayHandle handle) {
    if (handle == NULL) {
        return 0;
    }
    VDXDisplayBox *box = (__bridge VDXDisplayBox *)handle;
    return box.displayID;
}

void VDXDisplayDestroy(VDXDisplayHandle handle) {
    if (handle == NULL) {
        return;
    }
    VDXDisplayBox *box = (__bridge VDXDisplayBox *)handle;
    BOOL owned = NO;
    @synchronized (VDXDisplayBox.class) {
        NSMutableSet<VDXDisplayBox *> *boxes = gLiveBoxes;
        if (boxes != nil) {
            owned = [boxes containsObject:box];
            if (owned) {
                [boxes removeObject:box];
                // 立即释放底层虚拟屏, 而不是等对象 dealloc.
                box.display = nil;
            }
        }
    }
    // 只释放由 create 的 __bridge_retained 持有的那一份引用.
    // 若已被 atexit 统一处理, 这里不再 CFRelease, 避免重复释放.
    if (owned) {
        CFRelease(handle);
    }
}

NS_ASSUME_NONNULL_END
