#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>

NS_ASSUME_NONNULL_BEGIN

@interface XDOpenConnectRuntime : NSObject

- (void)startWithProvider:(NEPacketTunnelProvider *)provider
               packetFlow:(NEPacketTunnelFlow *)packetFlow
            configuration:(NSDictionary<NSString *, id> *)configuration
               completion:(void (^)(NSError *_Nullable error))completion
    NS_SWIFT_NAME(start(provider:packetFlow:configuration:completion:));

- (void)stopWithCompletion:(void (^)(void))completion
    NS_SWIFT_NAME(stop(completion:));

@end

NS_ASSUME_NONNULL_END
