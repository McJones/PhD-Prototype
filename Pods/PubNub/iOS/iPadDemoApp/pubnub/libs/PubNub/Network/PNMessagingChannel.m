//
//  PNMessagingChannel.m
//  pubnub
//
//  This channel instance is required for messages exchange between client and
//  PubNub service:
//      - channels messages (subscribe)
//      - channels presence events
//      - leave
//
//  Notice: don't try to create more than one messaging channel on MacOS
//
//
//  Created by Sergey Mamontov on 12/12/12.
//
//

#import "PNMessagingChannel.h"
#import "PNConnectionChannel+Protected.h"
#import "PNChannelEventsResponseParser.h"
#import "PNChannelPresence+Protected.h"
#import "PNPresenceEvent+Protected.h"
#import "PNChannelEvents+Protected.h"
#import "PNDefaultConfiguration.h"
#import "NSObject+PNAdditions.h"
#import "PNMessage+Protected.h"
#import "PNChannel+Protected.h"
#import "PNOperationStatus.h"
#import "PNRequestsImport.h"
#import "PNRequestsQueue.h"
#import "PNLoggerSymbols.h"
#import "PNErrorCodes.h"
#import "PNResponse.h"
#import "PNHelper.h"
#import "PNCache.h"
#import "PNError.h"


// ARC check
#if !__has_feature(objc_arc)
#error PubNub messaging connection channel must be built with ARC.
// You can turn on ARC for only PubNub files by adding '-fobjc-arc' to the build phase for each of its files.
#endif


#pragma mark Statics

typedef NS_OPTIONS(NSUInteger, PNMessagingConnectionStateFlag)  {
    
    // Channel currently tries to restore subscription on channels which he was subscribed before or which
    // didn't get response from server (stored have more value when selecting re-subscription route)
    PNMessagingChannelRestoringSubscription = 1 << 0,
    
    // Channel currently tries to update subscription on channels (send request with updated time tokens)
    PNMessagingChannelUpdateSubscription = 1 << 1,
    
    // Channel currently tries to retrieve next subscription token which should be used for long-poll
    // subscription request
    PNMessagingChannelSubscriptionTimeTokenRetrieve = 1 << 2,
    
    // Channel scheduled long-poll request and waiting for new events from channel on which it is subscribed
    PNMessagingChannelSubscriptionWaitingForEvents = 1 << 3,
    
    // Channel restoring connection after server terminated it
    PNMessagingChannelRestoringConnectionTerminatedByServer = 1 << 4,
    
    // Channel trying to enable presence on particular channels
    PNMessagingChannelEnablingPresence = 1 << 5,
    
    // Channel trying to enable presence on particular channels
    PNMessagingChannelDisablingPresence = 1 << 6,
    
    /**
     Channel re-subscribe after server didn't respond with ping (new time token) message.
     */
    PNMessagingChannelResubscribeOnTimeOut = 1 << 7
};


#pragma mark - Private interface methods

@interface PNMessagingChannel ()


#pragma mark - Properties

// Stores list of channels (including presence) on which this client is subscribed now
@property (nonatomic, strong) NSMutableSet *subscribedChannelsSet;
@property (nonatomic, strong) NSMutableSet *oldSubscribedChannelsSet;

// Stores whether on subscription request should be reset when rescheduling requests or not
@property (nonatomic, assign, getter = isRestoringSubscriptionOnResume) BOOL restoringSubscriptionOnResume;

// Stores current messaging channel state
@property (nonatomic, assign) unsigned long messagingState;

@property (nonatomic, strong) NSTimer *idleTimer;
@property (nonatomic, strong) NSDate *idleTimerFireDate;
@property (nonatomic, strong) NSDate *channelSuspensionDate;


#pragma mark - Instance methods

#pragma mark - Presence observation management

- (void)disablePresenceObservationForChannels:(NSArray *)channels sendRequest:(BOOL)shouldSendRequest;


#pragma mark - Channels management

/**
 * Returns whether messaging channel can resubscribe on channels or not. Will return YES if there is some channels
 * on which it can resubscribe, NO in other case.
 */
- (BOOL)canResubscribe;

/**
 * Will restore channels subscription if doesn't set that it should resubscribe
 */
- (void)restoreSubscription:(BOOL)shouldRestoreSubscriptionFromLastTimeToken;

/**
 * Will try to resubscribe on channels to which it was subscribed before (mostly this method will be used to restore
 * subscription because of new request failure)
 */
- (void)restoreSubscriptionOnPreviousChannels;

/**
 Method will initiate subscription on specified set of channels. This request will add provided channels set to the
 list of channels on which client already subscribed.
 
 @code
 @endcode
 This method extends \a -subscribeOnChannels:withPresenceEvent: and allow to specify whether any changes should be
 performed in specified channels list as for presence enabling / disabling.
 
 @param channels
 List of \b PNChannel instances on which it should subscribe.
 
 @param channelsPresence
 Bit mask from \b PNMessagingConnectionStateFlag enumerator: PNMessagingChannelEnablingPresence or
 PNMessagingChannelDisablingPresence to identify what kind of changes should be performed.
 */
- (void)subscribeOnChannels:(NSArray *)channels withPresence:(NSUInteger)channelsPresence;

/**
 Method will initiate subscription on specified set of channels. This request will add provided channels set to the
 list of channels on which client already subscribed.
 
 @code
 @endcode
 This method extends \a -subscribeOnChannels:withPresence: and allow to specify state which should
 be sent along with subscription request.
 
 @param channels
 List of \b PNChannel instances on which it should subscribe.
 
 @param channelsPresence
 Bit mask from \b PNMessagingConnectionStateFlag enumerator: PNMessagingChannelEnablingPresence or
 PNMessagingChannelDisablingPresence to identify what kind of changes should be performed.
 
 @param clientState
 \b NSDictionary instance with list of parameters which should be bound to the client.
 */
- (void)subscribeOnChannels:(NSArray *)channels withPresence:(NSUInteger)channelsPresence
                    catchUp:(BOOL)shouldCatchUp andClientState:(NSDictionary *)clientState;

/**
 Unsubscribe from all channels and allow to specify whether request has been done by user or not.
 */
- (void)unsubscribeFromChannelsByUserRequest:(BOOL)isLeavingByUserRequest;

/**
 * Same as -updateSubscription but allow to specify on which channels subscription should be updated
 */
- (void)updateSubscriptionForChannels:(NSArray *)channels withPresence:(NSUInteger)presenceType
                           forRequest:(PNSubscribeRequest *)request forcibly:(BOOL)isUpdateForced;


#pragma mark - Presence management

/**
 * Send leave event to all channels to which client subscribed at this moment
 *
 * As soon as client will receive leave request confirmation all messages from unsubscribed channels will be ignored
 */
- (void)leaveSubscribedChannelsByUserRequest:(BOOL)isLeavingByUserRequest;

- (void)leaveChannels:(NSArray *)channels byUserRequest:(BOOL)isLeavingByUserRequest;


#pragma mark - Handler methods

/**
 Called every time when client complete / faile leave request processing.
 
 @param request
 Reference on initial request which has been used.
 
 @param result
 Result can be either PNResponse or PNError instances (depending on reason why this method has been called.
 */
- (void)handleLeaveRequestCompletionForWithRequest:(PNBaseRequest *)request processingResult:(id)result;

/**
 * Called every time when one of events occur on channels:
 *     - initial subscribe
 *     - message
 *     - presence event
 */
- (void)handleEventOnChannelsForRequest:(PNSubscribeRequest *)request withResponse:(PNResponse *)response;

/**
 * Called every time when subscribe request fails
 */
- (void)handleSubscribeDidFail:(PNBaseRequest *)request withError:(PNError *)error;

/**
 * Handle Idle timer trigger and reconnect channel if it is possible
 */
- (void)handleIdleTimer:(NSTimer *)timer;


#pragma mark - Misc methods

/**
 * Start/stop channel idle handler timer. This timer allow to detect situation when client is in idle state
 * longer than this is allowed.
 */
- (void)startChannelIdleTimer;
- (void)stopChannelIdleTimer;
- (void)pauseChannelIdleTimer;
- (void)resumeChannelIdleTimer;

/**
 * Retrieve full list of channels on which channel should subscribe including presence observing channels
 */
- (NSSet *)channelsWithPresenceFromList:(NSArray *)channelsList forSubscribe:(BOOL)listForSubscribe;
- (NSSet *)channelsWithPresenceFromList:(NSArray *)channelsList forSubscribe:(BOOL)listForSubscribe
                           onlyPresence:(BOOL)fetchPresenceChannelsOnly;

/**
 * Retrieve list of channels which is cleared from presence observing instances
 */
- (NSArray *)channelsWithOutPresenceFromList:(NSArray *)channelsList;
- (NSArray *)channelsWithPresenceFromList:(NSArray *)channelsList;

/**
 Retrieve filtered state dictionary based on list of channels for which it is set.
 
 @param state
 Source dictionary which should be filtered with list of channels from \c channels
 
 @param channels
 List of \b PNChannel instances which should be used for state filtering.
 
 @return Filtered client state \b NSDictionary instance.
 */
- (NSDictionary *)stateFromClientState:(NSDictionary *)state forChannels:(NSArray *)channels;

/**
 Retrieve merged state for client based on newly submitted and already processed client state.
 
 @param state
 Newly submitted client state information.
 
 @return Merged client state information.
 */
- (NSDictionary *)mergedClientStateWithState:(NSDictionary *)state;

/**
 * Print out current connection channel state
 */
- (NSString *)stateDescription;


@end


#pragma mark Public interface methods

@implementation PNMessagingChannel


#pragma mark - Class methods

+ (PNMessagingChannel *)messageChannelWithConfiguration:(PNConfiguration *)configuration
                                            andDelegate:(id<PNConnectionChannelDelegate>)delegate {
    
    return (PNMessagingChannel *)[super connectionChannelWithConfiguration:configuration type:PNConnectionChannelMessaging
                                                               andDelegate:delegate];
}


#pragma mark - Instance methods

- (id)initWithConfiguration:(PNConfiguration *)configuration type:(PNConnectionChannelType)connectionChannelType
                andDelegate:(id<PNConnectionChannelDelegate>)delegate {
    
    // Check whether initialization was successful or not
    if ((self = [super initWithConfiguration:configuration type:connectionChannelType andDelegate:delegate])) {
        
        [PNBitwiseHelper clear:&_messagingState];
        self.subscribedChannelsSet = [NSMutableSet set];
        self.oldSubscribedChannelsSet = [NSMutableSet set];
    }
    
    
    return self;
}

- (BOOL)shouldHandleResponse:(PNResponse *)response {
    
    return ([response.callbackMethod hasPrefix:PNServiceResponseCallbacks.subscriptionCallback] ||
            [response.callbackMethod hasPrefix:PNServiceResponseCallbacks.leaveChannelCallback]);
}

- (void)processResponse:(PNResponse *)response forRequest:(PNBaseRequest *)request {
    
    [self pn_dispatchAsynchronouslyBlock:^{
        
        // Check whether 'Leave' request has been processed or not
        if ([request isKindOfClass:[PNLeaveRequest class]] ||
            [response.callbackMethod isEqualToString:PNServiceResponseCallbacks.leaveChannelCallback]) {
            
            // Process leave request process completion
            [self handleLeaveRequestCompletionForWithRequest:request processingResult:response];
            
            // Remove request from queue to unblock it (subscribe events and message post requests was blocked)
            [self destroyRequest:request];
        }
        // Check whether 'Subscription'/'Presence'/'Events' request has been processed or not
        else if (request == nil || [request isKindOfClass:[PNSubscribeRequest class]]) {
            
            // Remove request from queue to unblock it (subscribe events and message post requests was blocked)
            [self destroyRequest:request];
            
            // Process subscription on channels
            [self handleEventOnChannelsForRequest:(PNSubscribeRequest *)request withResponse:response];
        }
    }];
}

- (BOOL)shouldScheduleRequest:(PNBaseRequest *)request {
    
    __block BOOL shouldScheduleRequest = YES;
    
    if ([request isKindOfClass:[PNTimeTokenRequest class]]) {
        
        [self pn_dispatchSynchronouslyBlock:^{
            
            shouldScheduleRequest = (![PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents] &&
                                     ![PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription] &&
                                     ![PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelResubscribeOnTimeOut]);
        }];
    }
    
    
    return shouldScheduleRequest;
}

