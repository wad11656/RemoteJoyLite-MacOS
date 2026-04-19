#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#if __has_include(<AVFAudio/AVFAudio.h>)
#import <AVFAudio/AVFAudio.h>
#define HAS_AVFAUDIO 1
#else
#define HAS_AVFAUDIO 0
#endif
#import <AudioToolbox/AudioToolbox.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <math.h>

#include <SDL3/SDL.h>
#include <SDL3/SDL_video.h>
#include <stdlib.h>

#if __has_include(<ScreenCaptureKit/ScreenCaptureKit.h>)
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#define HAS_SCREENCAPTUREKIT 1
#else
#define HAS_SCREENCAPTUREKIT 0
#endif

extern "C" void RemoteJoyLiteToggleRecording(void);
extern "C" void RemoteJoyLiteSetRecordingQuality(int quality);
extern "C" int RemoteJoyLiteGetRecordingQuality(void);
extern "C" void RemoteJoyLiteToggleTitlebarOnHover(void);
extern "C" void MacRevealRecordingFolder(const char *path);
extern "C" void MacShowToastMessage(const char *message);

static BOOL HasScreenCapturePermission(void);
static void LoadMicrophonePreferences(void);
static void SaveMicrophonePreferences(void);
static void UpdateMicrophoneMenuState(void);
static NSString *CopyDefaultOutputDeviceUID(void);
static BOOL EnsureSingleInstance(void);

static NSWindow *sWindow = nil;
static NSMenuItem *sTitlebarItem = nil;
static NSMenuItem *sRecordingMenuItem = nil;
static NSMenuItem *sRecordingItem = nil;
static NSMenuItem *sHighQualityItem = nil;
static NSMenuItem *sMaxQualityItem = nil;
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
static NSString *sSelectedMicUID = nil;
static NSData *sSelectedMicSourceID = nil;
static BOOL sMicMuted = NO;
static BOOL sMicPrefsLoaded = NO;
static NSMenuItem *sMicHeaderItem = nil;
static NSMenuItem *sMicNoneItem = nil;
static NSMenuItem *sMicMuteItem = nil;
static NSMutableArray *sMicDeviceItems = nil;

static NSString *kMicSelectionPrefFile = @"recording_mic.txt";
static NSString *kMicSourceSelectionPrefFile = @"recording_mic_source.txt";
static NSString *kMicMutePrefFile = @"recording_mic_muted.txt";
@class RemoteJoyLiteVideoRecorder;
static RemoteJoyLiteVideoRecorder *sRecorder = nil;

static NSString *RecordingPrefsDirectory(void)
{
  char *prefPath = SDL_GetPrefPath("psparchive", "RemoteJoyLite");
  if (prefPath == NULL)
  {
    return nil;
  }

  NSString *path = [NSString stringWithUTF8String:prefPath];
  SDL_free(prefPath);
  return path;
}

static NSString *ReadPrefFile(NSString *filename)
{
  NSString *dir = RecordingPrefsDirectory();
  if (dir == nil)
  {
    return nil;
  }

  NSString *path = [dir stringByAppendingPathComponent:filename];
  NSError *error = nil;
  NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
  if (contents == nil)
  {
    return nil;
  }

  return [contents stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSData *ReadDataPrefFile(NSString *filename)
{
  NSString *dir = RecordingPrefsDirectory();
  if (dir == nil)
  {
    return nil;
  }

  NSString *path = [dir stringByAppendingPathComponent:filename];
  NSData *contents = [NSData dataWithContentsOfFile:path];
  if (contents == nil || [contents length] == 0)
  {
    return nil;
  }

  return contents;
}

static void WritePrefFile(NSString *filename, NSString *value)
{
  NSString *dir = RecordingPrefsDirectory();
  if (dir == nil)
  {
    return;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;
  if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error])
  {
    NSLog(@"RemoteJoyLite: failed to create preferences directory %@: %@", dir, error);
    return;
  }

  NSString *path = [dir stringByAppendingPathComponent:filename];
  if (![value writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error])
  {
    NSLog(@"RemoteJoyLite: failed to write preference %@: %@", path, error);
  }
}

static void WriteDataPrefFile(NSString *filename, NSData *value)
{
  NSString *dir = RecordingPrefsDirectory();
  if (dir == nil)
  {
    return;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;
  if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error])
  {
    NSLog(@"RemoteJoyLite: failed to create preferences directory %@: %@", dir, error);
    return;
  }

  NSString *path = [dir stringByAppendingPathComponent:filename];
  if (value == nil || ![value writeToFile:path atomically:YES])
  {
    NSLog(@"RemoteJoyLite: failed to write binary preference %@", path);
  }
}

static NSString *CopyDefaultOutputDeviceUID(void)
{
  AudioObjectID outputDevice = kAudioObjectUnknown;
  AudioObjectPropertyAddress address = {
      kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  UInt32 size = sizeof(outputDevice);
  OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &outputDevice);
  if (status != noErr || outputDevice == kAudioObjectUnknown)
  {
    return nil;
  }

  CFStringRef uidRef = NULL;
  address.mSelector = kAudioDevicePropertyDeviceUID;
  size = sizeof(uidRef);
  status = AudioObjectGetPropertyData(outputDevice, &address, 0, NULL, &size, &uidRef);
  if (status != noErr || uidRef == NULL)
  {
    return nil;
  }

  return [(NSString *)uidRef autorelease];
}

static BOOL SourceIdentifierIsEmpty(id sourceID)
{
  if (sourceID == nil)
  {
    return YES;
  }
  if ([sourceID isKindOfClass:[NSData class]])
  {
    return [(NSData *)sourceID length] == 0;
  }
  if ([sourceID isKindOfClass:[NSString class]])
  {
    return [(NSString *)sourceID length] == 0;
  }
  return NO;
}

