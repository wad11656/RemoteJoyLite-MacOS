#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#include <SDL3/SDL.h>
#include <SDL3/SDL_video.h>
#include <stdlib.h>

extern "C" void RemoteJoyLiteToggleRecording(void);
extern "C" void RemoteJoyLiteToggleTitlebarOnHover(void);
extern "C" void MacRevealRecordingFolder(const char *path);
extern "C" void MacShowToastMessage(const char *message);

static NSWindow *sWindow = nil;
static NSMenuItem *sTitlebarItem = nil;
static NSMenuItem *sRecordItem = nil;
static NSTrackingArea *sTrackingArea = nil;
static NSView *sDragRegionView = nil;
static BOOL sMouseInsideWindow = NO;
static BOOL sTitlebarOnHoverEnabled = YES;

@interface RemoteJoyLiteDragView : NSView
@end

@implementation RemoteJoyLiteDragView
- (BOOL)mouseDownCanMoveWindow
{
  return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  (void)event;
  return YES;
}
@end

@interface RemoteJoyLiteToastController : NSObject
{
  NSWindow *_toastWindow;
  NSVisualEffectView *_backdropView;
  NSTextField *_label;
  NSUInteger _generation;
}

- (void)showMessage:(NSString *)message;
@end

@implementation RemoteJoyLiteToastController

- (void)dealloc
{
  [_label release];
  [_backdropView release];
  [_toastWindow release];
  [super dealloc];
}

- (void)ensureToastWindow
{
  if (_toastWindow != nil)
  {
    return;
  }

  NSRect frame = NSMakeRect(0, 0, 900, 150);
  NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  [window setOpaque:NO];
  [window setBackgroundColor:[NSColor clearColor]];
  [window setHasShadow:NO];
  [window setLevel:NSStatusWindowLevel];
  [window setIgnoresMouseEvents:YES];
  [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorTransient];
  [window setReleasedWhenClosed:NO];
  [window setAlphaValue:0.0];

  NSView *contentView = [[NSView alloc] initWithFrame:frame];
  [contentView setWantsLayer:YES];
  [contentView.layer setBackgroundColor:[[NSColor clearColor] CGColor]];

  NSRect backdropFrame = NSMakeRect(18.0, 18.0, frame.size.width - 36.0, frame.size.height - 36.0);
  NSVisualEffectView *backdropView = [[NSVisualEffectView alloc] initWithFrame:backdropFrame];
  [backdropView setMaterial:NSVisualEffectMaterialHUDWindow];
  [backdropView setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
  [backdropView setState:NSVisualEffectStateActive];
  [backdropView setWantsLayer:YES];
  [backdropView.layer setCornerRadius:24.0];
  [backdropView.layer setMasksToBounds:YES];
  [backdropView.layer setBorderWidth:0.0];
  [backdropView.layer setShadowOpacity:0.0];

  NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, backdropFrame.size.width, backdropFrame.size.height)];
  [label setEditable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setSelectable:NO];
  [label setFont:[NSFont systemFontOfSize:42.0 weight:NSFontWeightSemibold]];
  [label setTextColor:[NSColor whiteColor]];
  [label setAlignment:NSTextAlignmentCenter];
  [label setUsesSingleLineMode:YES];
  [label setLineBreakMode:NSLineBreakByTruncatingTail];
  [label setStringValue:@""];
  [label setShadow:[[[NSShadow alloc] init] autorelease]];
  [[label shadow] setShadowColor:[[NSColor blackColor] colorWithAlphaComponent:0.55]];
  [[label shadow] setShadowBlurRadius:3.0];
  [[label shadow] setShadowOffset:NSMakeSize(0.0, -1.0)];

  [backdropView addSubview:label];
  [contentView addSubview:backdropView];
  [window setContentView:contentView];
  [contentView release];

  _backdropView = [backdropView retain];
  _label = [label retain];
  _toastWindow = [window retain];
  [window release];
  [backdropView release];
  [label release];
}