- (void)handleRequestProcessingDidFail:(PNBaseRequest *)request withError:(PNError *)error {
    
    // Check whether this is 'Subscribe' or 'Leave' request or not
    if ([request isKindOfClass:[PNSubscribeRequest class]] ||
        [request isKindOfClass:[PNLeaveRequest class]]) {
        
        [self pn_dispatchAsynchronouslyBlock:^{
            
            // Retrieve list of channels w/o presence channels to notify user that client was unable to subscribe on
            // specified list of channels
            NSArray *channels = [self channelsWithOutPresenceFromList:[request valueForKey:@"channels"]];
            
            if ([channels count] > 0 && [request isSendingByUserRequest]) {
                
                if ([request isKindOfClass:[PNSubscribeRequest class]]) {
                    
                    // Notify delegate about that client failed to subscribe on channels
                    [self handleSubscribeDidFail:request withError:error];
                }
                else {
                    
                    // Notify delegate about that client failed to leave set of channels
                    [self handleLeaveRequestCompletionForWithRequest:request processingResult:error];
                }
            }
        }];
    }
}

- (void)makeScheduledRequestsFail:(NSArray *)requestsList withError:(PNError *)processingError {
    
    PNError *error = processingError;
    if (error == nil) {
        
        error = [PNError errorWithCode:kPNRequestExecutionFailedOnInternetFailureError];
    }
    
    [requestsList enumerateObjectsUsingBlock:^(NSString *requestIdentifier, NSUInteger requestIdentifierIdx,
                                               BOOL *requestIdentifierEnumeratorStop) {
        
        PNBaseRequest *request = [self requestWithIdentifier:requestIdentifier];
        
        if (![request isKindOfClass:[PNSubscribeRequest class]] || ![(PNSubscribeRequest *)request isInitialSubscription]) {
            
            // Removing failed request from queue
            [self destroyRequest:request];
            [self handleRequestProcessingDidFail:request withError:error];
        }
        
    }];
}

- (void)rescheduleStoredRequests:(NSArray *)requestsList resetRetryCount:(BOOL)shouldResetRequestsRetryCount {

    requestsList = [requestsList copy];
    if ([requestsList count] > 0) {

        [self pn_dispatchSynchronouslyBlock:^{
            
            BOOL useLastTimeToken = [self.messagingDelegate shouldMessagingChannelRestoreWithLastTimeToken:self];
            [requestsList enumerateObjectsWithOptions:NSEnumerationReverse
                                           usingBlock:^(id requestIdentifier, NSUInteger requestIdentifierIdx,
                                                        BOOL *requestIdentifierEnumeratorStop) {
                                               
                   PNBaseRequest *request = [self storedRequestWithIdentifier:requestIdentifier];
                   [request resetWithRetryCount:shouldResetRequestsRetryCount];
                   request.closeConnection = NO;
                   
                   BOOL isSubscribeRequest = [request isKindOfClass:[PNSubscribeRequest class]];
                   if (isSubscribeRequest && self.isRestoringSubscriptionOnResume) {
                       
                       BOOL shouldNotifyAboutSubscriptionRestore = ![PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription];
                       if (!useLastTimeToken) {
                           
                           [(PNSubscribeRequest *)request resetTimeToken];
                       }
                       
                       [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelUpdateSubscription, PNMessagingChannelResubscribeOnTimeOut,
                        PNMessagingChannelSubscriptionWaitingForEvents, BITS_LIST_TERMINATOR];
                       
                       [PNBitwiseHelper addTo:&_messagingState bits:PNMessagingChannelRestoringSubscription,
                        PNMessagingChannelSubscriptionTimeTokenRetrieve, BITS_LIST_TERMINATOR];
                       
                       [(PNSubscribeRequest *)request resetSubscriptionTimeToken];
                       
                       if (shouldNotifyAboutSubscriptionRestore) {
                           
                           // Notify delegate that messaging channel is about to restore subscription on previous channels
                           [self.messagingDelegate messagingChannel:self
                                          willRestoreSubscriptionOn:((PNSubscribeRequest *)request).channels
                                                          sequenced:NO];
                       }
                   }
                   
                   // Check whether client is waiting for request completion
                   BOOL isWaitingForCompletion = [self isWaitingRequestCompletion:request.shortIdentifier];
                   if (isSubscribeRequest) {
                       
                       isWaitingForCompletion = [(PNSubscribeRequest *)request isInitialSubscription];
                   }
                   
                   // Clean up query (if request has been stored in it)
                   [self destroyRequest:request];
                   
                   // Send request back into queue with higher priority among other requests
                   [self scheduleRequest:request shouldObserveProcessing:isWaitingForCompletion outOfOrder:YES
                        launchProcessing:NO];
               }];
            
            // Try to check whether there is leave request or not in stack
            if ([self hasRequestsWithClass:[PNLeaveRequest class]]) {
                
                PNBaseRequest *request = [[self requestsWithClass:[PNLeaveRequest class]] lastObject];
                if (request) {
                    
                    // Check whether client is waiting for request completion
                    BOOL isWaitingForCompletion = [self isWaitingRequestCompletion:request.shortIdentifier];
                    
                    // Clean up query (if request has been stored in it)
                    [self destroyRequest:request];
                    
                    // Send request back into queue with higher priority among other requests
                    [self scheduleRequest:request shouldObserveProcessing:isWaitingForCompletion outOfOrder:YES
                         launchProcessing:NO];
                }
                
            }
            
            
            [self scheduleNextRequest];
        }];
    }
}

- (BOOL)shouldStoreRequest:(PNBaseRequest *)request {
    
    BOOL shouldStoreRequest = [request isKindOfClass:[PNSubscribeRequest class]] ||
    [request isKindOfClass:[PNLeaveRequest class]];
    if (!shouldStoreRequest && [request isKindOfClass:[PNTimeTokenRequest class]]) {
        
        shouldStoreRequest = request.isSendingByUserRequest;
    }
    
    
    return shouldStoreRequest;
}

- (void)terminate {
    
    [self pn_dispatchSynchronouslyBlock:^{
        
        [PNBitwiseHelper clear:&_messagingState];
        
        [self stopChannelIdleTimer];
        [super terminate];
    }];
}


#pragma mark - Connection management

- (void)reconnect {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [PNBitwiseHelper clear:&_messagingState];
    }];
    
    // Forward to the super class
    [super reconnect];
}

- (void)disconnectWithReset:(BOOL)shouldResetCommunicationChannel {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [PNBitwiseHelper clear:&_messagingState];
    
        // Forward to the super class
        [super disconnect];
        
        
        // Check whether communication channel should reset state or not
        if (shouldResetCommunicationChannel) {
            
            // Clean up channels stack
            [self.subscribedChannelsSet removeAllObjects];
            [self.oldSubscribedChannelsSet removeAllObjects];
            [self purgeObservedRequestsPool];
            [self purgeStoredRequestsPool];
            [self clearScheduledRequestsQueue];
        }
    }];
}

- (void)disconnectWithEvent:(BOOL)shouldNotifyOnDisconnection {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [PNBitwiseHelper clear:&_messagingState];
        
        [self stopChannelIdleTimer];
    }];
    
    
    // Forward to the super class
    [super disconnectWithEvent:shouldNotifyOnDisconnection];
}

- (void)suspend {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [PNBitwiseHelper clear:&_messagingState];
        
        if (![super isSuspended]) {
            
            [super suspend];
        }
    }];
    
    [self pauseChannelIdleTimer];
}

- (void)resume {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [PNBitwiseHelper clear:&_messagingState];
        
        if ([super isSuspended]) {
            
            [super resume];
        }
    }];
    
    [self resumeChannelIdleTimer];
}


#pragma mark - Presence management

- (void)leaveSubscribedChannelsByUserRequest:(BOOL)isLeavingByUserRequest {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        // Check whether there some channels which user can leave
        if ([self.subscribedChannelsSet count] > 0) {

            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                return @[PNLoggerSymbols.connectionChannel.subscribe.leaveAllChannels, (self.name ? self.name : self),
                        @(self.messagingState)];
            }];
            
            [self leaveChannels:[self.subscribedChannelsSet allObjects] byUserRequest:isLeavingByUserRequest];
        }
    }];
}

- (void)leaveChannels:(NSArray *)channels byUserRequest:(BOOL)isLeavingByUserRequest {
    
    [self pn_dispatchSynchronouslyBlock:^{
    
        // Check whether specified channels set contains channels on which client not subscribed
        NSSet *channelsSet = [NSSet setWithArray:channels];
        if (![self.subscribedChannelsSet intersectsSet:channelsSet]) {
            
            // Extracting channels on which client is not subscribed at this moment
            // (set will contain only those channels, on which client subscribed at this moment)
            NSMutableSet *filteredChannels = [self.subscribedChannelsSet mutableCopy];
            [filteredChannels intersectSet:channelsSet];
            
            // Retrieve list of channel on which client really subscribed (other channels ignored)
            channelsSet = filteredChannels;
        }
        
        // Retrieve set of channels (including presence observers) from which client should unsubscribe
        NSArray *channelsForUnsubscribe = [[self channelsWithPresenceFromList:[channelsSet allObjects] forSubscribe:NO] allObjects];
        if ([channelsForUnsubscribe count] > 0) {

            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                return @[PNLoggerSymbols.connectionChannel.subscribe.leaveSpecificChannels, (self.name ? self.name : self),
                        @(self.messagingState)];
            }];
            
            // Reset last update time token for channels in list
            [channels makeObjectsPerformSelector:@selector(resetUpdateTimeToken)];
            
            // Schedule request to be processed as soon as queue will be processed
            PNLeaveRequest *request = [PNLeaveRequest leaveRequestForChannels:channelsForUnsubscribe
                                                                byUserRequest:isLeavingByUserRequest];
            
            request.closeConnection = isLeavingByUserRequest;
            if (!isLeavingByUserRequest) {
                
                // Check whether connection channel is waiting for response via long-poll connection or not
                request.closeConnection = [PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents];
            }
            if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringConnectionTerminatedByServer]) {
                
                request.closeConnection = NO;
            }
            
            if (![self hasRequestsWithClass:[PNSubscribeRequest class]]) {
                
                [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelRestoringSubscription, PNMessagingChannelUpdateSubscription,
                 PNMessagingChannelResubscribeOnTimeOut, BITS_LIST_TERMINATOR];
            }
            
            if (isLeavingByUserRequest) {
                
                [self.messagingDelegate messagingChannel:self willUnsubscribeFrom:request.channels sequenced:NO];
            }
            [self destroyByRequestClass:[PNLeaveRequest class]];
            [self scheduleRequest:request shouldObserveProcessing:YES];
        }
    }];
}


#pragma mark - Channels management

- (NSArray *)subscribedChannels {
    
    __block NSArray *subscribedChannels = nil;
    [self pn_dispatchSynchronouslyBlock:^{
        
        subscribedChannels = [self channelsWithOutPresenceFromList:[self.subscribedChannelsSet allObjects]];
    }];
    
    
    return subscribedChannels;
}

- (NSArray *)fullSubscribedChannelsList {
    
    __block NSArray *fullSubscribedChannelsList = nil;
    [self pn_dispatchSynchronouslyBlock:^{
        
        fullSubscribedChannelsList = [self.subscribedChannelsSet allObjects];
    }];
    
    
    return fullSubscribedChannelsList;
}

- (BOOL)isSubscribedForChannel:(PNChannel *)channel {
    
    __block BOOL isSubscribedForChannel = NO;
    [self pn_dispatchSynchronouslyBlock:^{
        
        isSubscribedForChannel = [self.subscribedChannelsSet containsObject:channel];
    }];
    
    
    return isSubscribedForChannel;
}

- (BOOL)willRestoreSubscription {
    
    __block BOOL willRestoreSubscription = NO;
    [self pn_dispatchSynchronouslyBlock:^{
        
        willRestoreSubscription = [PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription];
        if (!willRestoreSubscription) {
            
            willRestoreSubscription = ([self canResubscribe] && [self.messagingDelegate shouldMessagingChannelRestoreSubscription:self] &&
                                       ![PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents]);
        }
    }];
    
    
    return willRestoreSubscription;
}

- (BOOL)canResubscribe {
    
    __block BOOL canResubscribe = NO;
    [self pn_dispatchSynchronouslyBlock:^{
        
        canResubscribe = ([self.subscribedChannelsSet count] > 0);
    }];
    
    
    return canResubscribe;
}