static BOOL SourceIdentifierMatches(id lhs, id rhs)
{
  if (SourceIdentifierIsEmpty(lhs) && SourceIdentifierIsEmpty(rhs))
  {
    return YES;
  }
  if ([lhs isKindOfClass:[NSData class]] && [rhs isKindOfClass:[NSData class]])
  {
    return [(NSData *)lhs isEqualToData:(NSData *)rhs];
  }
  if ([lhs isKindOfClass:[NSString class]] && [rhs isKindOfClass:[NSString class]])
  {
    return [(NSString *)lhs isEqualToString:(NSString *)rhs];
  }
  return [lhs isEqual:rhs];
}

static BOOL EnsureSingleInstance(void)
{
  NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
  if (bundleID == nil || [bundleID length] == 0)
  {
    return YES;
  }

  pid_t selfPID = [[NSProcessInfo processInfo] processIdentifier];
  NSArray<NSRunningApplication *> *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID];
  for (NSRunningApplication *app in apps)
  {
    if ([app processIdentifier] != selfPID)
    {
      [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
      return NO;
    }
  }

  return YES;
}

static void LoadMicrophonePreferences(void)
{
  if (sMicPrefsLoaded)
  {
    return;
  }

  sMicPrefsLoaded = YES;

  NSString *selectedUID = ReadPrefFile(kMicSelectionPrefFile);
  if (selectedUID != nil && [selectedUID length] > 0)
  {
    sSelectedMicUID = [selectedUID copy];
  }
  else
  {
    [sSelectedMicUID release];
    sSelectedMicUID = nil;
  }

  NSData *selectedSourceID = ReadDataPrefFile(kMicSourceSelectionPrefFile);
  if (selectedSourceID != nil && [selectedSourceID length] > 0)
  {
    sSelectedMicSourceID = [selectedSourceID copy];
  }
  else
  {
    [sSelectedMicSourceID release];
    sSelectedMicSourceID = nil;
  }

  NSString *mutedValue = ReadPrefFile(kMicMutePrefFile);
  sMicMuted = (mutedValue != nil && [mutedValue intValue] != 0) ? YES : NO;
  if (sSelectedMicUID == nil)
  {
    sMicMuted = NO;
    [sSelectedMicSourceID release];
    sSelectedMicSourceID = nil;
  }
}

static void SaveMicrophonePreferences(void)
{
  if (sSelectedMicUID != nil)
  {
    WritePrefFile(kMicSelectionPrefFile, sSelectedMicUID);
  }
  else
  {
    WritePrefFile(kMicSelectionPrefFile, @"");
  }

  if (sSelectedMicSourceID != nil)
  {
    WriteDataPrefFile(kMicSourceSelectionPrefFile, sSelectedMicSourceID);
  }
  else
  {
    WriteDataPrefFile(kMicSourceSelectionPrefFile, nil);
  }

  WritePrefFile(kMicMutePrefFile, sMicMuted ? @"1" : @"0");
}

static BOOL MicSelectionMatchesItem(NSMenuItem *item, NSString *selectedUID, id selectedSourceID)
{
  id representedObject = [item representedObject];
  if ([representedObject isKindOfClass:[NSDictionary class]])
  {
    NSDictionary *info = (NSDictionary *)representedObject;
    NSString *deviceUID = info[@"deviceUID"];
    id sourceID = info[@"sourceID"];
    BOOL deviceMatches = (selectedUID != nil && [deviceUID isKindOfClass:[NSString class]] && [deviceUID isEqualToString:selectedUID]);
    BOOL sourceMatches = SourceIdentifierMatches(selectedSourceID, sourceID);
    return deviceMatches && sourceMatches;
  }

  if ([representedObject isKindOfClass:[NSString class]])
  {
    return (selectedUID != nil && [representedObject isEqualToString:selectedUID] &&
            (selectedSourceID == nil || [selectedSourceID length] == 0));
  }

  return NO;
}

static void UpdateMicrophoneMenuState(void)
{
  BOOL hasSelection = (sSelectedMicUID != nil && [sSelectedMicUID length] > 0);
  if (sMicHeaderItem != nil)
  {
    [sMicHeaderItem setEnabled:NO];
  }
  if (sMicNoneItem != nil)
  {
    [sMicNoneItem setState:hasSelection ? NSControlStateValueOff : NSControlStateValueOn];
  }
  for (NSMenuItem *item in sMicDeviceItems)
  {
    BOOL selected = hasSelection && MicSelectionMatchesItem(item, sSelectedMicUID, sSelectedMicSourceID);
    [item setState:selected ? NSControlStateValueOn : NSControlStateValueOff];
  }
  if (sMicMuteItem != nil)
  {
    [sMicMuteItem setEnabled:hasSelection];
    [sMicMuteItem setState:(hasSelection && sMicMuted) ? NSControlStateValueOn : NSControlStateValueOff];
  }
}

@interface RemoteJoyLiteVideoRecorder : NSObject <AVCaptureAudioDataOutputSampleBufferDelegate>
{
  AVAssetWriter *_writer;
  AVAssetWriterInput *_input;
  AVAssetWriterInputPixelBufferAdaptor *_adaptor;
  AVAssetWriterInput *_audioInput;
  AVCaptureSession *_audioSession;
  AVCaptureDeviceInput *_audioDeviceInput;
  AVCaptureAudioDataOutput *_audioOutput;
  AVAudioEngine *_audioEngine;
  AVAudioPlayerNode *_audioPlayerNode;
  AVAudioFormat *_audioMonitoringFormat;
  dispatch_queue_t _encodeQueue;
  dispatch_queue_t _audioQueue;
  dispatch_semaphore_t _frameSlots;
  NSURL *_outputURL;
  NSString *_outputFolder;
  NSString *_audioDeviceUID;
  NSData *_audioSourceID;
  BOOL _audioConfigured;
  BOOL _recording;
  CFAbsoluteTime _startTime;
  CMTime _lastPTS;
  CMTime _audioFirstPTS;
  CMTime _lastAudioPTS;
  BOOL _haveAudioFirstPTS;
}

