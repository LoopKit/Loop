//
//  RileyLinkDevice.m
//  RileyLink
//
//  Created by Nathan Racklyeft on 8/28/15.
//  Copyright © 2015 Pete Schwamb. All rights reserved.
//

#import "RileyLinkDevice.h"
#import "RileyLinkBLEManager.h"
#import "MessageBase.h"
#import "MessageSendOperation.h"

NSString * const RileyLinkDeviceDidReceivePacketNotification = @"com.ps2.RileyLinkKit.RileyLinkDeviceDidReceivePacketNotification";

NSString * const RileyLinkDevicePacketKey = @"com.ps2.RileyLinkKit.RileyLinkDevicePacket";

@interface RileyLinkDevice () {
    NSInteger _txChannel;
    NSOperationQueue *_messageQueue;
}

@property (nonatomic, nonnull, strong) RileyLinkBLEDevice *device;

@end

@implementation RileyLinkDevice

- (instancetype)initWithBLEDevice:(RileyLinkBLEDevice *)device
{
    self = [super init];
    if (self) {
        _txChannel = 2;
        _device = device;
        _messageQueue = [[NSOperationQueue alloc] init];
        _messageQueue.maxConcurrentOperationCount = 1;
        _messageQueue.qualityOfService = NSQualityOfServiceUserInitiated;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(packetReceived:) name:RILEYLINK_EVENT_PACKET_RECEIVED object:device];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:RILEYLINK_EVENT_PACKET_RECEIVED object:self.device];
}

- (NSString *)name
{
    return self.device.name;
}

- (NSNumber *)RSSI
{
    return self.device.RSSI;
}

- (CBPeripheral *)peripheral
{
    return self.device.peripheral;
}

#pragma mark -

- (void)packetReceived:(NSNotification *)note
{
    [[NSNotificationCenter defaultCenter] postNotificationName:RileyLinkDeviceDidReceivePacketNotification object:self userInfo:@{RileyLinkDevicePacketKey: note.userInfo[@"packet"]}];
}

- (void)executeCommand:(id<MessageSendOperationGroup>)command withCompletionHandler:(void (^)(id<MessageSendOperationGroup> _Nonnull))completionHandler
{
    switch ([command packetType]) {
        case PacketTypeSentry:
            if (_txChannel != 3) {
                _txChannel = 3;
                // TODO: This should be asynchronous
                [self.device setTXChannel:3];
            }

            break;
        case PacketTypeCarelink:
            if (_txChannel != 2) {
                _txChannel = 2;
                // TODO: This should be asynchronous
                [self.device setTXChannel:2];
            }

            break;
        default:
            // Undefined
            break;
    }

    [_messageQueue addOperations:[command messageOperations] waitUntilFinished:NO];
    [_messageQueue addOperationWithBlock:^{
        completionHandler(command);
    }];
}

- (void)sendMessageData:(NSData *)messageData
{
    MessageBase *message = [[MessageBase alloc] initWithData:messageData];

    switch (message.packetType) {
        case PacketTypeSentry:
            if (_txChannel != 3) {
                _txChannel = 3;
                // TODO: This should be asynchronous
                [self.device setTXChannel:3];
            }

            break;
        case PacketTypeCarelink:
            if (_txChannel != 2) {
                _txChannel = 2;
                // TODO: This should be asynchronous
                [self.device setTXChannel:2];
            }

            break;
        default:
            // Undefined
            break;
    }

    MessageSendOperation *operation = [[MessageSendOperation alloc] initWithDevice:self.device message:message timeout:2 completionHandler:nil];

    [_messageQueue addOperation:operation];
}

@end