- (void)restoreSubscription:(BOOL)shouldRestoreSubscriptionFromLastTimeToken {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        // Check whether client has been subscribed on channels before or not
        if ([self.subscribedChannelsSet count]) {
            
            NSString *symbolCode = PNLoggerSymbols.connectionChannel.subscribe.restoringSubscription;
            if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelResubscribeOnTimeOut]) {
                
                symbolCode = PNLoggerSymbols.connectionChannel.subscribe.resubscribeOnIdle;
            }

            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                return @[symbolCode, (self.name ? self.name : self), @(shouldRestoreSubscriptionFromLastTimeToken),
                        @(self.messagingState)];
            }];
            
            [self destroyByRequestClass:[PNLeaveRequest class]];
            [self destroyByRequestClass:[PNSubscribeRequest class]];
            
            if (!shouldRestoreSubscriptionFromLastTimeToken) {
                
                // Reset last update time token for channels in list
                [self.subscribedChannelsSet makeObjectsPerformSelector:@selector(resetUpdateTimeToken)];
            }
            
            [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelRestoringSubscription, PNMessagingChannelUpdateSubscription,
             PNMessagingChannelSubscriptionWaitingForEvents, BITS_LIST_TERMINATOR];
            [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelSubscriptionTimeTokenRetrieve];
            
            if (![PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelResubscribeOnTimeOut]) {
                
                [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelRestoringSubscription];
            }
            [PNBitwiseHelper removeFrom:&_messagingState bit:PNMessagingChannelResubscribeOnTimeOut];
            
            NSDictionary *clientStateInformation = [self.messagingDelegate clientStateInformationForChannels:[self.subscribedChannelsSet allObjects]];
            PNSubscribeRequest *resubscribeRequest = [PNSubscribeRequest subscribeRequestForChannels:[self.subscribedChannelsSet allObjects]
                                                                                       byUserRequest:YES
                                                                                     withClientState:clientStateInformation];
            [resubscribeRequest resetSubscriptionTimeToken];
            
            // Check whether connection channel is waiting for response via long-poll connection or not
            resubscribeRequest.closeConnection = YES;
            if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringConnectionTerminatedByServer]) {
                
                resubscribeRequest.closeConnection = NO;
            }
            
            if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription]) {
                
                // Notify delegate that messaging channel is about to restore subscription on previous channels
                [self.messagingDelegate messagingChannel:self willRestoreSubscriptionOn:resubscribeRequest.channels
                                               sequenced:NO];
            }
            
            
            [self scheduleRequest:resubscribeRequest
          shouldObserveProcessing:[PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionTimeTokenRetrieve]
                       outOfOrder:YES launchProcessing:YES];
        }
    }];
}

- (void)updateSubscriptionForChannels:(NSArray *)channels withPresence:(NSUInteger)presenceType
                           forRequest:(PNSubscribeRequest *)request forcibly:(BOOL)isUpdateForced {
    
    // Ensure that client connected to at least one channel
    if ([channels count] > 0 || request) {

        [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

            return @[PNLoggerSymbols.connectionChannel.subscribe.updateSubscriptionWithNewTimeToken, (self.name ? self.name : self),
                    @(self.messagingState)];
        }];
        
        
        BOOL shouldSendUpdateSubscriptionRequest = YES;
        
        if (!isUpdateForced) {
            
            // Check whether user want to subscribe on particular channel (w/ or w/o presence event) or unsubscribe from all channels
            if ([self hasRequestsWithClass:[PNSubscribeRequest class]] || [self hasRequestsWithClass:[PNLeaveRequest class]]) {
                
                shouldSendUpdateSubscriptionRequest = NO;
                
                // Check whether user want to unsubscribe from all channels or not
                __block BOOL isLeavingAllChannels = NO;
                NSArray *leaveRequests  = [self requestsWithClass:[PNLeaveRequest class]];
                [leaveRequests enumerateObjectsUsingBlock:^(PNLeaveRequest *leaveRequest, NSUInteger leaveRequestIdx,
                                                            BOOL *leaveRequestEnumeratorStop) {
                    
                    if (!isLeavingAllChannels) {
                        
                        // Check whether we already found request which will unsubscribe from all channels or not
                        NSSet *leaveChannelsSet = [NSSet setWithArray:leaveRequest.channels];
                        if ([leaveChannelsSet isEqualToSet:self.subscribedChannelsSet]) {
                            
                            isLeavingAllChannels = YES;
                        }
                    }
                    else {
                        
                        [self destroyRequest:leaveRequest];
                    }
                }];
                
                // Check whether is leaving only partial channels and there is no subscribe request for rest of the channels
                if ([leaveRequests count] > 0 && !isLeavingAllChannels && ![self hasRequestsWithClass:[PNSubscribeRequest class]]) {
                    
                    [self destroyByRequestClass:[PNLeaveRequest class]];
                    shouldSendUpdateSubscriptionRequest = YES;
                }
                
                if ([self hasRequestsWithClass:[PNSubscribeRequest class]]) {
                    
                    shouldSendUpdateSubscriptionRequest = NO;
                }
            }
        }
        
        if (!shouldSendUpdateSubscriptionRequest) {

            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                return @[PNLoggerSymbols.connectionChannel.subscribe.subscriptionUpdateCanceled, (self.name ? self.name : self),
                        @(self.messagingState)];
            }];
        }
        
        [self pn_dispatchAsynchronouslyBlock:^{
            
            BOOL shouldModifyPresence = [PNBitwiseHelper is:presenceType containsBits:PNMessagingChannelEnablingPresence,
                                         PNMessagingChannelDisablingPresence, BITS_LIST_TERMINATOR];
            
            // Depending on whether client already try to subscribe on another set of channels or leave all channels, there maybe no
            // reason to send request to subscribe on channels with updated time token
            if (shouldSendUpdateSubscriptionRequest) {
                
                [self destroyByRequestClass:[PNLeaveRequest class]];
                [self destroyByRequestClass:[PNSubscribeRequest class]];
                
                NSMutableSet *channelsForSubscription = [NSMutableSet setWithArray:channels];
                if (request) {
                    
                    [channelsForSubscription addObjectsFromArray:[request channelsForSubscription]];
                }
                if ([[channels lastObject] isTimeTokenChangeLocked]) {
                    
                    [channelsForSubscription makeObjectsPerformSelector:@selector(unlockTimeTokenChange)];
                }
                
                PNSubscribeRequest *subscribeRequest = [PNSubscribeRequest subscribeRequestForChannels:[channelsForSubscription allObjects]
                                                                                         byUserRequest:YES
                                                                                       withClientState:request.state];
                if (shouldModifyPresence) {
                    
                    subscribeRequest.channelsForPresenceEnabling = request.channelsForPresenceEnabling;
                    subscribeRequest.channelsForPresenceDisabling = request.channelsForPresenceDisabling;
                    [subscribeRequest resetTimeTokenTo:[PNChannel largestTimetokenFromChannels:subscribeRequest.channels]];
                }
                
                BOOL isWaitingForTimeToken = [PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionTimeTokenRetrieve];
                [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelUpdateSubscription];
                subscribeRequest.closeConnection = [PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents];
                if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringConnectionTerminatedByServer]) {
                    
                    subscribeRequest.closeConnection = NO;
                }
                
                if (!isWaitingForTimeToken) {
                    
                    subscribeRequest.state = [self.messagingDelegate clientStateInformationForChannels:[channelsForSubscription allObjects]];
                }
                
                // In case if we are restoring subscription and user decided to discard old time token client should
                // send channel long-poll request (with updated time token) before other requests
                [self scheduleRequest:subscribeRequest shouldObserveProcessing:[subscribeRequest isInitialSubscription]
                           outOfOrder:[PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription]
                     launchProcessing:YES];
            }
        }];
    }
    
}

- (void)subscribeOnChannels:(NSArray *)channels {
    
    [self subscribeOnChannels:channels withCatchUp:NO andClientState:nil];
}

- (void)subscribeOnChannels:(NSArray *)channels withCatchUp:(BOOL)shouldCatchUp
             andClientState:(NSDictionary *)clientState {
    
    clientState = [[self stateFromClientState:clientState
                                  forChannels:[[self subscribedChannels] arrayByAddingObjectsFromArray:channels]] mutableCopy];
    
    [self subscribeOnChannels:channels withPresence:0 catchUp:shouldCatchUp
               andClientState:[self mergedClientStateWithState:clientState]];
}

- (NSSet *)channelsForPresenceEnablingFromArray:(NSArray *)channels {
    
    __block NSSet *channelsForPresenceEnabling = nil;
    [self pn_dispatchSynchronouslyBlock:^{
        
        NSMutableSet *presenceChannelsSet = [NSMutableSet setWithSet:[self channelsWithPresenceFromList:channels forSubscribe:YES onlyPresence:YES]];
        NSMutableSet *existingPresenceChannelsSet = [NSMutableSet setWithArray:[self channelsWithPresenceFromList:[self.subscribedChannelsSet allObjects]]];
        [presenceChannelsSet removeObject:[NSNull null]];
        [existingPresenceChannelsSet removeObject:[NSNull null]];
        
        // Remove all presence enabled channels on which client already subscribed. It will allow to find set of channels which has been enabled for presence
        // observation.
        [presenceChannelsSet minusSet:existingPresenceChannelsSet];
        
        channelsForPresenceEnabling = ([presenceChannelsSet count] ? presenceChannelsSet : nil);
    }];
    
    
    return channelsForPresenceEnabling;
}

- (NSSet *)channelsForPresenceDisablingFromArray:(NSArray *)channels {
    
    __block NSSet *channelsForPresenceDisabling = nil;
    [self pn_dispatchSynchronouslyBlock:^{
    
        NSMutableSet *channelsSet = [NSMutableSet set];
        NSMutableSet *presenceChannelsSet = [NSMutableSet setWithSet:[self channelsWithPresenceFromList:channels forSubscribe:YES onlyPresence:YES]];
        [presenceChannelsSet removeObject:[NSNull null]];
        NSMutableSet *observedChannelsSet = [NSMutableSet setWithSet:[presenceChannelsSet valueForKey:@"observedChannel"]];
        [observedChannelsSet removeObject:[NSNull null]];
        NSMutableSet *existingPresenceChannelsSet = [NSMutableSet setWithArray:[self channelsWithPresenceFromList:[self.subscribedChannelsSet allObjects]]];
        [existingPresenceChannelsSet removeObject:[NSNull null]];
        NSMutableSet *existingObservedChannelsSet = [NSMutableSet setWithSet:[existingPresenceChannelsSet valueForKey:@"observedChannel"]];
        [existingObservedChannelsSet removeObject:[NSNull null]];
        
        [existingObservedChannelsSet enumerateObjectsUsingBlock:^(PNChannel *channel, BOOL *channelEnumeratorStop) {
            
            // Checking on whether channel from which presence observation already enabled (subscribed on this channel) exist in list of channels for subscription
            // and in same time still has observation instance.
            if ([channels containsObject:channel] && ![observedChannelsSet containsObject:channel]) {
                
                [channelsSet addObject:([channel presenceObserver] ? [channel presenceObserver] : [PNChannelPresence presenceForChannel:channel] )];
            }
        }];
        
        channelsForPresenceDisabling = ([channelsSet count] ? channelsSet : nil);
    }];
    
    
    return channelsForPresenceDisabling;
}

- (void)subscribeOnChannels:(NSArray *)channels withPresence:(NSUInteger)channelsPresence {
    
    [self subscribeOnChannels:channels withPresence:channelsPresence catchUp:NO andClientState:nil];
}