- (BOOL)startWithWidth:(int)width height:(int)height quality:(int)quality;
- (BOOL)ensureAudioCaptureSession;
- (void)appendFramePixels:(const void *)pixels width:(int)width height:(int)height pitch:(int)pitch pixelFormat:(SDL_PixelFormat)pixelFormat captureTicks:(Uint64)captureTicks;
- (void)appendCapturedFrameData:(NSData *)frameData width:(int)width height:(int)height pitch:(int)pitch pixelFormat:(SDL_PixelFormat)pixelFormat pts:(CMTime)pts;
- (void)configureAudioCaptureForWriter:(AVAssetWriter *)writer;
- (BOOL)configureAudioMonitoringForSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)appendAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)appendAudioSampleBufferToMonitoring:(CMSampleBufferRef)sampleBuffer;
- (void)stopAudioCapture;
- (void)stopAudioMonitoring;
- (void)setAudioMonitoringMuted:(BOOL)muted;
- (void)finishRecording;
- (NSString *)outputFolder;
- (NSURL *)outputURL;
@end

@implementation RemoteJoyLiteVideoRecorder

- (void)dealloc
{
  [_input release];
  [_adaptor release];
  [_audioInput release];
  [_audioDeviceInput release];
  [_audioOutput release];
  [_audioPlayerNode release];
  [_audioEngine release];
  [_audioMonitoringFormat release];
  [_audioSession release];
  [_writer release];
  [_outputURL release];
  [_outputFolder release];
  [_audioDeviceUID release];
  [_audioSourceID release];
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

- (BOOL)startWithWidth:(int)width height:(int)height quality:(int)quality
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
  BOOL maxQuality = (quality != 0);
  NSString *filename = [NSString stringWithFormat:@"RemoteJoyLite-%@.%@", stamp, maxQuality ? @"mov" : @"mp4"];
  NSString *fullPath = [folder stringByAppendingPathComponent:filename];
  NSURL *url = [NSURL fileURLWithPath:fullPath];

  NSDictionary *settings = nil;
  NSString *fileType = nil;
  if (maxQuality)
  {
    settings = @{ AVVideoCodecKey : AVVideoCodecTypeAppleProRes4444, AVVideoWidthKey : @(width),
                  AVVideoHeightKey : @(height) };
    fileType = AVFileTypeQuickTimeMovie;
  }
  else
  {
    NSDictionary *compression =
        @{ AVVideoAverageBitRateKey : @(24000000),
           AVVideoProfileLevelKey : AVVideoProfileLevelH264HighAutoLevel,
           AVVideoMaxKeyFrameIntervalKey : @(30),
           AVVideoAllowFrameReorderingKey : @NO };
    settings = @{ AVVideoCodecKey : AVVideoCodecTypeH264, AVVideoWidthKey : @(width), AVVideoHeightKey : @(height),
                  AVVideoCompressionPropertiesKey : compression };
    fileType = AVFileTypeMPEG4;
  }

  AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:fileType error:&error];
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
  [_audioInput release];
  _audioInput = nil;
  [_audioDeviceInput release];
  _audioDeviceInput = nil;
  [_audioOutput release];
  _audioOutput = nil;
  [_audioSession release];
  _audioSession = nil;
  [_audioDeviceUID release];
  _audioDeviceUID = nil;
  _audioConfigured = NO;
  _haveAudioFirstPTS = NO;
  _lastAudioPTS = kCMTimeZero;

  [self ensureAudioCaptureSession];
  [self configureAudioCaptureForWriter:writer];

  if (![writer startWriting])
  {
    NSLog(@"RemoteJoyLite: startWriting failed: %@", [writer error]);
    [self stopAudioCapture];
    [adaptor release];
    [input release];
    [writer release];
    return NO;
  }

  [writer startSessionAtSourceTime:kCMTimeZero];

  _encodeQueue = dispatch_queue_create("com.psparchive.RemoteJoyLite.recording", DISPATCH_QUEUE_SERIAL);
  _frameSlots = dispatch_semaphore_create(3);
  _recording = YES;
  _startTime = CFAbsoluteTimeGetCurrent();
  _lastPTS = kCMTimeZero;
  return YES;
}

