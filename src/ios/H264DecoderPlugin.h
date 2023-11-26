#import <Cordova/CDV.h>
#import "VTCompressionH264Decode.h"

@interface H264DecoderPlugin : CDVPlugin<VTCompressionH264DecodeDelegate>

@property (nonatomic, strong) VTCompressionH264Decode* decoder;
@property (nonatomic, strong) NSString* callbackId;

- (void)initialize:(CDVInvokedUrlCommand*)command;
- (void)setCallback:(CDVInvokedUrlCommand*)command;
- (void)decode:(CDVInvokedUrlCommand*)command;
- (void)invalidate:(CDVInvokedUrlCommand*)command;

- (void)imageBufferCallBack:(CVImageBufferRef)imageBuffer;
@end