- (void)subscribeOnChannels:(NSArray *)channels withPresence:(NSUInteger)channelsPresence catchUp:(BOOL)shouldCatchUp
             andClientState:(NSDictionary *)clientState {
    
    [self pn_dispatchAsynchronouslyBlock:^{
        
        NSDictionary *clientStateForRequest = clientState;
        NSUInteger channelPresenceOperation = channelsPresence;
        NSMutableSet *channelsSet = nil;
        
        // Stores whether method is used to enable presence on channels (there is no regular channels, only presence observation).
        BOOL isOnlyEnablingPresence = NO;
        BOOL isDisablingPresenceOnAllChannels = NO;
        BOOL isChangingPresenceOnSubscribedChannels = NO;
        BOOL indirectionalPresenceModification = NO;
        NSSet *channelsForPresenceEnabling = nil;
        NSSet *channelsForPresenceDisabling = nil;
        
        BOOL isPresenceModification = [PNBitwiseHelper is:channelPresenceOperation containsBits:PNMessagingChannelEnablingPresence,
                                       PNMessagingChannelDisablingPresence, BITS_LIST_TERMINATOR];
        
        if (!isPresenceModification) {
            
            unsigned long updatedChannelsPresence = channelPresenceOperation;
            channelsForPresenceEnabling  = [self channelsForPresenceEnablingFromArray:channels];
            channelsForPresenceDisabling  = [self channelsForPresenceDisablingFromArray:channels];
            
            if ([channelsForPresenceEnabling count]) {
                
                [PNBitwiseHelper addTo:&updatedChannelsPresence bit:PNMessagingChannelEnablingPresence];
            }
            if ([channelsForPresenceDisabling count]) {
                
                [PNBitwiseHelper addTo:&updatedChannelsPresence bit:PNMessagingChannelDisablingPresence];
            }
            channelPresenceOperation = updatedChannelsPresence;
            isPresenceModification = [PNBitwiseHelper is:channelPresenceOperation containsBits:PNMessagingChannelEnablingPresence,
                                      PNMessagingChannelDisablingPresence, BITS_LIST_TERMINATOR];
            
            indirectionalPresenceModification = isPresenceModification;
        }
        
        if (isPresenceModification) {
            
            NSString *symbolCode = (!indirectionalPresenceModification ? PNLoggerSymbols.connectionChannel.subscribe.enablingPresenceOnSetOfChannels :
                                    PNLoggerSymbols.connectionChannel.subscribe.enablingPresenceAndSubscribingOnSetOfChannels);
            if ([PNBitwiseHelper is:channelPresenceOperation strictly:YES containsBits:PNMessagingChannelEnablingPresence,
                 PNMessagingChannelDisablingPresence, BITS_LIST_TERMINATOR]) {
                
                symbolCode = (!indirectionalPresenceModification ? PNLoggerSymbols.connectionChannel.subscribe.enablingDisablingPresenceOnSetOfChannels :
                              PNLoggerSymbols.connectionChannel.subscribe.enablingDisablingPresenceAndSubscribingOnSetOfChannels);
            }
            else if ([PNBitwiseHelper is:channelPresenceOperation containsBit:PNMessagingChannelDisablingPresence]) {
                
                symbolCode = (!indirectionalPresenceModification ? PNLoggerSymbols.connectionChannel.subscribe.disablingPresenceOnSetOfChannels :
                              PNLoggerSymbols.connectionChannel.subscribe.disablingPresenceAndSubscribingOnSetOfChannels);
            }
            
            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{
                
                return @[symbolCode, (self.name ? self.name : self), @(self.messagingState)];
            }];
        }
        else {
            
            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{
                
                return @[PNLoggerSymbols.connectionChannel.subscribe.subscribingOnSetOfChannels, (self.name ? self.name : self),
                         @(self.messagingState)];
            }];
        }
        
        if (isPresenceModification) {
            
            if (!indirectionalPresenceModification) {
                
                NSMutableSet *targetPresenceObservers = [NSMutableSet setWithArray:channels];
                NSMutableSet *presenceObservers = [NSMutableSet setWithArray:[self channelsWithPresenceFromList:[self.subscribedChannelsSet allObjects]]];
                [presenceObservers removeObject:[NSNull null]];
                
                if ([PNBitwiseHelper is:channelPresenceOperation containsBit:PNMessagingChannelEnablingPresence]) {
                    
                    // Remove presence observers for which client already subscribed
                    [targetPresenceObservers minusSet:presenceObservers];
                    
                    channelsForPresenceEnabling = targetPresenceObservers;
                }
                else {
                    
                    // Extract channels for which PubNub client really enabled presence observation
                    [targetPresenceObservers intersectSet:presenceObservers];
                    
                    channelsForPresenceDisabling = targetPresenceObservers;
                }
            }
        }
        
        // Check whether subscribe request or whether this is subscribe request with indirectional presence observation state change
        if (!isPresenceModification || indirectionalPresenceModification) {
            
            channelsSet = [NSMutableSet setWithArray:[self channelsWithOutPresenceFromList:channels]];
            NSUInteger channelsSetCount = [channelsSet count];
            [channelsSet minusSet:self.subscribedChannelsSet];
            
            // Set to \c YES in case if user tried to update presence observation with PNChannel constructor on channel for
            // which client already subscribed.
            isChangingPresenceOnSubscribedChannels = indirectionalPresenceModification && channelsSetCount > 0 && [channelsSet count] == 0;
        }
        
        // Check whether there is at leas one channel at which client didn't subscribed yet
        BOOL isAbleToSendRequest = [channelsSet count] || [channelsForPresenceEnabling count] || [channelsForPresenceDisabling count];
        
        if (isAbleToSendRequest) {
            
            BOOL hasValidSetOfChannels = YES;
            [self destroyByRequestClass:[PNSubscribeRequest class]];
            
            NSMutableSet *subscriptionChannelsSet = [NSMutableSet setWithSet:self.subscribedChannelsSet];
            [self.oldSubscribedChannelsSet setSet:subscriptionChannelsSet];
            [subscriptionChannelsSet unionSet:channelsSet];
            
            // In case if user defined that subscription request should keep previous time token or request new one
            // client will update channels time token value.
            if (!shouldCatchUp && ![self.messagingDelegate shouldKeepTimeTokenOnChannelsListChange:self]) {
                
                [subscriptionChannelsSet makeObjectsPerformSelector:@selector(resetUpdateTimeToken)];
                [channelsForPresenceEnabling makeObjectsPerformSelector:@selector(resetUpdateTimeToken)];
                [channelsForPresenceDisabling makeObjectsPerformSelector:@selector(resetUpdateTimeToken)];
            }
            
            if (!clientStateForRequest) {
                
                clientStateForRequest = [self.messagingDelegate clientStateInformationForChannels:[subscriptionChannelsSet allObjects]];
            }
            PNSubscribeRequest *subscribeRequest = [PNSubscribeRequest subscribeRequestForChannels:[subscriptionChannelsSet allObjects]
                                                                                     byUserRequest:YES
                                                                                   withClientState:clientStateForRequest];
            [subscribeRequest resetSubscriptionTimeToken];
            
            if ((!isPresenceModification || indirectionalPresenceModification) && [channelsSet count]) {
                
                [self.messagingDelegate messagingChannel:self
                                 willSubscribeOnChannels:[self channelsWithOutPresenceFromList:[channelsSet allObjects]]
                                               sequenced:([channelsForPresenceEnabling count] || [channelsForPresenceDisabling count])];
            }
            
            if ([channelsForPresenceEnabling count]) {
                
                if ([subscribeRequest.channels count] == 0 && [channelsForPresenceDisabling count] == 0) {
                    
                    isOnlyEnablingPresence = YES;
                }
                
                subscribeRequest.channelsForPresenceEnabling = [channelsForPresenceEnabling allObjects];
                [self.messagingDelegate messagingChannel:self
                         willEnablePresenceObservationOn:[[channelsForPresenceEnabling valueForKey:@"observedChannel"] allObjects]
                                               sequenced:([channelsForPresenceDisabling count] > 0)];
            }
            
            if ([channelsForPresenceDisabling count]) {
                
                if ([subscribeRequest.channels count] == [channelsForPresenceDisabling count] &&
                    [[NSSet setWithArray:subscribeRequest.channels] isEqualToSet:channelsForPresenceDisabling]) {
                    
                    hasValidSetOfChannels = NO;
                    isDisablingPresenceOnAllChannels = YES;
                    [self.subscribedChannelsSet removeAllObjects];
                    [self.oldSubscribedChannelsSet removeAllObjects];
                    
                    [self.messagingDelegate messagingChannel:self
                             didDisablePresenceObservationOn:[[channelsForPresenceDisabling valueForKey:@"observedChannel"] allObjects]
                                                   sequenced:NO];
                }
                else {
                    
                    subscribeRequest.channelsForPresenceDisabling = [channelsForPresenceDisabling allObjects];
                    [self.messagingDelegate messagingChannel:self
                            willDisablePresenceObservationOn:[[channelsForPresenceDisabling valueForKey:@"observedChannel"] allObjects]
                                                   sequenced:NO];
                }
            }
            
            if (hasValidSetOfChannels) {
                
                if ((([channelsSet count] && [PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents]) ||
                     ((isPresenceModification && !indirectionalPresenceModification) || indirectionalPresenceModification)) &&
                    !isOnlyEnablingPresence && !isDisablingPresenceOnAllChannels) {
                    
                    subscribeRequest.closeConnection = YES;
                }
                
                [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelSubscriptionTimeTokenRetrieve,
                 PNMessagingChannelSubscriptionWaitingForEvents, BITS_LIST_TERMINATOR];
                [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelSubscriptionTimeTokenRetrieve];
                
                
                if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringConnectionTerminatedByServer]) {
                    
                    subscribeRequest.closeConnection = NO;
                }
                
                if ([[subscribeRequest.channelsForSubscription lastObject] isTimeTokenChangeLocked] && ![subscribeRequest isInitialSubscription]) {
                    
                    [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelSubscriptionTimeTokenRetrieve];
                    [PNBitwiseHelper removeFrom:&_messagingState bit:PNMessagingChannelSubscriptionWaitingForEvents];
                    
                    [subscribeRequest resetTimeToken];
                }
                
                [self scheduleRequest:subscribeRequest shouldObserveProcessing:[PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionTimeTokenRetrieve]];
            }
            else {
                
                isAbleToSendRequest = NO;
                [self reconnect];
            }
        }
        
        if ([channelsSet count] == 0 && (!(isPresenceModification && indirectionalPresenceModification) || isChangingPresenceOnSubscribedChannels) &&
            !isOnlyEnablingPresence && !isDisablingPresenceOnAllChannels) {
            
            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{
                
                return @[PNLoggerSymbols.connectionChannel.subscribe.subscribedOnSetOfChannelsEarlier,
                         (self.name ? self.name : self), @(self.messagingState)];
            }];
            
            // Checking whether provided client state changed or not.
            if ([clientStateForRequest count] && ![clientStateForRequest isEqualToDictionary:[self.messagingDelegate clientStateInformation]]) {
                
                // Looks like client try to subscribed on channels on which it already subscribed, and mean time changed
                // client state values, so we should force state storage and client re-subscription.
                [self.messagingDelegate updateClientStateInformationWith:clientStateForRequest
                                                             forChannels:[self.subscribedChannelsSet allObjects]];
                
                [self updateSubscriptionForChannels:[self.subscribedChannelsSet allObjects] withPresence:0
                                         forRequest:nil forcibly:YES];
            }
            
            [self.messagingDelegate messagingChannel:self didSubscribeOn:channels sequenced:isPresenceModification
                                     withClientState:clientStateForRequest];
        }
        
        
        if (isPresenceModification && !isAbleToSendRequest) {
            
            if ([PNBitwiseHelper is:channelPresenceOperation containsBit:PNMessagingChannelEnablingPresence]) {
                
                [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{
                    
                    return @[PNLoggerSymbols.connectionChannel.subscribe.enabledPresenceOnSetOfChannelsEarlier,
                             (self.name ? self.name : self), @(self.messagingState)];
                }];
                
                NSArray *presenceEnabledChannelsList = [[channelsForPresenceEnabling valueForKey:@"observedChannel"] allObjects];
                if (![presenceEnabledChannelsList count]) {
                    
                    presenceEnabledChannelsList = [[self channelsWithPresenceFromList:channels] valueForKey:@"observedChannel"];
                }
                
                [self.messagingDelegate messagingChannel:self
                          didEnablePresenceObservationOn:presenceEnabledChannelsList
                                               sequenced:[PNBitwiseHelper is:channelPresenceOperation containsBit:PNMessagingChannelDisablingPresence]];
            }
            
            if ([PNBitwiseHelper is:channelPresenceOperation containsBit:PNMessagingChannelDisablingPresence]) {
                
                [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{
                    
                    return @[PNLoggerSymbols.connectionChannel.subscribe.disabledPresenceOnSetOfChannelsEarlier,
                             (self.name ? self.name : self), @(self.messagingState)];
                }];
                
                // Remove 'presence enabled' state from list of specified channels
                [self disablePresenceObservationForChannels:[channelsForPresenceDisabling valueForKey:@"observedChannel"]
                                                sendRequest:NO];
                
                [self.messagingDelegate messagingChannel:self
                         didDisablePresenceObservationOn:[[channelsForPresenceDisabling valueForKey:@"observedChannel"] allObjects]
                                               sequenced:NO];
            }
        }
    }];
}