- (BOOL)ensureAudioCaptureSession
{
  LoadMicrophonePreferences();

  if (sSelectedMicUID == nil || [sSelectedMicUID length] == 0)
  {
    [self stopAudioCapture];
    return NO;
  }

  BOOL selectedHasSource = !SourceIdentifierIsEmpty(sSelectedMicSourceID);
  BOOL sameDevice = (_audioDeviceUID != nil && [_audioDeviceUID isEqualToString:sSelectedMicUID]);
  BOOL sameSource = SourceIdentifierMatches(_audioSourceID, sSelectedMicSourceID);
  if (_audioSession != nil && sameDevice && sameSource)
  {
    if (![_audioSession isRunning])
    {
      [_audioSession startRunning];
    }
    return YES;
  }

  [self stopAudioCapture];

  if (@available(macOS 10.14, *))
  {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted)
    {
      NSLog(@"RemoteJoyLite: microphone access is not authorized");
      return NO;
    }
  }

  AVCaptureDevice *device = [AVCaptureDevice deviceWithUniqueID:sSelectedMicUID];
  if (device == nil)
  {
    NSLog(@"RemoteJoyLite: selected microphone is unavailable: %@", sSelectedMicUID);
    return NO;
  }

  if (!SourceIdentifierIsEmpty(sSelectedMicSourceID))
  {
    NSError *configError = nil;
    if ([device lockForConfiguration:&configError])
    {
      AVCaptureDeviceInputSource *matchedSource = nil;
      for (AVCaptureDeviceInputSource *source in [device inputSources])
      {
        if (SourceIdentifierMatches(source.inputSourceID, sSelectedMicSourceID))
        {
          matchedSource = source;
          break;
        }
      }
      if (matchedSource != nil)
      {
        [device setActiveInputSource:matchedSource];
      }
      else
      {
        NSLog(@"RemoteJoyLite: selected input source is unavailable");
      }
      [device unlockForConfiguration];
    }
    else
    {
      NSLog(@"RemoteJoyLite: failed to lock microphone for configuration: %@", configError);
    }
  }

  NSError *error = nil;
  AVCaptureSession *session = [[AVCaptureSession alloc] init];
  AVCaptureDeviceInput *deviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:device error:&error];
  if (deviceInput == nil)
  {
    NSLog(@"RemoteJoyLite: failed to create microphone input: %@", error);
    [session release];
    return NO;
  }

  if (![session canAddInput:deviceInput])
  {
    NSLog(@"RemoteJoyLite: capture session rejected microphone input");
    [deviceInput release];
    [session release];
    return NO;
  }
  [session addInput:deviceInput];

  AVCaptureAudioDataOutput *audioOutput = [[AVCaptureAudioDataOutput alloc] init];
  dispatch_queue_t audioQueue = dispatch_queue_create("com.psparchive.RemoteJoyLite.audio", DISPATCH_QUEUE_SERIAL);
  [audioOutput setSampleBufferDelegate:self queue:audioQueue];

  if (![session canAddOutput:audioOutput])
  {
    NSLog(@"RemoteJoyLite: capture session rejected microphone output");
    [audioOutput release];
    [deviceInput release];
    [session release];
    return NO;
  }
  [session addOutput:audioOutput];

  [_audioSession release];
  _audioSession = session;
  [_audioDeviceInput release];
  _audioDeviceInput = deviceInput;
  [_audioOutput release];
  _audioOutput = audioOutput;
  _audioQueue = audioQueue;
  [_audioDeviceUID release];
  _audioDeviceUID = [sSelectedMicUID copy];
  [_audioSourceID release];
  _audioSourceID = [sSelectedMicSourceID copy];

  [_audioSession startRunning];
  return YES;
}

- (void)configureAudioCaptureForWriter:(AVAssetWriter *)writer
{
  LoadMicrophonePreferences();

  if (sSelectedMicUID == nil || [sSelectedMicUID length] == 0)
  {
    return;
  }

  NSDictionary *audioSettings =
      @{ AVFormatIDKey : @(kAudioFormatMPEG4AAC),
         AVNumberOfChannelsKey : @(2),
         AVSampleRateKey : @(48000),
         AVEncoderBitRateKey : @(128000) };

  AVAssetWriterInput *audioInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:audioSettings];
  [audioInput setExpectsMediaDataInRealTime:YES];

  if (![writer canAddInput:audioInput])
  {
    NSLog(@"RemoteJoyLite: writer rejected microphone audio input");
    [audioInput release];
    return;
  }

  [writer addInput:audioInput];

  [_audioInput release];
  _audioInput = audioInput;
  _audioConfigured = YES;
  _haveAudioFirstPTS = NO;
  _lastAudioPTS = kCMTimeZero;
}

- (BOOL)configureAudioMonitoringForSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
  if (sampleBuffer == NULL)
  {
    return NO;
  }

  CMAudioFormatDescriptionRef audioFormat = (CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer);
  const AudioStreamBasicDescription *asbd =
      audioFormat != NULL ? CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat) : NULL;
  if (asbd == NULL || asbd->mBytesPerFrame == 0 || asbd->mChannelsPerFrame == 0)
  {
    NSLog(@"RemoteJoyLite: microphone sample buffer has no usable format");
    return NO;
  }

  if (_audioMonitoringFormat != nil && memcmp(_audioMonitoringFormat.streamDescription, asbd, sizeof(*asbd)) == 0 &&
      _audioEngine != nil && _audioPlayerNode != nil)
  {
    if (sMicMuted)
    {
      [_audioPlayerNode setVolume:0.0f];
    }
    else
    {
      [_audioPlayerNode setVolume:1.0f];
      if (![_audioPlayerNode isPlaying])
      {
        [_audioPlayerNode play];
      }
    }
    return YES;
  }

  [self stopAudioMonitoring];

  NSError *error = nil;
  AVAudioFormat *monitorFormat = [[AVAudioFormat alloc] initWithStreamDescription:asbd];
  if (monitorFormat == nil)
  {
    NSLog(@"RemoteJoyLite: failed to create monitoring audio format");
    return NO;
  }

  AVAudioEngine *engine = [[AVAudioEngine alloc] init];
  AVAudioPlayerNode *playerNode = [[AVAudioPlayerNode alloc] init];
  [engine attachNode:playerNode];
  [engine connect:playerNode to:[engine mainMixerNode] format:monitorFormat];
  [engine prepare];
  if (![engine startAndReturnError:&error])
  {
    NSLog(@"RemoteJoyLite: failed to start audio monitoring engine: %@", error);
    [playerNode release];
    [engine release];
    [monitorFormat release];
    return NO;
  }

  [_audioEngine release];
  _audioEngine = engine;
  [_audioPlayerNode release];
  _audioPlayerNode = playerNode;
  [_audioMonitoringFormat release];
  _audioMonitoringFormat = [monitorFormat retain];
  [_audioPlayerNode setVolume:sMicMuted ? 0.0f : 1.0f];
  [_audioPlayerNode play];
  [monitorFormat release];
  return YES;
}

- (void)setAudioMonitoringMuted:(BOOL)muted
{
  sMicMuted = muted ? YES : NO;
  if (_audioPlayerNode != nil)
  {
    [_audioPlayerNode setVolume:sMicMuted ? 0.0f : 1.0f];
  }
}