- (void)showMessage:(NSString *)message
{
  if (message == nil || [message length] == 0)
  {
    return;
  }

  [self ensureToastWindow];
  [_label setStringValue:message];

  NSSize textSize = [_label.attributedStringValue boundingRectWithSize:NSMakeSize(760.0, 120.0)
                                                               options:NSStringDrawingUsesLineFragmentOrigin |
                                                                       NSStringDrawingUsesFontLeading]
                        .size;
  CGFloat width = MIN(1100.0, MAX(700.0, ceil(textSize.width) + 160.0));
  CGFloat height = 160.0;

  NSScreen *screen = sWindow != nil ? [sWindow screen] : [NSScreen mainScreen];
  NSRect visibleFrame = screen != nil ? [screen visibleFrame] : NSMakeRect(0, 0, 1440, 900);
  CGFloat x = floor(NSMidX(visibleFrame) - (width / 2.0));
  CGFloat y = floor(NSMinY(visibleFrame) + 34.0);

  [_toastWindow setFrame:NSMakeRect(x, y, width, height) display:YES];
  [[_toastWindow contentView] setFrame:NSMakeRect(0, 0, width, height)];
  NSRect backdropFrame = NSMakeRect(18.0, 18.0, width - 36.0, height - 36.0);
  [_backdropView setFrame:backdropFrame];
  [_label setFrame:NSMakeRect(0, floor((backdropFrame.size.height - ceil(textSize.height)) / 2.0), backdropFrame.size.width,
                               ceil(textSize.height))];

  _generation += 1;
  NSUInteger generation = _generation;
  [_toastWindow orderFrontRegardless];
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    [context setDuration:0.14];
    [[_toastWindow animator] setAlphaValue:1.0];
  } completionHandler:nil];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (generation != _generation || _toastWindow == nil)
    {
      return;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
      [context setDuration:0.22];
      [[_toastWindow animator] setAlphaValue:0.0];
    } completionHandler:^{
      if (generation == _generation)
      {
        [_toastWindow orderOut:nil];
      }
    }];
  });
}
@end

static RemoteJoyLiteToastController *sToastController = nil;

@interface RemoteJoyLiteVideoRecorder : NSObject
{
  AVAssetWriter *_writer;
  AVAssetWriterInput *_input;
  AVAssetWriterInputPixelBufferAdaptor *_adaptor;
  dispatch_queue_t _encodeQueue;
  dispatch_semaphore_t _frameSlots;
  NSURL *_outputURL;
  NSString *_outputFolder;
  BOOL _recording;
  CFAbsoluteTime _startTime;
  CMTime _lastPTS;
}

- (BOOL)startWithWidth:(int)width height:(int)height;
- (void)appendFramePixels:(const void *)pixels width:(int)width height:(int)height pitch:(int)pitch pixelFormat:(SDL_PixelFormat)pixelFormat captureTicks:(Uint64)captureTicks;
- (void)appendCapturedFrameData:(NSData *)frameData width:(int)width height:(int)height pitch:(int)pitch pixelFormat:(SDL_PixelFormat)pixelFormat pts:(CMTime)pts;
- (void)finishRecording;
- (NSString *)outputFolder;
- (NSURL *)outputURL;
@end

@implementation RemoteJoyLiteVideoRecorder

- (void)dealloc
{
  [_input release];
  [_adaptor release];
  [_writer release];
  [_outputURL release];
  [_outputFolder release];
  [super dealloc];
}

- (NSString *)moviesDirectory
{
  NSArray<NSString *> *movies = NSSearchPathForDirectoriesInDomains(NSMoviesDirectory, NSUserDomainMask, YES);
  if (movies.count > 0)
  {
    return movies[0];
  }
  return [NSHomeDirectory() stringByAppendingPathComponent:@"Movies"];
}