- (void)restoreSubscriptionOnPreviousChannels {
    
    [self pn_dispatchAsynchronouslyBlock:^{
        
        NSArray *channelsList = [self.subscribedChannelsSet allObjects];
        if ([channelsList count] > 0) {
            
            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{
                
                return @[PNLoggerSymbols.connectionChannel.subscribe.subscribingOnPreviousChannels,
                         (self.name ? self.name : self), @(self.messagingState)];
            }];
            
            [self destroyByRequestClass:[PNLeaveRequest class]];
            [self destroyByRequestClass:[PNSubscribeRequest class]];
            
            [PNBitwiseHelper removeFrom:&_messagingState bit:PNMessagingChannelResubscribeOnTimeOut];
            [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelRestoringSubscription];
            
            NSDictionary *clientStateInformation = [self.messagingDelegate clientStateInformationForChannels:channelsList];
            PNSubscribeRequest *resubscribeRequest = [PNSubscribeRequest subscribeRequestForChannels:channelsList
                                                                                       byUserRequest:NO
                                                                                     withClientState:clientStateInformation];
            resubscribeRequest.closeConnection = [PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents];
            if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringConnectionTerminatedByServer]) {
                
                resubscribeRequest.closeConnection = NO;
            }
            
            [self scheduleRequest:resubscribeRequest
          shouldObserveProcessing:![PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents]
                       outOfOrder:YES launchProcessing:YES];
        }
    }];
}

- (void)unsubscribeFromChannelsByUserRequest:(BOOL)isLeavingByUserRequest {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        // In case if unsubscribe has been triggered by user, there is no possibility that client can be in
        // 'subscription restore' state
        if (isLeavingByUserRequest) {
            
            [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelRestoringSubscription, PNMessagingChannelUpdateSubscription,
             PNMessagingChannelResubscribeOnTimeOut, BITS_LIST_TERMINATOR];
        }
        
        // Check whether should generate 'leave' presence event or not
        [self leaveSubscribedChannelsByUserRequest:isLeavingByUserRequest];
    }];
}

- (void)unsubscribeFromChannels:(NSArray *)channels {
    
    [self unsubscribeFromChannels:channels byUserRequest:YES ];
}

- (void)unsubscribeFromChannels:(NSArray *)channels byUserRequest:(BOOL)isLeavingByUserRequest {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        // Retrieve list of channels which will left after unsubscription
        NSMutableSet *currentlySubscribedChannels = [self.subscribedChannelsSet mutableCopy];
        NSSet *channelsWithPresence = [self channelsWithPresenceFromList:channels forSubscribe:NO];
        
        // Check whether there is at least one of channels from which client should unsubscribe is in the list
        // of subscribed or not
        if ([currentlySubscribedChannels intersectsSet:channelsWithPresence]) {
            
            [currentlySubscribedChannels minusSet:channelsWithPresence];
            [self destroyByRequestClass:[PNSubscribeRequest class]];
            [self leaveChannels:[channelsWithPresence allObjects] byUserRequest:isLeavingByUserRequest];
            
            
            if (isLeavingByUserRequest && [currentlySubscribedChannels count] > 0) {
                
                // In case if user defined that subscription request should keep previous time token or request new one
                // client will update channels time token value.
                if (![self.messagingDelegate shouldKeepTimeTokenOnChannelsListChange:self]) {
                    
                    [currentlySubscribedChannels makeObjectsPerformSelector:@selector(resetUpdateTimeToken)];
                }
                
                NSDictionary *clientStateInformation = [self.messagingDelegate clientStateInformationForChannels:[currentlySubscribedChannels allObjects]];
                PNSubscribeRequest *subscribeRequest = [PNSubscribeRequest subscribeRequestForChannels:[currentlySubscribedChannels allObjects]
                                                                                         byUserRequest:isLeavingByUserRequest
                                                                                       withClientState:clientStateInformation];
                [subscribeRequest resetSubscriptionTimeToken];
                
                subscribeRequest.closeConnection = [PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents];
                
                [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelSubscriptionTimeTokenRetrieve,
                 PNMessagingChannelSubscriptionWaitingForEvents, BITS_LIST_TERMINATOR];
                [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelSubscriptionTimeTokenRetrieve];
                if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringConnectionTerminatedByServer]) {
                    
                    subscribeRequest.closeConnection = NO;
                }
                
                [self destroyByRequestClass:[PNSubscribeRequest class]];
                
                // Resubscribe on rest of channels which is left after unsubscribe
                [self scheduleRequest:subscribeRequest
              shouldObserveProcessing:![PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents]];
            }
            else if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents]) {
                
                // Reconnect messaging channel to free up long-poll on server
                [self reconnect];
            }
        }
        else {
            
            // Schedule immediately that client unsubscribed from suggested channels
            [self.messagingDelegate messagingChannel:self didUnsubscribeFrom:channels sequenced:NO ];
            
            if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents]) {
                
                // Reconnect messaging channel to free up long-poll on server
                [self reconnect];
            }
        }
    }];
}


#pragma mark - Presence observation management

- (BOOL)isPresenceObservationEnabledForChannel:(PNChannel *)channel {
    
    __block BOOL isPresenceObservationEnabledForChannel = NO;
    PNChannelPresence *presenceObserver = [channel presenceObserver];
    [self pn_dispatchSynchronouslyBlock:^{
        
        isPresenceObservationEnabledForChannel = (presenceObserver != nil && [self.subscribedChannelsSet containsObject:presenceObserver]);
    }];
    
    
    return isPresenceObservationEnabledForChannel;
}

- (NSArray *)presenceEnabledChannels {
    
    __block NSArray *presenceEnabledChannels = nil;
    NSPredicate *filterPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        
        return [object isKindOfClass:[PNChannelPresence class]];
    }];
    [self pn_dispatchSynchronouslyBlock:^{
        
        presenceEnabledChannels = [[[self.subscribedChannelsSet allObjects] filteredArrayUsingPredicate:filterPredicate]
                                   valueForKeyPath:@"observedChannel"];
    }];
    
    
    return presenceEnabledChannels;
}

- (void)enablePresenceObservationForChannels:(NSArray *)channels {
    
    NSMutableArray *presenceObservers = [[channels valueForKey:@"presenceObserver"] mutableCopy];
    [presenceObservers removeObject:[NSNull null]];
    
    [self subscribeOnChannels:presenceObservers withPresence:PNMessagingChannelEnablingPresence];
}

- (void)disablePresenceObservationForChannels:(NSArray *)channels {
    
    [self disablePresenceObservationForChannels:channels sendRequest:YES];
}

- (void)disablePresenceObservationForChannels:(NSArray *)channels sendRequest:(BOOL)shouldSendRequest {
    
    if (shouldSendRequest) {
        
        NSMutableArray *presenceObservers = [[channels valueForKey:@"presenceObserver"] mutableCopy];
        [presenceObservers removeObject:[NSNull null]];
        
        
        if ([presenceObservers count]) {
            
            [self subscribeOnChannels:presenceObservers withPresence:PNMessagingChannelDisablingPresence];
        }
        else {

            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                return @[PNLoggerSymbols.connectionChannel.subscribe.disabledPresenceOnSetOfChannelsEarlier,
                        (self.name ? self.name : self), @(self.messagingState)];
            }];
            
            // Remove 'presence enabled' state from list of specified channels
            [self disablePresenceObservationForChannels:channels sendRequest:NO];
            
            [self.messagingDelegate messagingChannel:self didDisablePresenceObservationOn:channels sequenced:NO];
        }
    }
    else {
        
        // Enumerate over the list of channels and mark that it should observe for presence
        [channels enumerateObjectsUsingBlock:^(PNChannel *channel, NSUInteger channelIdx, BOOL *channelEnumeratorStop) {
            
            channel.observePresence = NO;
            channel.linkedWithPresenceObservationChannel = NO;
        }];
    }
}


#pragma mark - Handler methods

- (void)handleLeaveRequestCompletionForWithRequest:(PNBaseRequest *)request processingResult:(id)result {
    
    PNLeaveRequest *leaveRequest = (PNLeaveRequest *)request;
    BOOL isSuccessfulResponse = ![result isKindOfClass:[PNError class]];

    [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

        return @[PNLoggerSymbols.connectionChannel.subscribe.leaveRequestCompleted, (self.name ? self.name : self),
                @(self.messagingState)];
    }];
    if (!(isSuccessfulResponse || result == nil)) {

        [PNLogger logCommunicationChannelErrorMessageFrom:self withParametersFromBlock:^NSArray *{

            return @[PNLoggerSymbols.connectionChannel.subscribe.leaveRequestFailed, (self.name ? self.name : self),
                    (result ? result : [NSNull null]), (leaveRequest.channels ? leaveRequest.channels : [NSNull null]),
                    @(self.messagingState)];
        }];
    }
    
    [self pn_dispatchAsynchronouslyBlock:^{
        
        [self.oldSubscribedChannelsSet setSet:self.subscribedChannelsSet];
        [self.subscribedChannelsSet minusSet:[self channelsWithPresenceFromList:leaveRequest.channels forSubscribe:NO]];
        
        [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{
            
            return @[PNLoggerSymbols.connectionChannel.subscribe.unsubscribedFromSetOfChannels,
                     (self.name ? self.name : self), (leaveRequest.channels ? leaveRequest.channels : [NSNull null]),
                     @(self.messagingState)];
        }];
        
        if (request.isSendingByUserRequest) {
            
            if (![self hasRequestsWithClass:[PNSubscribeRequest class]]) {
                
                [self.messagingDelegate messagingChannel:self
                                      didUnsubscribeFrom:[self channelsWithOutPresenceFromList:leaveRequest.channels]
                                               sequenced:NO];
            }
        }
        
        // Removing failed request from queue
        [self destroyRequest:request];
    }];
}

- (void)handleEventOnChannelsForRequest:(PNSubscribeRequest *)request withResponse:(PNResponse *)response {

    [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

        return @[PNLoggerSymbols.connectionChannel.subscribe.handleEvent,
                (self.name ? self.name : self), (request ? request : [NSNull null]),
                (request.channels ? request.channels : [NSNull null]), (response ? response : [NSNull null]),
                @(self.messagingState)];
    }];
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        PNResponseParser *parser = [PNResponseParser parserForResponse:response];
        id parsedData = [parser parsedData];

        [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

            return @[PNLoggerSymbols.connectionChannel.subscribe.parsedData, (self.name ? self.name : self),
                    (parser ? parser : [NSNull null]), @(self.messagingState)];
        }];
        
        if ([parsedData isKindOfClass:[PNError class]] ||
            ([parsedData isKindOfClass:[PNOperationStatus class]] && ((PNOperationStatus *)parsedData).error != nil)) {
            
            if ([parsedData isKindOfClass:[PNOperationStatus class]]) {
                
                parsedData = ((PNOperationStatus *)parsedData).error;
            }
            
            [self handleSubscribeDidFail:request withError:parsedData];
        }
        else {
            
            PNChannelEvents *events = [parser parsedData];
            
            // Retrieve event time token
            NSString *timeToken = @"0";
            if (events.timeToken) {
                
                timeToken = PNStringFromUnsignedLongLongNumber(events.timeToken);
            }
            
            
            // Update channels state update time token
            NSMutableSet *channelsForTokenUpdate = [self.subscribedChannelsSet mutableCopy];
            [channelsForTokenUpdate addObjectsFromArray:request.channels];
            
            NSString *largestTimeToken = [PNChannel largestTimetokenFromChannels:[channelsForTokenUpdate allObjects]];
            if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionTimeTokenRetrieve] &&
                ![largestTimeToken isEqualToString:@"0"]) {
                
                timeToken = largestTimeToken;
            }
            [channelsForTokenUpdate makeObjectsPerformSelector:@selector(setUpdateTimeToken:) withObject:timeToken];
            
            NSUInteger presenceModificationType = 0;
            if ([request.channelsForPresenceEnabling count] || [request.channelsForPresenceDisabling count]) {
                
                unsigned long modificationType = 0;
                if ([request.channelsForPresenceEnabling count]) {
                    
                    [PNBitwiseHelper addTo:&modificationType bit:PNMessagingChannelEnablingPresence];
                }
                if ([request.channelsForPresenceDisabling count]) {
                    
                    [PNBitwiseHelper addTo:&modificationType bit:PNMessagingChannelDisablingPresence];
                }
                presenceModificationType = modificationType;
            }
            
            // Check whether events arrived from PubNub service (messages, presence)
            if ([events.events count] > 0) {
                
                NSArray *channels = [self channelsWithOutPresenceFromList:[self.subscribedChannelsSet allObjects]];
                PNChannel *channel = nil;
                if ([channels count] == 0) {
                    
                    channels = [self.subscribedChannelsSet allObjects];
                    channel = [(PNChannelPresence *)[channels lastObject] observedChannel];
                }
                else if ([channels count] == 1) {
                    
                    channel = (PNChannel *)[channels lastObject];
                }
                
                [events.events enumerateObjectsUsingBlock:^(id event, NSUInteger eventIdx, BOOL *eventsEnumeratorStop) {
                    
                    if ([event isKindOfClass:[PNPresenceEvent class]]) {
                        
                        // Check whether channel was assigned to presence event or not (channel may not arrive with
                        // server response if client subscribed only for single channel)
                        if (((PNPresenceEvent *)event).channel == nil) {
                            
                            ((PNPresenceEvent *)event).channel = channel;
                        }
                        
                        [self.messagingDelegate messagingChannel:self didReceiveEvent:event];
                    }
                    else {
                        
                        // Check whether channel was assigned to message or not (channel may not arrive with server
                        // response if client subscribed only for single channel)
                        if (((PNMessage *)event).channel == nil) {
                            
                            ((PNMessage *)event).channel = channel;
                        }
                        
                        [self.messagingDelegate messagingChannel:self didReceiveMessage:event];
                    }
                }];
            }
            
            // Subscribe to the channels with new update time token
            NSArray *targetChannels = [self.subscribedChannelsSet count] ? [self.subscribedChannelsSet allObjects] : nil;
            targetChannels = targetChannels ? targetChannels : (request != nil ? request.channelsForSubscription : nil);
            if ([targetChannels count] || request) {
                
                [self updateSubscriptionForChannels:targetChannels withPresence:presenceModificationType forRequest:request
                                           forcibly:NO];
            }
        }
    }];
}