- (void)appendAudioSampleBufferToMonitoring:(CMSampleBufferRef)sampleBuffer
{
  if (sampleBuffer == NULL)
  {
    return;
  }

  if (![self configureAudioMonitoringForSampleBuffer:sampleBuffer])
  {
    return;
  }

  if (sMicMuted || _audioPlayerNode == nil || _audioMonitoringFormat == nil)
  {
    return;
  }

  CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
  if (numSamples <= 0)
  {
    return;
  }

  AVAudioFrameCount frameCount = (AVAudioFrameCount)numSamples;
  AVAudioPCMBuffer *pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_audioMonitoringFormat frameCapacity:frameCount];
  if (pcmBuffer == nil)
  {
    return;
  }

  pcmBuffer.frameLength = frameCount;
  OSStatus status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, 0, (int32_t)frameCount,
                                                                 pcmBuffer.mutableAudioBufferList);
  if (status != noErr)
  {
    NSLog(@"RemoteJoyLite: failed to copy microphone audio for monitoring: %d", (int)status);
    [pcmBuffer release];
    return;
  }

  if (![_audioPlayerNode isPlaying])
  {
    [_audioPlayerNode play];
  }
  [_audioPlayerNode scheduleBuffer:pcmBuffer completionHandler:nil];
  [pcmBuffer release];
}

- (void)appendAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
  [self appendAudioSampleBufferToMonitoring:sampleBuffer];

  if (!_recording || !_audioConfigured || sampleBuffer == NULL || _audioInput == nil)
  {
    return;
  }

  if (![_audioInput isReadyForMoreMediaData])
  {
    return;
  }

  CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
  if (!CMTIME_IS_VALID(pts))
  {
    return;
  }

  if (!_haveAudioFirstPTS)
  {
    _audioFirstPTS = pts;
    _haveAudioFirstPTS = YES;
  }

  CMTime relativePTS = CMTimeSubtract(pts, _audioFirstPTS);
  if (!CMTIME_IS_VALID(relativePTS) || CMTIME_COMPARE_INLINE(relativePTS, <, kCMTimeZero))
  {
    relativePTS = kCMTimeZero;
  }

  if (CMTIME_COMPARE_INLINE(relativePTS, <=, _lastAudioPTS))
  {
    relativePTS = CMTimeAdd(_lastAudioPTS, CMTimeMake(1, 48000));
  }

  CMSampleTimingInfo timingInfo;
  timingInfo.duration = CMSampleBufferGetDuration(sampleBuffer);
  timingInfo.presentationTimeStamp = relativePTS;
  timingInfo.decodeTimeStamp = kCMTimeInvalid;

  CMSampleBufferRef adjustedBuffer = NULL;
  OSStatus status =
      CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, sampleBuffer, 1, &timingInfo, &adjustedBuffer);
  if (status != noErr || adjustedBuffer == NULL)
  {
    NSLog(@"RemoteJoyLite: failed to retime microphone sample buffer: %d", (int)status);
    return;
  }

  if (![_audioInput appendSampleBuffer:adjustedBuffer])
  {
    NSLog(@"RemoteJoyLite: failed to append microphone sample: %@", [_writer error]);
  }
  else
  {
    _lastAudioPTS = relativePTS;
  }

  CFRelease(adjustedBuffer);
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
  (void)output;
  (void)connection;
  [self appendAudioSampleBuffer:sampleBuffer];
}

- (void)stopAudioCapture
{
  if (_audioSession != nil)
  {
    [_audioSession stopRunning];
  }

  if (_audioQueue != nil)
  {
    dispatch_sync(_audioQueue, ^{});
  }

  [self stopAudioMonitoring];

  [_audioInput release];
  _audioInput = nil;
  [_audioDeviceInput release];
  _audioDeviceInput = nil;
  [_audioOutput release];
  _audioOutput = nil;
  [_audioSession release];
  _audioSession = nil;
  _audioQueue = nil;
  [_audioDeviceUID release];
  _audioDeviceUID = nil;
  [_audioSourceID release];
  _audioSourceID = nil;
  _audioConfigured = NO;
  _haveAudioFirstPTS = NO;
  _lastAudioPTS = kCMTimeZero;
}