- (NSString *)timestampString
{
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
  [formatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
  NSString *stamp = [formatter stringFromDate:[NSDate date]];
  [formatter release];
  return stamp;
}

- (BOOL)startWithWidth:(int)width height:(int)height
{
  if (_recording)
  {
    return YES;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *movies = [self moviesDirectory];
  NSString *folder = [movies stringByAppendingPathComponent:@"RemoteJoyLite"];
  NSError *error = nil;
  if (![fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error])
  {
    NSLog(@"RemoteJoyLite: failed to create recording folder %@: %@", folder, error);
    return NO;
  }

  NSString *stamp = [self timestampString];
  NSString *filename = [NSString stringWithFormat:@"RemoteJoyLite-%@.mp4", stamp];
  NSString *fullPath = [folder stringByAppendingPathComponent:filename];
  NSURL *url = [NSURL fileURLWithPath:fullPath];

  NSDictionary *settings =
      @{ AVVideoCodecKey : AVVideoCodecTypeH264, AVVideoWidthKey : @(width), AVVideoHeightKey : @(height) };

  AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:&error];
  if (writer == nil)
  {
    NSLog(@"RemoteJoyLite: failed to create writer for %@: %@", url, error);
    return NO;
  }

  AVAssetWriterInput *input = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:settings];
  [input setExpectsMediaDataInRealTime:YES];

  NSDictionary *attributes =
      @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
         (id)kCVPixelBufferWidthKey : @(width),
         (id)kCVPixelBufferHeightKey : @(height),
         (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
         (id)kCVPixelBufferCGImageCompatibilityKey : @YES,
         (id)kCVPixelBufferIOSurfacePropertiesKey : @{} };

  AVAssetWriterInputPixelBufferAdaptor *adaptor =
      [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:input
                                                  sourcePixelBufferAttributes:attributes];

  if (![writer canAddInput:input])
  {
    NSLog(@"RemoteJoyLite: writer rejected input");
    [adaptor release];
    [input release];
    [writer release];
    return NO;
  }

  [writer addInput:input];
  if (![writer startWriting])
  {
    NSLog(@"RemoteJoyLite: startWriting failed: %@", [writer error]);
    [adaptor release];
    [input release];
    [writer release];
    return NO;
  }

  [writer startSessionAtSourceTime:kCMTimeZero];

  [_outputFolder release];
  _outputFolder = [folder copy];
  [_outputURL release];
  _outputURL = [url retain];
  [_writer release];
  _writer = writer;
  [_input release];
  _input = input;
  [_adaptor release];
  _adaptor = adaptor;
  _encodeQueue = dispatch_queue_create("com.psparchive.RemoteJoyLite.recording", DISPATCH_QUEUE_SERIAL);
  _frameSlots = dispatch_semaphore_create(3);
  _recording = YES;
  _startTime = CFAbsoluteTimeGetCurrent();
  _lastPTS = kCMTimeZero;
  return YES;
}

- (void)appendFramePixels:(const void *)pixels width:(int)width height:(int)height pitch:(int)pitch pixelFormat:(SDL_PixelFormat)pixelFormat captureTicks:(Uint64)captureTicks
{
  if (!_recording || pixels == NULL || _writer == nil || _input == nil || _adaptor == nil)
  {
    return;
  }

  if (width <= 0 || height <= 0)
  {
    return;
  }

  if (_frameSlots != nil && dispatch_semaphore_wait(_frameSlots, DISPATCH_TIME_NOW) != 0)
  {
    return;
  }

  const int rowBytes = pitch;
  NSData *frameData = [[NSData alloc] initWithBytes:pixels length:(size_t)rowBytes * (size_t)height];

  RemoteJoyLiteVideoRecorder *recorder = [self retain];
  NSData *capturedFrame = [frameData retain];
  int frameWidth = width;
  int frameHeight = height;
  int framePitch = rowBytes;
  SDL_PixelFormat frameFormat = pixelFormat;
  CMTime pts = CMTimeMake((int64_t)captureTicks, 1000000000);
  dispatch_async(_encodeQueue, ^{
    [recorder appendCapturedFrameData:capturedFrame width:frameWidth height:frameHeight pitch:framePitch pixelFormat:frameFormat pts:pts];
    if (recorder->_frameSlots != nil)
    {
      dispatch_semaphore_signal(recorder->_frameSlots);
    }
    [capturedFrame release];
    [recorder release];
  });
  [frameData release];
}

- (void)appendCapturedFrameData:(NSData *)frameData width:(int)width height:(int)height pitch:(int)pitch pixelFormat:(SDL_PixelFormat)pixelFormat pts:(CMTime)pts
{
  if (!_recording || frameData == nil || _writer == nil || _input == nil || _adaptor == nil)
  {
    return;
  }

  if (_adaptor.pixelBufferPool == nil)
  {
    return;
  }

  if (![_input isReadyForMoreMediaData])
  {
    return;
  }

  CVPixelBufferRef buffer = NULL;
  CVReturn ret = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _adaptor.pixelBufferPool, &buffer);
  if (ret != kCVReturnSuccess || buffer == NULL)
  {
    return;
  }

  CVPixelBufferLockBaseAddress(buffer, 0);
  uint8_t *dst = (uint8_t *)CVPixelBufferGetBaseAddress(buffer);
  size_t dstPitch = CVPixelBufferGetBytesPerRow(buffer);
  if (!SDL_ConvertPixels(width, height, pixelFormat, [frameData bytes], pitch, SDL_PIXELFORMAT_BGRA32, dst, (int)dstPitch))
  {
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    CVPixelBufferRelease(buffer);
    NSLog(@"RemoteJoyLite: pixel conversion failed");
    return;
  }

  CVPixelBufferUnlockBaseAddress(buffer, 0);

  if (CMTIME_COMPARE_INLINE(pts, <=, _lastPTS))
  {
    pts = CMTimeAdd(_lastPTS, CMTimeMake(1, 600));
  }

  if (![_adaptor appendPixelBuffer:buffer withPresentationTime:pts])
  {
    NSLog(@"RemoteJoyLite: failed to append frame: %@", [_writer error]);
  }
  else
  {
    _lastPTS = pts;
  }

  CVPixelBufferRelease(buffer);
}