- (void)handleSubscribeDidFail:(PNBaseRequest *)request withError:(PNError *)error {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        BOOL shouldRestoreSubscriptionOnPreviousChannels = error.code != kPNAPIAccessForbiddenError;
        [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelRestoringSubscription, PNMessagingChannelUpdateSubscription,
         PNMessagingChannelSubscriptionTimeTokenRetrieve, PNMessagingChannelResubscribeOnTimeOut, BITS_LIST_TERMINATOR];
        
        PNSubscribeRequest *subscriptionRequest = (PNSubscribeRequest *)request;
        
        // Check whether failed to subscribe on set of channels or not
        NSMutableSet *channelsForSubscription = [NSMutableSet setWithArray:[self channelsWithOutPresenceFromList:subscriptionRequest.channelsForSubscription]];
        [channelsForSubscription minusSet:[NSSet setWithArray:[self channelsWithOutPresenceFromList:[self.subscribedChannelsSet allObjects]]]];
        NSMutableSet *existingChannelsSet = [NSMutableSet setWithArray:[self channelsWithOutPresenceFromList:[self.oldSubscribedChannelsSet allObjects]]];
        [existingChannelsSet minusSet:[NSSet setWithArray:[self channelsWithOutPresenceFromList:subscriptionRequest.channelsForSubscription]]];
        if ([channelsForSubscription count]) {

            [PNLogger logCommunicationChannelErrorMessageFrom:self withParametersFromBlock:^NSArray *{

                return @[PNLoggerSymbols.connectionChannel.subscribe.subscribeError,
                        (self.name ? self.name : self), (error ? error : [NSNull null]),
                        (subscriptionRequest.channels ? subscriptionRequest.channels : [NSNull null]), @(self.messagingState)];
            }];
            
            // Checking whether user generated request or not
            if (request.isSendingByUserRequest || error.code == kPNAPIAccessForbiddenError) {
                
                if (error.code == kPNAPIAccessForbiddenError) {
                    
                    NSSet *channelsFromFailedRequest = [self channelsWithPresenceFromList:subscriptionRequest.channels forSubscribe:NO];
                    [self.subscribedChannelsSet minusSet:channelsFromFailedRequest];
                    [self.oldSubscribedChannelsSet setSet:self.subscribedChannelsSet];
                }
                
                NSArray *channels = [self channelsWithOutPresenceFromList:subscriptionRequest.channels];
                [self.messagingDelegate messagingChannel:self didFailSubscribeOn:channels withError:error
                                               sequenced:([subscriptionRequest.channelsForPresenceEnabling count] ||
                                                          [subscriptionRequest.channelsForPresenceDisabling count])];
            }
        }
        
        // Check whether request doesn't include one of the channels at which client has been subscribed before
        // (it mean that request unsubscribed from some channels).
        if ([existingChannelsSet count]) {
            
            [self handleLeaveRequestCompletionForWithRequest:subscriptionRequest processingResult:error];
        }
        
        // Check whether tried to enable presence or not
        if ([subscriptionRequest.channelsForPresenceEnabling count]) {

            [PNLogger logCommunicationChannelErrorMessageFrom:self withParametersFromBlock:^NSArray *{

                return @[PNLoggerSymbols.connectionChannel.subscribe.presenceEnablingError,
                        (self.name ? self.name : self), (error ? error : [NSNull null]),
                        (subscriptionRequest.channelsForPresenceEnabling ? subscriptionRequest.channelsForPresenceEnabling : [NSNull null]),
                        @(self.messagingState)];
            }];
            
            // Checking whether user generated request or not
            if (request.isSendingByUserRequest) {
                
                NSArray *channels = [self channelsWithOutPresenceFromList:subscriptionRequest.channelsForPresenceEnabling];
                [self.messagingDelegate messagingChannel:self didFailPresenceEnablingOn:channels withError:error
                                               sequenced:([subscriptionRequest.channelsForPresenceDisabling count] > 0)];
            }
        }
        
        // Check whether tried to disable presence or not
        if ([subscriptionRequest.channelsForPresenceDisabling count]) {

            [PNLogger logCommunicationChannelErrorMessageFrom:self withParametersFromBlock:^NSArray *{

                return @[PNLoggerSymbols.connectionChannel.subscribe.presenceDisablingError,
                        (self.name ? self.name : self), (error ? error : [NSNull null]),
                        (subscriptionRequest.channelsForPresenceDisabling ? subscriptionRequest.channelsForPresenceDisabling : [NSNull null]),
                        @(self.messagingState)];
            }];
            
            // Checking whether user generated request or not
            if (request.isSendingByUserRequest) {
                
                NSArray *channels = [self channelsWithOutPresenceFromList:subscriptionRequest.channelsForPresenceDisabling];
                [self.messagingDelegate messagingChannel:self didFailPresenceDisablingOn:channels withError:error
                                               sequenced:NO];
            }
        }
        
        if (shouldRestoreSubscriptionOnPreviousChannels) {
            
            [self restoreSubscriptionOnPreviousChannels];
        }
    }];
}

- (void)handleTimeoutTimer:(NSTimer *)timer {
    
    PNBaseRequest *request = (PNBaseRequest *)timer.userInfo;
    NSInteger errorCode = kPNRequestExecutionFailedByTimeoutError;
    NSString *errorMessage = @"Subscription failed by timeout";
    if ([request isKindOfClass:[PNLeaveRequest class]]) {
        
        errorMessage = @"Unsubscription failed by timeout";
    }
    PNError *error = [PNError errorWithMessage:errorMessage code:errorCode];
    
    if (request) {
        
        [self pn_dispatchSynchronouslyBlock:^{
            
            if ([request isKindOfClass:[PNLeaveRequest class]]) {
                
                [self handleLeaveRequestCompletionForWithRequest:request processingResult:error];
            }
            else {
                
                [self handleSubscribeDidFail:request withError:error];
            }
        }];
    }
    
    [self destroyRequest:request];
    
    // Check whether connection available or not
    [self.delegate isPubNubServiceAvailable:YES checkCompletionBlock:^(BOOL available) {
        
        if ([self isConnected] && available) {
            
            // Asking to schedule next request
            [self scheduleNextRequest];
        }
    }];
}

- (void)handleIdleTimer:(NSTimer *)timer {
    
    if ([self canResubscribe]) {
        
        // Destroy all subscription/leave requests from queue and stored sources
        [self destroyByRequestClass:[PNLeaveRequest class]];
        [self destroyByRequestClass:[PNSubscribeRequest class]];
        
        if ([self.messagingDelegate shouldMessagingChannelRestoreSubscription:self]) {
            
            [self pn_dispatchAsynchronouslyBlock:^{

                // Ensure that client doesn't try to restore subscription on its own (after connection failure) to
                // prevent race of conditions and process this request if required to resubscribe because of channel
                // 'idle' state.
                if (![PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription]) {

                    [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelResubscribeOnTimeOut];
                    [self restoreSubscription:[self.messagingDelegate shouldMessagingChannelRestoreWithLastTimeToken:self]];
                }
            }];
        }
        else {
            
            [self unsubscribeFromChannelsByUserRequest:NO];
            
            // Notify delegate that messaging channel will reset and there is nothing for it to process
            [self.messagingDelegate messagingChannelDidReset:self];
        }
    }
    else {
        
        [self pn_dispatchAsynchronouslyBlock:^{
        
            [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelSubscriptionTimeTokenRetrieve,
             PNMessagingChannelSubscriptionWaitingForEvents, BITS_LIST_TERMINATOR];
            
            [self reconnect];
        }];
    }
}


#pragma mark - Misc methods

- (void)startChannelIdleTimer {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [self stopChannelIdleTimer];
        
        self.idleTimer = [NSTimer timerWithTimeInterval:kPNConnectionIdleTimeout target:self
                                               selector:@selector(handleIdleTimer:) userInfo:nil repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:self.idleTimer forMode:NSRunLoopCommonModes];
    }];
}

- (void)stopChannelIdleTimer {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        if ([self.idleTimer isValid]) {
            
            [self.idleTimer invalidate];
            self.idleTimer = nil;
        }
    }];
}

- (void)pauseChannelIdleTimer {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        if ([self.idleTimer isValid]) {
            
            self.idleTimerFireDate = self.idleTimer.fireDate;
            self.channelSuspensionDate = [NSDate date];
            [self.idleTimer invalidate];
            self.idleTimer = nil;
        }
        else {
            
            self.idleTimerFireDate = nil;
            self.channelSuspensionDate = nil;
        }
    }];
}

- (void)resumeChannelIdleTimer {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        if (self.idleTimerFireDate) {
            
            NSTimeInterval timeLeftBeforeSuspension = ABS([self.channelSuspensionDate timeIntervalSinceDate:self.idleTimerFireDate]);
            
            // Adding some time to let connection channel awake from suspension
            timeLeftBeforeSuspension += 10.0f;
            
            self.idleTimer = [NSTimer timerWithTimeInterval:timeLeftBeforeSuspension target:self
                                                   selector:@selector(handleIdleTimer:) userInfo:nil repeats:NO];
            [[NSRunLoop mainRunLoop] addTimer:self.idleTimer forMode:NSRunLoopCommonModes];
            
            self.idleTimerFireDate = nil;
            self.channelSuspensionDate = nil;
        }
    }];
}

- (NSSet *)channelsWithPresenceFromList:(NSArray *)channelsList forSubscribe:(BOOL)listForSubscribe {
    
    return [self channelsWithPresenceFromList:channelsList forSubscribe:listForSubscribe onlyPresence:NO];
}

- (NSSet *)channelsWithPresenceFromList:(NSArray *)channelsList forSubscribe:(BOOL)listForSubscribe
                           onlyPresence:(BOOL)fetchPresenceChannelsOnly {
    
    NSMutableSet *fullChannelsList = [NSMutableSet setWithCapacity:[channelsList count]];
    [channelsList enumerateObjectsUsingBlock:^(PNChannel *channel, NSUInteger channelIdx, BOOL *channelEnumeratorStop) {
        
        if (!fetchPresenceChannelsOnly) {
            
            [fullChannelsList addObject:channel];
        }
        
        if ((channel.linkedWithPresenceObservationChannel && !listForSubscribe) || listForSubscribe) {
            
            PNChannelPresence *presenceObserver = [channel presenceObserver];
            if (presenceObserver) {
                
                [fullChannelsList addObject:presenceObserver];
            }
        }
    }];
    
    
    return fullChannelsList;
}

- (NSArray *)channelsWithOutPresenceFromList:(NSArray *)channelsList {
    
    // Compose filtering predicate to retrieve list of channels which are not presence observing channels
    NSPredicate *filterPredicate = [NSPredicate predicateWithFormat:@"isPresenceObserver = NO"];
    
    
    return [channelsList filteredArrayUsingPredicate:filterPredicate];
}