- (void)stopAudioMonitoring
{
  [_audioPlayerNode stop];
  [_audioPlayerNode release];
  _audioPlayerNode = nil;
  [_audioEngine stop];
  [_audioEngine release];
  _audioEngine = nil;
  [_audioMonitoringFormat release];
  _audioMonitoringFormat = nil;
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
  AVAssetWriterInput *audioInput = [_audioInput retain];
  if (audioInput != nil)
  {
    [audioInput markAsFinished];
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
  [audioInput release];
  _audioInput = nil;
  _audioConfigured = NO;
  _haveAudioFirstPTS = NO;
  _lastAudioPTS = kCMTimeZero;
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

#if HAS_SCREENCAPTUREKIT
@interface RemoteJoyLiteScreenRecorder : NSObject <SCStreamDelegate, SCStreamOutput>
{
  AVAssetWriter *_writer;
  AVAssetWriterInput *_input;
  AVAssetWriterInputPixelBufferAdaptor *_adaptor;
  SCStream *_stream;
  dispatch_queue_t _sampleQueue;
  NSURL *_outputURL;
  NSString *_outputFolder;
  BOOL _recording;
  BOOL _stopping;
  BOOL _sessionStarted;
  CMTime _lastPTS;
}

- (BOOL)startWithWindow:(NSWindow *)window quality:(int)quality;
- (void)finishRecording;
- (NSString *)outputFolder;
@end

@implementation RemoteJoyLiteScreenRecorder

- (void)dealloc
{
  [_input release];
  [_adaptor release];
  [_writer release];
  [_stream release];
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

- (SCWindow *)findWindowForContent:(SCShareableContent *)content windowNumber:(NSInteger)windowNumber
{
  for (SCWindow *candidate in content.windows)
  {
    if ((NSInteger)candidate.windowID == windowNumber)
    {
      return candidate;
    }
  }
  return nil;
}

- (BOOL)prepareWriterAtURL:(NSURL *)url width:(int)width height:(int)height
{
  NSError *error = nil;

  NSDictionary *compression =
      @{ AVVideoAverageBitRateKey : @(18000000),
         AVVideoMaxKeyFrameIntervalKey : @(30),
         AVVideoAllowFrameReorderingKey : @NO };
  NSDictionary *settings =
      @{ AVVideoCodecKey : AVVideoCodecTypeHEVC, AVVideoWidthKey : @(width), AVVideoHeightKey : @(height),
         AVVideoCompressionPropertiesKey : compression };

  AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error];
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

  [_writer release];
  _writer = writer;
  [_input release];
  _input = input;
  [_adaptor release];
  _adaptor = adaptor;
  _sessionStarted = NO;
  _lastPTS = kCMTimeZero;
  return YES;
}

- (BOOL)startWithWindow:(NSWindow *)window quality:(int)quality
{
  if (_recording)
  {
    return YES;
  }

  if (@available(macOS 13.0, *))
  {
    if (window == nil)
    {
      NSLog(@"RemoteJoyLite: no window to capture");
      return NO;
    }

    if (_sampleQueue == nil)
    {
      _sampleQueue = dispatch_queue_create("com.psparchive.RemoteJoyLite.screencapture", DISPATCH_QUEUE_SERIAL);
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
    NSString *filename = [NSString stringWithFormat:@"RemoteJoyLite-%@.mov", stamp];
    NSString *fullPath = [folder stringByAppendingPathComponent:filename];
    NSURL *url = [NSURL fileURLWithPath:fullPath];

    __block SCWindow *capturedWindow = nil;
    dispatch_semaphore_t contentSem = dispatch_semaphore_create(0);
    [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *content, NSError *contentError) {
      if (contentError != nil)
      {
        NSLog(@"RemoteJoyLite: ScreenCaptureKit content query failed: %@", contentError);
      }
      else
      {
        capturedWindow = [[self findWindowForContent:content windowNumber:[window windowNumber]] retain];
      }
      dispatch_semaphore_signal(contentSem);
    }];
    dispatch_semaphore_wait(contentSem, DISPATCH_TIME_FOREVER);
    if (capturedWindow == nil)
    {
      NSLog(@"RemoteJoyLite: could not find capture window");
      return NO;
    }

    NSRect contentRect = [window contentLayoutRect];
    CGFloat scale = 1.0;
    if ([window respondsToSelector:@selector(backingScaleFactor)])
    {
      scale = [window backingScaleFactor];
    }

    SCContentFilter *filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:capturedWindow];
    SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
    configuration.width = MAX(1, (int)(contentRect.size.width * scale + 0.5));
    configuration.height = MAX(1, (int)(contentRect.size.height * scale + 0.5));
    configuration.minimumFrameInterval = CMTimeMake(1, 60);
    configuration.pixelFormat = kCVPixelFormatType_32BGRA;
    configuration.queueDepth = 5;
    configuration.showsCursor = NO;
    configuration.capturesAudio = NO;

    if (![self prepareWriterAtURL:url width:configuration.width height:configuration.height])
    {
      [filter release];
      [configuration release];
      [capturedWindow release];
      return NO;
    }

    SCStream *stream = [[SCStream alloc] initWithFilter:filter configuration:configuration delegate:self];
    NSError *streamError = nil;
    if (![stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:_sampleQueue error:&streamError])
    {
      NSLog(@"RemoteJoyLite: addStreamOutput failed: %@", streamError);
      [stream release];
      [filter release];
      [configuration release];
      [capturedWindow release];
      [_input release];
      _input = nil;
      [_adaptor release];
      _adaptor = nil;
      [_writer release];
      _writer = nil;
      return NO;
    }

    dispatch_semaphore_t startSem = dispatch_semaphore_create(0);
    __block NSError *startError = nil;
    [stream startCaptureWithCompletionHandler:^(NSError *captureError) {
      startError = [captureError retain];
      dispatch_semaphore_signal(startSem);
    }];
    dispatch_semaphore_wait(startSem, DISPATCH_TIME_FOREVER);

    if (startError != nil)
    {
      NSLog(@"RemoteJoyLite: ScreenCaptureKit start failed: %@", startError);
      [startError release];
      [stream release];
      [filter release];
      [configuration release];
      [capturedWindow release];
      [_input release];
      _input = nil;
      [_adaptor release];
      _adaptor = nil;
      [_writer release];
      _writer = nil;
      return NO;
    }

    [startError release];
    [_outputFolder release];
    _outputFolder = [folder copy];
    [_outputURL release];
    _outputURL = [url retain];
    [_stream release];
    _stream = [stream retain];
  _recording = YES;
  _stopping = NO;

    [stream release];
    [filter release];
    [configuration release];
    [capturedWindow release];
    return YES;
  }

  NSLog(@"RemoteJoyLite: ScreenCaptureKit recording requires macOS 13 or newer");
  (void)quality;
  return NO;
}

- (void)finishRecording
{
  if (!_recording || _stopping)
  {
    return;
  }

  if (_stream == nil)
  {
    _recording = NO;
    return;
  }

  _stopping = YES;
  _recording = NO;

  SCStream *stream = [_stream retain];
  [_stream release];
  _stream = nil;

  AVAssetWriter *writer = [_writer retain];
  AVAssetWriterInput *input = [_input retain];
  AVAssetWriterInputPixelBufferAdaptor *adaptor = [_adaptor retain];
  NSURL *outputURL = [_outputURL retain];
  NSString *outputFolder = [_outputFolder retain];

  [_input release];
  _input = nil;
  [_adaptor release];
  _adaptor = nil;
  [_writer release];
  _writer = nil;
  [_outputURL release];
  _outputURL = nil;
  [_outputFolder release];
  _outputFolder = nil;

  [stream stopCaptureWithCompletionHandler:^(NSError *error) {
    if (error != nil)
    {
      NSLog(@"RemoteJoyLite: ScreenCaptureKit stop failed: %@", error);
    }

    if (input != nil)
    {
      [input markAsFinished];
    }

    [writer finishWritingWithCompletionHandler:^{
      if (writer.status == AVAssetWriterStatusCompleted && outputURL != nil)
      {
        dispatch_async(dispatch_get_main_queue(), ^{
          [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ outputURL ]];
        });
      }
      else
      {
        NSLog(@"RemoteJoyLite: ScreenCaptureKit recording failed to finish cleanly: %@", [writer error]);
      }

      [input release];
      [adaptor release];
      [writer release];
      [outputURL release];
      [outputFolder release];
      _stopping = NO;
    }];

    [stream release];
  }];
}