- (void)finishRecording
{
  if (!_recording)
  {
    return;
  }

  _recording = NO;
  if (_encodeQueue != nil)
  {
    dispatch_sync(_encodeQueue, ^{});
  }
  [_input markAsFinished];

  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  [_writer finishWritingWithCompletionHandler:^{
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

  if (_writer.status == AVAssetWriterStatusCompleted && _outputURL != nil)
  {
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ _outputURL ]];
  }
  else
  {
    NSLog(@"RemoteJoyLite: recording failed to finish cleanly: %@", [_writer error]);
  }

  [_input release];
  _input = nil;
  [_adaptor release];
  _adaptor = nil;
  [_writer release];
  _writer = nil;
  _frameSlots = nil;
  _encodeQueue = nil;
  [_outputURL release];
  _outputURL = nil;
  [_outputFolder release];
  _outputFolder = nil;
}

- (NSString *)outputFolder
{
  return _outputFolder;
}

- (NSURL *)outputURL
{
  return _outputURL;
}

@end

static RemoteJoyLiteVideoRecorder *sRecorder = nil;

@interface RemoteJoyLiteMenuTarget : NSObject
@end

@implementation RemoteJoyLiteMenuTarget
- (void)toggleRecording:(id)sender
{
  RemoteJoyLiteToggleRecording();
}

- (void)toggleTitlebarOnHover:(id)sender
{
  RemoteJoyLiteToggleTitlebarOnHover();
}
@end

static RemoteJoyLiteMenuTarget *sTarget = nil;

@interface RemoteJoyLiteWindowDelegate : NSObject <NSWindowDelegate>
@end

static void SetTrafficLightVisibility(NSWindow *window, BOOL visible);
static void InstallHoverTracking(NSWindow *window);
static void ApplyWindowChrome(NSWindow *nsWindow, BOOL titlebar_on_hover);
static void UpdateDragRegion(NSWindow *nsWindow, BOOL titlebar_on_hover);

@implementation RemoteJoyLiteWindowDelegate
- (void)mouseEntered:(NSEvent *)event
{
  (void)event;
  if (!sTitlebarOnHoverEnabled)
  {
    return;
  }
  sMouseInsideWindow = YES;
  SetTrafficLightVisibility(sWindow, YES);
}

- (void)mouseExited:(NSEvent *)event
{
  (void)event;
  if (!sTitlebarOnHoverEnabled)
  {
    return;
  }
  sMouseInsideWindow = NO;
  SetTrafficLightVisibility(sWindow, NO);
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
  (void)notification;
  if (sWindow != nil)
  {
    [sWindow setTitlebarAppearsTransparent:YES];
    [sWindow setTitleVisibility:NSWindowTitleHidden];
    SetTrafficLightVisibility(sWindow, NO);
  }
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
  (void)notification;
  if (sWindow != nil)
  {
    ApplyWindowChrome(sWindow, sTitlebarOnHoverEnabled);
  }
}

- (void)windowDidResize:(NSNotification *)notification
{
  (void)notification;
  if (sWindow != nil)
  {
    ApplyWindowChrome(sWindow, sTitlebarOnHoverEnabled);
  }
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
  (void)notification;
  if (sWindow != nil && sTitlebarOnHoverEnabled && sMouseInsideWindow)
  {
    [self mouseEntered:nil];
  }
}

- (void)windowDidResignKey:(NSNotification *)notification
{
  (void)notification;
  if (sWindow != nil && sTitlebarOnHoverEnabled)
  {
    [self mouseExited:nil];
  }
}
@end

static RemoteJoyLiteWindowDelegate *sDelegate = nil;

