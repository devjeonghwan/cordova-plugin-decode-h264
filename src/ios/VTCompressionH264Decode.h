#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@protocol VTCompressionH264DecodeDelegate <NSObject>
- (void)imageBufferCallBack:(CVImageBufferRef)imageBuffer;
@end

@interface VTCompressionH264Decode : NSObject
@property(weak,nonatomic) id<VTCompressionH264DecodeDelegate> delegate;

- (void)decode:(NSData *)decodeData;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