- (NSString *)outputFolder
{
  return _outputFolder;
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type
{
  (void)stream;
  if (!_recording || type != SCStreamOutputTypeScreen || sampleBuffer == NULL)
  {
    return;
  }

  if (_writer == nil || _input == nil || _adaptor == nil)
  {
    return;
  }

  CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  if (pixelBuffer == NULL)
  {
    return;
  }

  CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
  if (!_sessionStarted)
  {
    [_writer startSessionAtSourceTime:pts];
    _sessionStarted = YES;
  }

  if (CMTIME_COMPARE_INLINE(pts, <=, _lastPTS))
  {
    pts = CMTimeAdd(_lastPTS, CMTimeMake(1, 60));
  }

  if (![_input isReadyForMoreMediaData])
  {
    return;
  }

  if (![_adaptor appendPixelBuffer:pixelBuffer withPresentationTime:pts])
  {
    NSLog(@"RemoteJoyLite: ScreenCaptureKit frame append failed: %@", [_writer error]);
  }
  else
  {
    _lastPTS = pts;
  }
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error
{
  (void)stream;
  if (error != nil)
  {
    NSLog(@"RemoteJoyLite: ScreenCaptureKit stream stopped with error: %@", error);
  }
}

@end
#endif

static RemoteJoyLiteScreenRecorder *sScreenRecorder = nil;
static BOOL sScreenCapturePermissionRequested = NO;

static BOOL HasScreenCapturePermission(void)
{
  if (@available(macOS 11.0, *))
  {
    if (CGPreflightScreenCaptureAccess())
    {
      return YES;
    }
    if (sScreenCapturePermissionRequested)
    {
      return NO;
    }
    sScreenCapturePermissionRequested = YES;
    return CGRequestScreenCaptureAccess();
  }
  return NO;
}

@interface RemoteJoyLiteMenuTarget : NSObject
@end

@implementation RemoteJoyLiteMenuTarget
- (void)toggleRecording:(id)sender
{
  RemoteJoyLiteToggleRecording();
}

- (void)setRecordingQualityHigh:(id)sender
{
  (void)sender;
  RemoteJoyLiteSetRecordingQuality(0);
}

- (void)setRecordingQualityMax:(id)sender
{
  (void)sender;
  RemoteJoyLiteSetRecordingQuality(1);
}

- (void)selectMicrophone:(id)sender
{
  if (![sender isKindOfClass:[NSMenuItem class]])
  {
    return;
  }

  NSMenuItem *item = (NSMenuItem *)sender;
  NSString *uid = nil;
  id sourceID = nil;
  id representedObject = [item representedObject];
  if ([representedObject isKindOfClass:[NSDictionary class]])
  {
    NSDictionary *info = (NSDictionary *)representedObject;
    uid = info[@"deviceUID"];
    sourceID = info[@"sourceID"];
  }
  else if ([representedObject isKindOfClass:[NSString class]])
  {
    uid = (NSString *)representedObject;
  }

  if (![uid isKindOfClass:[NSString class]] || [uid length] == 0)
  {
    [sSelectedMicUID release];
    sSelectedMicUID = nil;
    [sSelectedMicSourceID release];
    sSelectedMicSourceID = nil;
    sMicMuted = NO;
  }
  else
  {
    [sSelectedMicUID release];
    sSelectedMicUID = [uid copy];
    [sSelectedMicSourceID release];
    sSelectedMicSourceID = !SourceIdentifierIsEmpty(sourceID) ? [sourceID copy] : nil;
  }

  SaveMicrophonePreferences();
  UpdateMicrophoneMenuState();

  if (sSelectedMicUID != nil && sRecorder == nil)
  {
    sRecorder = [RemoteJoyLiteVideoRecorder new];
  }

  if (sRecorder != nil)
  {
    RemoteJoyLiteVideoRecorder *recorder = [sRecorder retain];
    if (sSelectedMicUID == nil)
    {
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [recorder stopAudioCapture];
        [recorder release];
      });
    }
    else
    {
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      [recorder ensureAudioCaptureSession];
      [recorder release];
    });
  }
}
}