static NSWindow *GetWindow(SDL_Window *window)
{
  SDL_PropertiesID props = SDL_GetWindowProperties(window);
  return (NSWindow *)SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
}

static void SetTrafficLightVisibility(NSWindow *window, BOOL visible)
{
  if (window == nil)
  {
    return;
  }

  NSButton *closeButton = [window standardWindowButton:NSWindowCloseButton];
  NSButton *minimizeButton = [window standardWindowButton:NSWindowMiniaturizeButton];
  NSButton *zoomButton = [window standardWindowButton:NSWindowZoomButton];

  [closeButton setHidden:!visible];
  [minimizeButton setHidden:!visible];
  [zoomButton setHidden:!visible];
}

static void InstallHoverTracking(NSWindow *window)
{
  if (window == nil)
  {
    return;
  }

  NSView *contentView = [window contentView];
  if (contentView == nil)
  {
    return;
  }

  if (sTrackingArea != nil)
  {
    [contentView removeTrackingArea:sTrackingArea];
    sTrackingArea = nil;
  }

  NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect;
  sTrackingArea = [[NSTrackingArea alloc] initWithRect:[contentView bounds] options:options owner:sDelegate userInfo:nil];
  [contentView addTrackingArea:sTrackingArea];
}

static void UpdateDragRegion(NSWindow *nsWindow, BOOL titlebar_on_hover)
{
  if (nsWindow == nil)
  {
    return;
  }

  NSView *contentView = [nsWindow contentView];
  if (contentView == nil)
  {
    return;
  }

  if (sDragRegionView != nil)
  {
    [sDragRegionView removeFromSuperview];
    [sDragRegionView release];
    sDragRegionView = nil;
  }

  if (titlebar_on_hover)
  {
    return;
  }

  NSRect bounds = [contentView bounds];
  CGFloat dragHeight = MIN(50.0, NSHeight(bounds));
  CGFloat buttonInset = 96.0;
  CGFloat dragWidth = MAX(0.0, NSWidth(bounds) - buttonInset);
  if (dragWidth <= 0.0 || dragHeight <= 0.0)
  {
    return;
  }

  NSRect dragFrame = NSMakeRect(buttonInset, NSHeight(bounds) - dragHeight, dragWidth, dragHeight);
  RemoteJoyLiteDragView *dragView = [[RemoteJoyLiteDragView alloc] initWithFrame:dragFrame];
  [dragView setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [dragView setWantsLayer:NO];
  [contentView addSubview:dragView];
  sDragRegionView = dragView;
}

static NSMenu *WindowMenu(NSMenu *mainMenu)
{
  for (NSMenuItem *item in [mainMenu itemArray])
  {
    if ([[item title] isEqualToString:@"Window"])
    {
      if ([item submenu] != nil)
      {
        return [item submenu];
      }
    }
  }

  NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Window"];
  [windowItem setSubmenu:menu];
  [mainMenu addItem:windowItem];

  NSMenuItem *closeItem = [[NSMenuItem alloc] initWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
  [menu addItem:closeItem];

  NSMenuItem *minimizeItem =
      [[NSMenuItem alloc] initWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
  [menu addItem:minimizeItem];

  NSMenuItem *zoomItem = [[NSMenuItem alloc] initWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
  [menu addItem:zoomItem];

  [menu addItem:[NSMenuItem separatorItem]];
  return menu;
}

extern "C" void MacInstallMenus(void)
{
  @autoreleasepool
  {
    if (sTarget == nil)
    {
      sTarget = [RemoteJoyLiteMenuTarget new];
    }

    if (sDelegate == nil)
    {
      sDelegate = [RemoteJoyLiteWindowDelegate new];
    }

    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];

    NSMenu *mainMenu = [app mainMenu];
    if (mainMenu == nil)
    {
      mainMenu = [[NSMenu alloc] initWithTitle:@""];
      [app setMainMenu:mainMenu];
    }

    NSMenu *windowMenu = WindowMenu(mainMenu);
    [app setWindowsMenu:windowMenu];

    if (sRecordItem == nil)
    {
      sRecordItem = [[NSMenuItem alloc] initWithTitle:@"Record" action:@selector(toggleRecording:) keyEquivalent:@""];
      [sRecordItem setTarget:sTarget];
      [sRecordItem setKeyEquivalent:@"r"];
      [sRecordItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
      [windowMenu addItem:sRecordItem];
    }

    [app activateIgnoringOtherApps:YES];
  }
}

extern "C" void MacSetTitlebarMenuState(int enabled)
{
  @autoreleasepool
  {
    if (sTitlebarItem != nil)
    {
      [sTitlebarItem setState:enabled ? NSControlStateValueOn : NSControlStateValueOff];
    }
  }
}

extern "C" void MacSetRecordingMenuState(int recording)
{
  @autoreleasepool
  {
    if (sRecordItem != nil)
    {
      [sRecordItem setTitle:recording ? @"Stop Recording" : @"Record"];
    }
  }
}

extern "C" void MacApplyWindowChrome(SDL_Window *window, int titlebar_on_hover)
{
  @autoreleasepool
  {
    NSWindow *nsWindow = GetWindow(window);
    if (nsWindow == nil)
    {
      return;
    }

    sWindow = nsWindow;
    sTitlebarOnHoverEnabled = titlebar_on_hover ? YES : NO;
    [nsWindow setDelegate:sDelegate];
    InstallHoverTracking(nsWindow);
    ApplyWindowChrome(nsWindow, sTitlebarOnHoverEnabled);

    [nsWindow makeKeyAndOrderFront:nil];
  }
}

static void ApplyWindowChrome(NSWindow *nsWindow, BOOL titlebar_on_hover)
{
  if (nsWindow == nil)
  {
    return;
  }

  if (titlebar_on_hover)
  {
    NSWindowStyleMask mask = [nsWindow styleMask];
    mask |= NSWindowStyleMaskTitled;
    mask |= NSWindowStyleMaskResizable;
    mask |= NSWindowStyleMaskFullSizeContentView;
    mask &= ~NSWindowStyleMaskBorderless;

    [nsWindow setStyleMask:mask];
    [nsWindow setTitleVisibility:NSWindowTitleHidden];
    [nsWindow setTitlebarAppearsTransparent:YES];
    [nsWindow setMovableByWindowBackground:YES];
    SetTrafficLightVisibility(nsWindow, sMouseInsideWindow);
  }
  else
  {
    NSWindowStyleMask mask = [nsWindow styleMask];
    mask |= NSWindowStyleMaskResizable;
    mask &= ~NSWindowStyleMaskTitled;
    mask &= ~NSWindowStyleMaskFullSizeContentView;

    [nsWindow setStyleMask:mask];
    [nsWindow setTitlebarAppearsTransparent:NO];
    [nsWindow setTitleVisibility:NSWindowTitleVisible];
    [nsWindow setMovableByWindowBackground:NO];
    SetTrafficLightVisibility(nsWindow, YES);
  }

  UpdateDragRegion(nsWindow, titlebar_on_hover);
}

extern "C" int MacStartRecording(int width, int height)
{
  @autoreleasepool
  {
    if (sRecorder == nil)
    {
      sRecorder = [RemoteJoyLiteVideoRecorder new];
    }
    return [sRecorder startWithWidth:width height:height] ? 1 : 0;
  }
}

extern "C" void MacAppendRecordingFrame(const void *pixels, int width, int height, int pitch, SDL_PixelFormat format,
                                        Uint64 capture_ticks_ns)
{
  @autoreleasepool
  {
    if (sRecorder != nil)
    {
      [sRecorder appendFramePixels:pixels width:width height:height pitch:pitch pixelFormat:format
                        captureTicks:capture_ticks_ns];
    }
  }
}

extern "C" void MacStopRecording(void)
{
  @autoreleasepool
  {
    if (sRecorder != nil)
    {
      [sRecorder finishRecording];
    }
  }
}

extern "C" void MacShowToastMessage(const char *message)
{
  @autoreleasepool
  {
    if (message == NULL || message[0] == '\0')
    {
      return;
    }

    NSString *text = [NSString stringWithUTF8String:message];
    if (text == nil)
    {
      return;
    }

    if (sToastController == nil)
    {
      sToastController = [RemoteJoyLiteToastController new];
    }

    [sToastController showMessage:text];
  }
}

extern "C" void MacRevealRecordingFolder(const char *path)
{
  @autoreleasepool
  {
    if (path == NULL || path[0] == '\0')
    {
      return;
    }

    NSString *folder = [NSString stringWithUTF8String:path];
    if (folder == nil)
    {
      return;
    }

    NSURL *url = [NSURL fileURLWithPath:folder];
    if (url == nil)
    {
      return;
    }

    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ url ]];
  }
}