- (NSArray *)channelsWithPresenceFromList:(NSArray *)channelsList {
    
    // Compose filtering predicate to retrieve list of channels which are not presence observing channels
    NSPredicate *filterPredicate = [NSPredicate predicateWithFormat:@"isPresenceObserver = YES"];
    
    
    return [channelsList filteredArrayUsingPredicate:filterPredicate];
}

- (NSDictionary *)stateFromClientState:(NSDictionary *)state forChannels:(NSArray *)channels {
    
    // Fetch list of names against which client should filter provided state.
    NSSet *channelNames = [NSSet setWithArray:[channels valueForKey:@"name"]];
    
    // Fetch list of names for which state has been provided.
    NSMutableSet *stateKeys = [NSMutableSet setWithArray:[state allKeys]];
    
    // Extract channels on which client wouldn't subscribed and they should be removed from provided state.
    [stateKeys intersectSet:channelNames];
    if ([stateKeys count]) {
        
        state = [state dictionaryWithValuesForKeys:[stateKeys allObjects]];
    }
    // Looks like provided state doesn't applicable to any channels on which client subscribed or will subscribe.
    else {
        
        state = nil;
    }
    
    return state;
}

- (NSDictionary *)mergedClientStateWithState:(NSDictionary *)state {
    
    return [self.messagingDelegate clientStateMergedWith:state];
}

- (NSString *)stateDescription {
    
    NSMutableString *connectionState = [NSMutableString stringWithFormat:@"\n[CHANNEL::%@ STATE DESCRIPTION", self];
    if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription]) {
        
        [connectionState appendFormat:@"\n- RESTORING SUBSCRIPTION..."];
    }
    if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelResubscribeOnTimeOut]) {
        
        [connectionState appendFormat:@"\n- RE-SUBSCRIBE ON CHANNEL CONNECTION IDLE EVENT..."];
    }
    if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionTimeTokenRetrieve]) {
        
        [connectionState appendFormat:@"\n- FETCHING INITIAL SUBSCRIPTION TIME TOKEN"];
    }
    if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelSubscriptionWaitingForEvents]) {
        
        [connectionState appendFormat:@"\n- WAITING FOR EVENTS (LONG-POLL CONNECTION)..."];
    }
    if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringConnectionTerminatedByServer]) {
        
        [connectionState appendFormat:@"\n- CONNECTION TERMINATED BY SERVER REUEST"];
    }
    
    
    return connectionState;
}


#pragma mark - Connection delegate methods

- (void)connectionDidReset:(PNConnection *)connection {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [PNBitwiseHelper clear:&_messagingState];
        
        [self startChannelIdleTimer];
    }];
    
    
    // Forward to the super class
    [super connectionDidReset:connection];
}

- (void)connection:(PNConnection *)connection didConnectToHost:(NSString *)hostName {
    
    BOOL shouldRestoreActivity = ![self isSuspended] && ![self isResuming];
    
    if (shouldRestoreActivity) {
        
        [self pn_dispatchAsynchronouslyBlock:^{
        
            [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelSubscriptionTimeTokenRetrieve,
             PNMessagingChannelSubscriptionWaitingForEvents, PNMessagingChannelRestoringConnectionTerminatedByServer,
             BITS_LIST_TERMINATOR];
            
            void(^storedRequestsDestroy)(void) = ^{
                
                [self destroyByRequestClass:[PNLeaveRequest class]];
                [self destroyByRequestClass:[PNSubscribeRequest class]];
            };
            
            // Check whether connection tried to update subscription before it was interrupted and reconnected back
            if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelUpdateSubscription]) {
                
                [PNBitwiseHelper clear:&_messagingState];
                
                // Check whether there is some channels which can be used to perform subscription update or not
                if ([self canResubscribe]) {
                    
                    storedRequestsDestroy();
                    
                    [self updateSubscriptionForChannels:[self.subscribedChannelsSet allObjects] withPresence:0
                                             forRequest:nil forcibly:NO];
                }
                // Check whether subscription request already scheduled or not
                else if (![self hasRequestsWithClass:[PNSubscribeRequest class]]) {
                    
                    // Check whether there is no 'leave' requests, which will mean that we are leaving from all channels
                    if (![self hasRequestsWithClass:[PNLeaveRequest class]]) {
                        
                        [self restoreSubscriptionOnPreviousChannels];
                    }
                }
            }
            else {
                
                [PNBitwiseHelper clear:&_messagingState];
                
                // Check whether client is able to restore subscription on channel on which it was subscribed before
                // (new time token will be used if required
                if ([self canResubscribe]) {
                    
                    storedRequestsDestroy();
                    
                    if ([self.messagingDelegate shouldMessagingChannelRestoreSubscription:self]) {
                        
                        [self restoreSubscription:[self.messagingDelegate shouldMessagingChannelRestoreWithLastTimeToken:self]];
                    }
                    else {
                        
                        [self unsubscribeFromChannelsByUserRequest:NO ];
                        
                        // Notify delegate that messaging channel will reset and there is nothing for it to process
                        [self.messagingDelegate messagingChannelDidReset:self];
                    }
                }
            }
            
            [self startChannelIdleTimer];
        }];
    }
    
    // Forward to the super class
    [super connection:connection didConnectToHost:hostName];
}

- (void)connectionDidResume:(PNConnection *)connection {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [PNBitwiseHelper clear:&_messagingState];
        
        // Check whether subscription request already scheduled or not
        if (![self hasRequestsWithClass:[PNSubscribeRequest class]]) {
            
            [self restoreSubscriptionOnPreviousChannels];
        }
        else {
            
            self.restoringSubscriptionOnResume = YES;
            
            if ([self.messagingDelegate shouldMessagingChannelRestoreWithLastTimeToken:self]) {
                
                [PNBitwiseHelper removeFrom:&_messagingState bit:PNMessagingChannelSubscriptionTimeTokenRetrieve];
                [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelSubscriptionWaitingForEvents];
            }
        }
        
        [self startChannelIdleTimer];
        
        
        // Forward to the super class
        [super connectionDidResume:connection];
        
        self.restoringSubscriptionOnResume = NO;
    }];
}

- (void)connection:(PNConnection *)connection willReconnectToHost:(NSString *)hostName {
    
    [self stopChannelIdleTimer];
    
    // Forward to the super class
    [super connection:connection willReconnectToHost:hostName];
}

- (void)connection:(PNConnection *)connection didReconnectToHost:(NSString *)hostName {
    
    [self pn_dispatchAsynchronouslyBlock:^{
        
        self.restoringSubscriptionOnResume = [PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription];
        [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelSubscriptionTimeTokenRetrieve,
         PNMessagingChannelSubscriptionWaitingForEvents, PNMessagingChannelRestoringConnectionTerminatedByServer,
         PNMessagingChannelRestoringSubscription, PNMessagingChannelResubscribeOnTimeOut, BITS_LIST_TERMINATOR];
    
        if (self.isRestoringSubscriptionOnResume) {
            [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelRestoringSubscription];
        }
        
        // Check whether client updated subscription or not
        if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelUpdateSubscription]) {
            
            [self destroyByRequestClass:[PNLeaveRequest class]];
            [self destroyByRequestClass:[PNSubscribeRequest class]];
            
            [PNBitwiseHelper removeFrom:&_messagingState bit:PNMessagingChannelUpdateSubscription];
            
            [self updateSubscriptionForChannels:[self.subscribedChannelsSet allObjects] withPresence:0 forRequest:nil
                                       forcibly:NO];
        }
        // Check whether reconnection was because of 'unsubscribe' request or not
        else if ([self hasRequestsWithClass:[PNLeaveRequest class]]) {
            
            [PNBitwiseHelper removeFrom:&_messagingState bit:PNMessagingChannelSubscriptionWaitingForEvents];
            [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelSubscriptionTimeTokenRetrieve];
        }
        // Check whether subscription request already scheduled or not
        else if (![self hasRequestsWithClass:[PNSubscribeRequest class]] && [self canResubscribe]) {
            
            [self restoreSubscriptionOnPreviousChannels];
        }
        [self startChannelIdleTimer];
        
        
        // Forward to the super class
        [super connection:connection didReconnectToHost:hostName];
        self.restoringSubscriptionOnResume = NO;
    }];
}

- (void)connection:(PNConnection *)connection willReconnectToHostAfterError:(NSString *)hostName {
    
    [self stopChannelIdleTimer];
    
    // Forward to the super class
    [super connection:connection willReconnectToHostAfterError:hostName];
}

- (void)connection:(PNConnection *)connection didReconnectToHostAfterError:(NSString *)hostName {
    
    [self pn_dispatchAsynchronouslyBlock:^{

        self.restoringSubscriptionOnResume = [PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription];
        [PNBitwiseHelper clear:&_messagingState];
    
        if (self.isRestoringSubscriptionOnResume) {
            [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelRestoringSubscription];
        }
        
        // Check whether subscription request already scheduled or not
        if (![self hasRequestsWithClass:[PNSubscribeRequest class]]) {
            
            [self restoreSubscriptionOnPreviousChannels];
        }
        [self startChannelIdleTimer];
        
        
        // Forward to the super class
        [super connection:connection didReconnectToHostAfterError:hostName];
        self.restoringSubscriptionOnResume = NO;
    }];
}

- (void)connection:(PNConnection *)connection willDisconnectFromHost:(NSString *)host withError:(PNError *)error {
    
    [self stopChannelIdleTimer];
    
    // Forward to the super class
    [super connection:connection willDisconnectFromHost:host withError:error];
}

- (void)connection:(PNConnection *)connection didDisconnectFromHost:(NSString *)hostName {
    
    [self pn_dispatchAsynchronouslyBlock:^{
        
        [PNBitwiseHelper clear:&_messagingState];
        
        [self stopChannelIdleTimer];
    }];
    
    
    // Forward to the super class
    [super connection:connection didDisconnectFromHost:hostName];
}

- (void)connection:(PNConnection *)connection didRestoreAfterServerCloseConnectionToHost:(NSString *)hostName {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelSubscriptionTimeTokenRetrieve,
         PNMessagingChannelSubscriptionWaitingForEvents, PNMessagingChannelRestoringConnectionTerminatedByServer,
         PNMessagingChannelRestoringSubscription, PNMessagingChannelResubscribeOnTimeOut, BITS_LIST_TERMINATOR];
        
        // Check whether connection tried to update subscription before it was interrupted and reconnected back
        if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelUpdateSubscription]) {
            
            [PNBitwiseHelper clear:&_messagingState];
            
            // Check whether there is some channels which can be used to perform subscription update or not
            if ([self.subscribedChannelsSet count]) {
                
                [self destroyByRequestClass:[PNLeaveRequest class]];
                [self destroyByRequestClass:[PNSubscribeRequest class]];
                
                [self updateSubscriptionForChannels:[self.subscribedChannelsSet allObjects] withPresence:0 forRequest:nil
                                           forcibly:NO];
            }
            
        }
        // Check whether subscription request already scheduled or not
        else if (![self hasRequestsWithClass:[PNSubscribeRequest class]]) {
            
            [PNBitwiseHelper clear:&_messagingState];
            
            [self restoreSubscriptionOnPreviousChannels];
        }
        else {
            
            [PNBitwiseHelper clear:&_messagingState];
        }
        
        [self startChannelIdleTimer];
        
        
        // Forward to the super class
        [super connection:connection didRestoreAfterServerCloseConnectionToHost:hostName];
    }];
}

- (void)connection:(PNConnection *)connection willDisconnectByServerRequestFromHost:(NSString *)hostName {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelRestoringSubscription,
         PNMessagingChannelUpdateSubscription, PNMessagingChannelResubscribeOnTimeOut, BITS_LIST_TERMINATOR];
        [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelRestoringConnectionTerminatedByServer];
        
        [self stopChannelIdleTimer];
        
        
        // Forward to the super class
        [super connection:connection willDisconnectByServerRequestFromHost:hostName];
    }];
    
}

- (void)connection:(PNConnection *)connection didReceiveResponse:(PNResponse *)response {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        [PNBitwiseHelper removeFrom:&_messagingState bit:PNMessagingChannelSubscriptionWaitingForEvents];
        
        [self startChannelIdleTimer];
        
        [super connection:connection didReceiveResponse:response];
    }];
}


#pragma mark - Requests queue delegate methods