- (void)toggleMuteMicrophone:(id)sender
{
  (void)sender;
  if (sSelectedMicUID == nil)
  {
    return;
  }

  sMicMuted = !sMicMuted;
  if (sRecorder == nil && sSelectedMicUID != nil)
  {
    sRecorder = [RemoteJoyLiteVideoRecorder new];
  }

  if (sRecorder != nil)
  {
    [sRecorder setAudioMonitoringMuted:sMicMuted];
  }
  SaveMicrophonePreferences();
  UpdateMicrophoneMenuState();
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

static NSMenu *RecordingMenu(NSMenu *mainMenu)
{
  for (NSMenuItem *item in [mainMenu itemArray])
  {
    if ([[item title] isEqualToString:@"Recording"])
    {
      if ([item submenu] != nil)
      {
        return [item submenu];
      }
    }
  }

  NSMenuItem *recordingItem = [[NSMenuItem alloc] initWithTitle:@"Recording" action:nil keyEquivalent:@""];
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Recording"];
  [recordingItem setSubmenu:menu];
  [mainMenu addItem:recordingItem];

  if (sRecordingItem == nil)
  {
    sRecordingItem = [[NSMenuItem alloc] initWithTitle:@"Record" action:@selector(toggleRecording:) keyEquivalent:@""];
    [sRecordingItem setTarget:sTarget];
    [sRecordingItem setKeyEquivalent:@"r"];
    [sRecordingItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
  }
  [menu addItem:sRecordingItem];

  [menu addItem:[NSMenuItem separatorItem]];

  if (sMicHeaderItem == nil)
  {
    sMicHeaderItem = [[NSMenuItem alloc] initWithTitle:@"Microphone Input" action:nil keyEquivalent:@""];
    [sMicHeaderItem setEnabled:NO];
  }
  [menu addItem:sMicHeaderItem];

  if (sMicNoneItem == nil)
  {
    sMicNoneItem = [[NSMenuItem alloc] initWithTitle:@"None" action:@selector(selectMicrophone:) keyEquivalent:@""];
    [sMicNoneItem setTarget:sTarget];
    [sMicNoneItem setRepresentedObject:nil];
  }
  [menu addItem:sMicNoneItem];

  if (sMicDeviceItems == nil)
  {
    sMicDeviceItems = [[NSMutableArray alloc] init];
    NSArray<AVCaptureDeviceType> *deviceTypes =
        @[ AVCaptureDeviceTypeBuiltInMicrophone, AVCaptureDeviceTypeExternalUnknown ];
    AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeAudio position:AVCaptureDevicePositionUnspecified];
    NSArray<AVCaptureDevice *> *devices = discovery.devices;
    for (AVCaptureDevice *device in devices)
    {
      NSArray<AVCaptureDeviceInputSource *> *sources = device.inputSources;
      if (sources != nil && [sources count] > 0)
      {
        for (AVCaptureDeviceInputSource *source in sources)
        {
          NSString *title = [NSString stringWithFormat:@"%@ : %@", device.localizedName, source.localizedName];
          NSMenuItem *deviceItem =
              [[NSMenuItem alloc] initWithTitle:title action:@selector(selectMicrophone:) keyEquivalent:@""];
          [deviceItem setTarget:sTarget];
          NSDictionary *info =
              @{ @"deviceUID" : device.uniqueID, @"sourceID" : source.inputSourceID ?: [NSData data] };
          [deviceItem setRepresentedObject:info];
          [sMicDeviceItems addObject:deviceItem];
          [menu addItem:deviceItem];
        }
      }
      else
      {
        NSMenuItem *deviceItem =
            [[NSMenuItem alloc] initWithTitle:device.localizedName action:@selector(selectMicrophone:) keyEquivalent:@""];
        [deviceItem setTarget:sTarget];
        NSDictionary *info = @{ @"deviceUID" : device.uniqueID };
        [deviceItem setRepresentedObject:info];
        [sMicDeviceItems addObject:deviceItem];
        [menu addItem:deviceItem];
      }
    }
  }
  else
  {
    for (NSMenuItem *deviceItem in sMicDeviceItems)
    {
      [menu addItem:deviceItem];
    }
  }

  [menu addItem:[NSMenuItem separatorItem]];

  if (sMicMuteItem == nil)
  {
    sMicMuteItem =
        [[NSMenuItem alloc] initWithTitle:@"Mute Mic Monitoring" action:@selector(toggleMuteMicrophone:) keyEquivalent:@""];
    [sMicMuteItem setTarget:sTarget];
  }
  [menu addItem:sMicMuteItem];

  [menu addItem:[NSMenuItem separatorItem]];

  if (sHighQualityItem == nil)
  {
    sHighQualityItem =
        [[NSMenuItem alloc] initWithTitle:@"High Quality (.mp4)" action:@selector(setRecordingQualityHigh:) keyEquivalent:@""];
    [sHighQualityItem setTarget:sTarget];
  }
  [menu addItem:sHighQualityItem];

  if (sMaxQualityItem == nil)
  {
    sMaxQualityItem =
        [[NSMenuItem alloc] initWithTitle:@"Max Quality (.mov)" action:@selector(setRecordingQualityMax:) keyEquivalent:@""];
    [sMaxQualityItem setTarget:sTarget];
  }
  [menu addItem:sMaxQualityItem];

  LoadMicrophonePreferences();
  UpdateMicrophoneMenuState();

  return menu;
}

extern "C" void MacInstallMenus(void)
{
  @autoreleasepool
  {
    NSLog(@"RemoteJoyLite launching from %@", [[NSBundle mainBundle] bundlePath]);
    if (!EnsureSingleInstance())
    {
      exit(0);
    }

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

    NSMenu *recordingMenu = RecordingMenu(mainMenu);
    (void)recordingMenu;
    LoadMicrophonePreferences();
    UpdateMicrophoneMenuState();

    if (sSelectedMicUID != nil)
    {
      if (sRecorder == nil)
      {
        sRecorder = [RemoteJoyLiteVideoRecorder new];
      }
      RemoteJoyLiteVideoRecorder *recorder = [sRecorder retain];
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [recorder ensureAudioCaptureSession];
        [recorder release];
      });
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
    if (sRecordingItem != nil)
    {
      [sRecordingItem setTitle:recording ? @"Stop Recording" : @"Record"];
    }
  }
}

extern "C" void MacSetRecordingQualityMenuState(int quality)
{
  @autoreleasepool
  {
    if (sHighQualityItem != nil)
    {
      [sHighQualityItem setState:(quality == 0) ? NSControlStateValueOn : NSControlStateValueOff];
    }
    if (sMaxQualityItem != nil)
    {
      [sMaxQualityItem setState:(quality != 0) ? NSControlStateValueOn : NSControlStateValueOff];
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
    int quality = RemoteJoyLiteGetRecordingQuality();
    if (sRecorder == nil)
    {
      sRecorder = [RemoteJoyLiteVideoRecorder new];
    }
    return [sRecorder startWithWidth:width height:height quality:quality] ? 1 : 0;
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
