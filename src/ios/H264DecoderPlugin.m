#import "H264DecoderPlugin.h"
#import "VTCompressionH264Decode.h"
#import <Cordova/CDV.h>
#define clamp(a) (a>255?255:(a<0?0:a));

@implementation H264DecoderPlugin

- (void)initialize:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;

    @try {
        if(!self.decoder){
            self.decoder = [[VTCompressionH264Decode alloc] init];
            self.decoder.delegate = self;

            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
        }
    } @catch(NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsMultipart:@[exception.name, exception.reason]];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setCallback:(CDVInvokedUrlCommand*)command
{
    self.callbackId = command.callbackId;

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_NO_RESULT];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)imageBufferCallBack:(CVImageBufferRef)imageBuffer
{
    if(self.callbackId){
        @autoreleasepool {
            CDVPluginResult* pluginResult = nil;
            @try{
                size_t width = CVPixelBufferGetWidth(imageBuffer);
                size_t height = CVPixelBufferGetHeight(imageBuffer);
                size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);

                if (width * 4 == bytesPerRow) {
                    // It can directly convert to rgba
                    CVPixelBufferLockBaseAddress(imageBuffer,0);
                    void* src_buff = CVPixelBufferGetBaseAddress(imageBuffer);
                    unsigned char* src_ubuff = (unsigned char*) src_buff;

                    for(int i=0; i < bytesPerRow * height; i+=4){
                        unsigned char val = src_ubuff[i+0];
                        src_ubuff[i+0] = src_ubuff[i+2];
                        src_ubuff[i+2] = val;
                    }

                    NSData *data = [NSData dataWithBytes:src_ubuff length:bytesPerRow * height];
                    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsMultipart:@[ @((int)width), @((int)height), data]];
                } else {
                    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
                    CIContext *temporaryContext = [CIContext contextWithOptions:nil];
                    CGImageRef videoImage = [temporaryContext
                                            createCGImage:ciImage
                                            fromRect:CGRectMake(0, 0,
                                            width,
                                            height)];

                    UIImage *image = [[UIImage alloc] initWithCGImage:videoImage];
                    CGDataProviderRef provider = CGImageGetDataProvider(image.CGImage);
                    NSData* data = (id)CFBridgingRelease(CGDataProviderCopyData(provider));
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsMultipart:@[ @((int)width), @((int)height), data]];

                    CGImageRelease(videoImage);
                }

            } @catch(NSException *exception) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsMultipart:@[exception.name, exception.reason]];
            }

            [pluginResult setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        }
    }
}

- (UIImage *) createRGBAImageFromBGRAImage: (UIImage *)image {
    CGSize dimensions = [image size];

    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * dimensions.width;
    NSUInteger bitsPerComponent = 8;

    unsigned char *bgra = malloc(bytesPerPixel * dimensions.width * dimensions.height);
    unsigned char *rgba = malloc(bytesPerPixel * dimensions.width * dimensions.height);

    CGColorSpaceRef colorSpace = NULL;
    CGContextRef context = NULL;

    colorSpace = CGColorSpaceCreateDeviceRGB();
    context = CGBitmapContextCreate(bgra, dimensions.width, dimensions.height, bitsPerComponent, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault); // kCGBitmapByteOrder32Big
    CGContextDrawImage(context, CGRectMake(0, 0, dimensions.width, dimensions.height), [image CGImage]);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    for (int x = 0; x < dimensions.width; x++) {
        for (int y = 0; y < dimensions.height; y++) {
            NSUInteger offset = ((dimensions.width * y) + x) * bytesPerPixel;
            rgba[offset + 0] = bgra[offset + 2];
            rgba[offset + 1] = bgra[offset + 1];
            rgba[offset + 2] = bgra[offset + 0];
            rgba[offset + 3] = bgra[offset + 3];
        }
    }

    colorSpace = CGColorSpaceCreateDeviceRGB();
    context = CGBitmapContextCreate(rgba, dimensions.width, dimensions.height, bitsPerComponent, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrderDefault); // kCGBitmapByteOrder32Big
    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    image = [UIImage imageWithCGImage: imageRef];
    CGImageRelease(imageRef);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    free(bgra);
    free(rgba);

    return image;
}

- (void)decode:(CDVInvokedUrlCommand*)command
{
    NSData* data = [command.arguments objectAtIndex:0];

    CDVPluginResult* pluginResult = nil;
    @try{
        if(self.decoder){
            [self.decoder decode:data];

            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
        }
    } @catch(NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsMultipart:@[exception.name, exception.reason]];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)invalidate:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;

    @try{
        if(self.decoder){
            [self.decoder invalidate];

            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
        }
    } @catch(NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsMultipart:@[exception.name, exception.reason]];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

@end