- (void)requestsQueue:(PNRequestsQueue *)queue willSendRequest:(PNBaseRequest *)request {
    
    // Forward to the super class
    [super requestsQueue:queue willSendRequest:request];

    [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

        return @[PNLoggerSymbols.connectionChannel.subscribe.willStartRequestSending, (self.name ? self.name : self),
                (request ? request : [NSNull null]), @(self.messagingState)];
    }];
    
    
    // Check whether connection should be closed for resubscribe
    // or not
    if (request.shouldCloseConnection) {
        
        // Mark that we don't need to close connection after next time
        // this request will be scheduled for processing
        // (this will happen right after connection will be restored)
        request.closeConnection = NO;
        
        
        // Reconnect communication channel
        [self reconnect];
    }
}

- (void)requestsQueue:(PNRequestsQueue *)queue didSendRequest:(PNBaseRequest *)request {
    
    [self pn_dispatchAsynchronouslyBlock:^{

        [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

            return @[PNLoggerSymbols.connectionChannel.subscribe.sentRequest, (self.name ? self.name : self),
                    (request ? request : [NSNull null]), @([self isWaitingRequestCompletion:request.shortIdentifier]),
                    @(self.messagingState)];
        }];
        
        // Check whether non-initial subscription request has been sent
        if ([request isKindOfClass:[PNSubscribeRequest class]]) {
            
            [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelSubscriptionTimeTokenRetrieve,
             PNMessagingChannelSubscriptionWaitingForEvents, BITS_LIST_TERMINATOR];
            if ([((PNSubscribeRequest *)request) isInitialSubscription]) {
                
                [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelSubscriptionTimeTokenRetrieve];
            }
            else {
                
                [PNBitwiseHelper addTo:&_messagingState bit:PNMessagingChannelSubscriptionWaitingForEvents];
            }
        }
        else {
            
            [PNBitwiseHelper removeFrom:&_messagingState bit:PNMessagingChannelSubscriptionWaitingForEvents];
        }
        
        
        // Forward to the super class
        [super requestsQueue:queue didSendRequest:request];
        
        // If we are not waiting for request completion, inform delegate immediately
        if (![self isWaitingRequestCompletion:request.shortIdentifier]) {
            
            // Check whether this is 'Subscribe' or 'Leave' request or not
            // (there probably no situation when this situation will take place)
            if ([request isKindOfClass:[PNSubscribeRequest class]] ||
                [request isKindOfClass:[PNLeaveRequest class]]) {
                
                if ([request isKindOfClass:[PNSubscribeRequest class]]) {
                    
                    PNSubscribeRequest *subscribeRequest = (PNSubscribeRequest *)request;
                    
                    NSMutableSet *channelsForSubscription = [NSMutableSet setWithArray:[self channelsWithOutPresenceFromList:subscribeRequest.channelsForSubscription]];
                    [channelsForSubscription minusSet:[NSSet setWithArray:[self channelsWithOutPresenceFromList:[self.oldSubscribedChannelsSet allObjects]]]];
                    NSMutableSet *existingChannelsSet = [NSMutableSet setWithArray:[self channelsWithOutPresenceFromList:[self.oldSubscribedChannelsSet allObjects]]];
                    [existingChannelsSet minusSet:[NSSet setWithArray:[self channelsWithOutPresenceFromList:subscribeRequest.channelsForSubscription]]];
                    [self.subscribedChannelsSet unionSet:[NSSet setWithArray:subscribeRequest.channels]];
                    [self.subscribedChannelsSet minusSet:[NSSet setWithArray:subscribeRequest.channelsForPresenceDisabling]];
                    if ([existingChannelsSet count]) {
                        
                        [self.subscribedChannelsSet minusSet:existingChannelsSet];
                    }
                    [self.oldSubscribedChannelsSet setSet:self.subscribedChannelsSet];
                    
                    // Check whether failed to subscribe on set of channels or not
                    if ([channelsForSubscription count] || [PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription]) {
                        
                        BOOL isInSequence = ([existingChannelsSet count] || [subscribeRequest.channelsForPresenceEnabling count] ||
                                             [subscribeRequest.channelsForPresenceDisabling count]);
                        
                        if ([PNBitwiseHelper is:self.messagingState containsBit:PNMessagingChannelRestoringSubscription]) {
                            
                            if (![channelsForSubscription count]) {
                                
                                channelsForSubscription = [NSMutableSet setWithArray:[self channelsWithOutPresenceFromList:[self.oldSubscribedChannelsSet allObjects]]];
                            }

                            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                                return @[PNLoggerSymbols.connectionChannel.subscribe.subscriptionRestored, (self.name ? self.name : self),
                                        (channelsForSubscription ? channelsForSubscription : [NSNull null]), @(self.messagingState)];
                            }];
                            
                            [PNBitwiseHelper removeFrom:&_messagingState bit:PNMessagingChannelRestoringSubscription];
                            
                            [self.messagingDelegate messagingChannel:self
                                            didRestoreSubscriptionOn:[channelsForSubscription allObjects]
                                                           sequenced:isInSequence];
                        }
                        else {

                            [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                                return @[PNLoggerSymbols.connectionChannel.subscribe.subscriptionCompleted, (self.name ? self.name : self),
                                        (channelsForSubscription ? channelsForSubscription : [NSNull null]), @(self.messagingState)];
                            }];
                            
                            [self.messagingDelegate messagingChannel:self
                                                      didSubscribeOn:[channelsForSubscription allObjects]
                                                           sequenced:isInSequence
                                                     withClientState:((PNSubscribeRequest *)request).state];
                        }
                    }
                    
                    // Check whether request doesn't include one of the channels at which client has been subscribed before
                    // (it mean that request unsubscribed from some channels).
                    if ([existingChannelsSet count]) {
                        
                        [self.subscribedChannelsSet minusSet:existingChannelsSet];
                        [self.oldSubscribedChannelsSet setSet:self.subscribedChannelsSet];

                        [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                            return @[PNLoggerSymbols.connectionChannel.subscribe.unsubscribedFromSetOfChannels, (self.name ? self.name : self),
                                    (existingChannelsSet ? existingChannelsSet : [NSNull null]), @(self.messagingState)];
                        }];
                        
                        [self.messagingDelegate messagingChannel:self didUnsubscribeFrom:[existingChannelsSet allObjects]
                                                       sequenced:([subscribeRequest.channelsForPresenceEnabling count] ||
                                                                  [subscribeRequest.channelsForPresenceDisabling count])];
                    }
                    
                    // Check whether request enabled presence on some channels or not
                    if ([subscribeRequest.channelsForPresenceEnabling count]) {
                        
                        NSArray *presenceEnabledChannels = [subscribeRequest.channelsForPresenceEnabling valueForKey:@"observedChannel"];
                        subscribeRequest.channelsForPresenceEnabling = nil;

                        [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                            return @[PNLoggerSymbols.connectionChannel.subscribe.enabledPresence, (self.name ? self.name : self),
                                    (presenceEnabledChannels ? presenceEnabledChannels : [NSNull null]), @(self.messagingState)];
                        }];
                        
                        [self.messagingDelegate messagingChannel:self didEnablePresenceObservationOn:presenceEnabledChannels
                                                       sequenced:([subscribeRequest.channelsForPresenceDisabling count] > 0)];
                    }
                    
                    // Check whether request disabled presence on some channels or not
                    if ([subscribeRequest.channelsForPresenceDisabling count]) {
                        
                        NSArray *presenceDisabledChannels = [subscribeRequest.channelsForPresenceDisabling valueForKey:@"observedChannel"];
                        subscribeRequest.channelsForPresenceDisabling = nil;

                        [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                            return @[PNLoggerSymbols.connectionChannel.subscribe.disabledPresence, (self.name ? self.name : self),
                                    (presenceDisabledChannels ? presenceDisabledChannels : [NSNull null]), @(self.messagingState)];
                        }];
                        
                        // Remove 'presence enabled' state from list of specified channels
                        [self disablePresenceObservationForChannels:presenceDisabledChannels sendRequest:NO];
                        
                        [self.messagingDelegate messagingChannel:self didDisablePresenceObservationOn:presenceDisabledChannels
                                                       sequenced:NO];
                    }
                }
                else {
                    
                    PNLeaveRequest *leaveRequest = (PNLeaveRequest *)request;
                    NSArray *channels = [self channelsWithOutPresenceFromList:leaveRequest.channels];

                    [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

                        return @[PNLoggerSymbols.connectionChannel.subscribe.leaved, (self.name ? self.name : self),
                                (channels ? channels : [NSNull null]), @(self.messagingState)];
                    }];
                    
                    NSSet *leavedChannels = [self channelsWithPresenceFromList:channels forSubscribe:NO];
                    [self.subscribedChannelsSet minusSet:leavedChannels];
                    [self.oldSubscribedChannelsSet setSet:self.subscribedChannelsSet];
                    
                    if ([leaveRequest isSendingByUserRequest]) {
                        
                        [self.messagingDelegate messagingChannel:self didUnsubscribeFrom:channels sequenced:NO];
                    }
                }
            }
            // In case if this is any other request for whichwe don't expect completion, we should clean it up from stored
            // requests list.
            else {
                
                [self removeStoredRequest:request];
            }
        }
        
        [self scheduleNextRequest];
    }];
}

- (void)requestsQueue:(PNRequestsQueue *)queue didFailRequestSend:(PNBaseRequest *)request withError:(PNError *)error {
    
    [self pn_dispatchAsynchronouslyBlock:^{
    
        // Check whether failed to send subscription request or not
        if ([request isKindOfClass:[PNSubscribeRequest class]]) {
            
            [PNBitwiseHelper removeFrom:&_messagingState bit:PNMessagingChannelSubscriptionWaitingForEvents];
        }
        
        // Forward to the super class
        [super requestsQueue:queue didFailRequestSend:request withError:error];
        
        
        // Check whether request can be rescheduled or not
        if (![request canRetry]) {

            [PNLogger logCommunicationChannelErrorMessageFrom:self withParametersFromBlock:^NSArray *{

                return @[PNLoggerSymbols.connectionChannel.subscribe.requestSendingFailed, (self.name ? self.name : self),
                        (request ? request : [NSNull null]), (error ? error : [NSNull null]), @(self.messagingState)];
            }];
            
            // Removing failed request from queue
            [self destroyRequest:request];
            
            [self handleRequestProcessingDidFail:request withError:error];
        }
        
        
        // Check whether connection available or not
        [self.delegate isPubNubServiceAvailable:NO checkCompletionBlock:^(BOOL available) {
            
            if ([self isConnected] && available) {
                
                [self scheduleNextRequest];
            }
        }];
    }];
}

- (void)requestsQueue:(PNRequestsQueue *)queue didCancelRequest:(PNBaseRequest *)request {

    [PNLogger logCommunicationChannelInfoMessageFrom:self withParametersFromBlock:^NSArray *{

        return @[PNLoggerSymbols.connectionChannel.subscribe.requestSendingCanceled, (self.name ? self.name : self),
                (request ? request : [NSNull null]), @(self.messagingState)];
    }];

    [self.delegate isPubNubServiceAvailable:YES checkCompletionBlock:^(BOOL available) {
        
        if ([request isKindOfClass:[PNSubscribeRequest class]]) {
            
            [self pn_dispatchAsynchronouslyBlock:^{
                
                [PNBitwiseHelper removeFrom:&_messagingState bits:PNMessagingChannelSubscriptionTimeTokenRetrieve,
                 PNMessagingChannelSubscriptionWaitingForEvents, BITS_LIST_TERMINATOR];
            }];
        }
        else if ([request isKindOfClass:[PNLeaveRequest class]]) {
            
            if (available) {
                
                request.processing = YES;
            }
        }
        
        // Forward to the super class
        [super requestsQueue:queue didCancelRequest:request];
    }];
}

- (void)shouldRequestsQueue:(PNRequestsQueue *)queue removeCompletedRequest:(PNBaseRequest *)request
            checkCompletion:(void(^)(BOOL))checkCompletionBlock {

    [self pn_dispatchAsynchronouslyBlock:^{

        BOOL shouldRemove = YES;

        if ([self isWaitingRequestCompletion:request.shortIdentifier] || [request isKindOfClass:[PNLeaveRequest class]]) {

            shouldRemove = NO;
        }

        checkCompletionBlock(shouldRemove);
    }];
}


#pragma mark Memory management

- (void)dealloc {
    
    [self stopChannelIdleTimer];
}

#pragma mark -


@end
