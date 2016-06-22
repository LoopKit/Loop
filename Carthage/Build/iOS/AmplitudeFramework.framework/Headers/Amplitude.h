//
// Amplitude.h

#import <Foundation/Foundation.h>
#import "AMPIdentify.h"
#import "AMPRevenue.h"


/*!
 @class
 Amplitude API.

 @abstract
 The interface for integrating Amplitude with your application.

 @discussion
 Use the Amplitude class to track events in your application.

 <pre>
 // In every file that uses analytics, import Amplitude.h at the top
 #import "Amplitude.h"

 // First, be sure to initialize the API in your didFinishLaunchingWithOptions delegate
 [[Amplitude instance] initializeApiKey:@"YOUR_API_KEY_HERE"];

 // Track an event anywhere in the app
 [[Amplitude instance] logEvent:@"EVENT_IDENTIFIER_HERE"];

 // You can attach additional data to any event by passing a NSDictionary object
 NSMutableDictionary *eventProperties = [NSMutableDictionary dictionary];
 [eventProperties setValue:@"VALUE_GOES_HERE" forKey:@"KEY_GOES_HERE"];
 [[Amplitude instance] logEvent:@"Compute Hash" withEventProperties:eventProperties];
 </pre>

 For more details on the setup and usage, be sure to check out the docs here:
 https://github.com/amplitude/Amplitude-iOS#setup
 */
@interface Amplitude : NSObject

#pragma mark - Properties
@property (nonatomic, strong, readonly) NSString *apiKey;
@property (nonatomic, strong, readonly) NSString *userId;
@property (nonatomic, strong, readonly) NSString *deviceId;
@property (nonatomic, strong, readonly) NSString *instanceName;
@property (nonatomic ,strong, readonly) NSString *propertyListPath;
@property (nonatomic, assign) BOOL optOut;

/*!
 The maximum number of events that can be stored locally before forcing an upload.
 The default is 30 events.
 */
@property (nonatomic, assign) int eventUploadThreshold;

/*!
 The maximum number of events that can be uploaded in a single request.
 The default is 100 events.
 */
@property (nonatomic, assign) int eventUploadMaxBatchSize;

/*!
 The maximum number of events that can be stored lcoally.
 The default is 1000 events.
 */
@property (nonatomic, assign) int eventMaxCount;

/*!
 The amount of time after an event is logged that events will be batched before being uploaded to the server.
 The default is 30 seconds.
 */
@property (nonatomic, assign) int eventUploadPeriodSeconds;

/*!
 When a user closes and reopens the app within minTimeBetweenSessionsMillis milliseconds, the reopen is considered part of the same session and the session continues. Otherwise, a new session is created.
 The default is 15 minutes.
 */
@property (nonatomic, assign) long minTimeBetweenSessionsMillis;

/*!
 Whether to track start and end of session events
 */
@property (nonatomic, assign) BOOL trackingSessionEvents;


#pragma mark - Methods

+ (Amplitude *)instance;

+ (Amplitude *)instanceWithName:(NSString*) instanceName;

/*!
 @method

 @abstract
 Initializes the Amplitude static class with your Amplitude api key.

 @param apiKey                 Your Amplitude key obtained from your dashboard at https://amplitude.com/settings
 @param userId                 If your app has its own login system that you want to track users with, you can set the userId.

 @discussion
 We recommend you first initialize your class within your "didFinishLaunchingWithOptions" method inside your app delegate.

 - (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
 {
 // Initialize your shared Analytics instance.
 [[Amplitude instance] initializeApiKey:@"YOUR_API_KEY_HERE"];

 // YOUR OTHER APP LAUNCH CODE HERE....

 return YES;
 }
 */
- (void)initializeApiKey:(NSString*) apiKey;
- (void)initializeApiKey:(NSString*) apiKey userId:(NSString*) userId;


/*!
 @method

 @abstract
 Tracks an event

 @param eventType                The name of the event you wish to track.
 @param eventProperties          You can attach additional data to any event by passing a NSDictionary object with property: value pairs.
 @param groups                   You can specify event-level groups for this user by passing a NSDictionary object with groupType: groupName pairs. Note the keys need to be strings, and the values can either be strings or an array of strings.
 @param outOfSession             If YES, will track the event as out of session. Useful for push notification events.

 @discussion
 Events are saved locally. Uploads are batched to occur every 30 events and every 30 seconds, as well as on app close.
 After calling logEvent in your app, you will immediately see data appear on the Amplitude Website.

 It's important to think about what types of events you care about as a developer. You should aim to track
 between 50 and 200 types of events within your app. Common event types are different screens within the app,
 actions the user initiates (such as pressing a button), and events you want the user to complete
 (such as filling out a form, completing a level, or making a payment).
 */
- (void)logEvent:(NSString*) eventType;
- (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties;
- (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties outOfSession:(BOOL) outOfSession;
- (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties withGroups:(NSDictionary*) groups;
- (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties withGroups:(NSDictionary*) groups outOfSession:(BOOL) outOfSession;

/*!
 @method

 @abstract
 Tracks revenue.

 @param amount                   The amount of revenue to track, e.g. "3.99".

 @discussion
 To track revenue from a user, call [[Amplitude instance] logRevenue:[NSNumber numberWithDouble:3.99]] each time the user generates revenue.
 logRevenue: takes in an NSNumber with the dollar amount of the sale as the only argument. This allows us to automatically display
 data relevant to revenue on the Amplitude website, including average revenue per daily active user (ARPDAU), 7, 30, and 90 day revenue,
 lifetime value (LTV) estimates, and revenue by advertising campaign cohort and daily/weekly/monthly cohorts.

 For validating revenue, use [[Amplitude instance] logRevenue:@"com.company.app.productId" quantity:1 price:[NSNumber numberWithDouble:3.99] receipt:transactionReceipt]
 */
- (void)logRevenue:(NSNumber*) amount;
- (void)logRevenue:(NSString*) productIdentifier quantity:(NSInteger) quantity price:(NSNumber*) price;
- (void)logRevenue:(NSString*) productIdentifier quantity:(NSInteger) quantity price:(NSNumber*) price receipt:(NSData*) receipt;

/*!
 @method
 
 @abstract
 Tracks revenue - API v2.
 
 @param AMPRevenue object       revenue object contains all revenue information
 
 @discussion
 To track revenue from a user, create an AMPRevenue object each time the user generates revenue, and set the revenue properties (productIdentifier, price, quantity).
 logRevenuev2: takes in an AMPRevenue object. This allows us to automatically display data relevant to revenue on the Amplitude website, including average
 revenue per daily active user (ARPDAU), 7, 30, and 90 day revenue, lifetime value (LTV) estimates, and revenue by advertising campaign cohort and
 daily/weekly/monthly cohorts.
 
 For validating revenue, make sure the receipt data is set on the AMPRevenue object.
 */
- (void)logRevenueV2:(AMPRevenue*) revenue;

/*!
 @method

 @abstract
 Update user properties using operations provided via Identify API.

 @param identify                   An AMPIdentify object with the intended user property operations

 @discussion
 To update user properties, first create an AMPIdentify object. For example if you wanted to set a user's gender, and then increment their
 karma count by 1, you would do:
 AMPIdentify *identify = [[[AMPIdentify identify] set:@"gender" value:@"male"] add:@"karma" value:[NSNumber numberWithInt:1]];
 Then you would pass this AMPIdentify object to the identify function to send to the server: [[Amplitude instance] identify:identify];
 The Identify API supports add, set, setOnce, unset operations. See the AMPIdentify.h header file for the method signatures.
 */

- (void)identify:(AMPIdentify *)identify;

/*!
 @method

 @abstract
 Manually forces the class to immediately upload all queued events.

 @discussion
 Events are saved locally. Uploads are batched to occur every 30 events and every 30 seconds, as well as on app close.
 Use this method to force the class to immediately upload all queued events.
 */
- (void)uploadEvents;

/*!
 @method

 @abstract
 Adds properties that are tracked on the user level.

 @param userProperties          An NSDictionary containing any additional data to be tracked.
 @param replace                 This is deprecated. In earlier versions of this SDK, this replaced the in-memory userProperties dictionary with the input, but now userProperties are no longer stored in memory.

 @discussion
 Property keys must be <code>NSString</code> objects and values must be serializable.
 */

- (void)setUserProperties:(NSDictionary*) userProperties;
- (void)setUserProperties:(NSDictionary*) userProperties replace:(BOOL) replace;

/*!
 @method

 @abstract
 Clears all properties that are tracked on the user level.
 */

- (void)clearUserProperties;

/*!
 @method

 @abstract
 Adds a user to a group or groups. You need to specify a groupType and groupName(s). For example you can group people by their organization. In that case groupType is "orgId", and groupName would be the actual ID(s). groupName can be a string or an array of strings to indicate a user in multiple groups. You can also call setGroup multiple times with different groupTypes to track multiple types of groups (up to 5 per app). Note: this will also set groupType: groupName as a user property.
 @param groupType               You need to specify a group type (for example "orgId").
 @param groupName               The value for the group name, can be a string or an array of strings, (for example for groupType orgId, the groupName would be the actual id number, like 15).
 */

- (void)setGroup:(NSString*) groupType groupName:(NSObject*) groupName;

/*!
 @method

 @abstract
 Sets the userId.

 @param userId                  If your app has its own login system that you want to track users with, you can set the userId.

 @discussion
 If your app has its own login system that you want to track users with, you can set the userId.
 */
- (void)setUserId:(NSString*) userId;

/*!
 @method

 @abstract
 Sets the deviceId.

 @param deviceId                  If your app has its own system for tracking devices, you can set the deviceId.

 @discussion
 If your app has its own system for tracking devices, you can set the deviceId.
 */
- (void)setDeviceId:(NSString*) deviceId;

/*!
 @method

 @abstract
 Enables tracking opt out.

 @param enabled                  Whether tracking opt out should be enabled or disabled.

 @discussion
 If the user wants to opt out of all tracking, use this method to enable opt out for them. Once opt out is enabled, no events will be saved locally or sent to the server. Calling this method again with enabled set to NO will turn tracking back on for the user.
 */
- (void)setOptOut:(BOOL)enabled;

/*!
 @method

 @abstract
 Disables sending logged events to Amplitude servers.

 @param offline                  Whether logged events should be sent to Amplitude servers.

 @discussion
 If you want to stop logged events from being sent to Amplitude severs, use this method to set the client to offline. Once offline is enabled, logged events will not be sent to the server until offline is disabled. Calling this method again with offline set to NO will allow events to be sent to server and the client will attempt to send events that have been queued while offline.
 */
- (void)setOffline:(BOOL)offline;

/*!
 @method

 @abstract
 Enables location tracking.

 @discussion
 If the user has granted your app location permissions, the SDK will also grab the location of the user.
 Amplitude will never prompt the user for location permissions itself, this must be done by your app.
 */
- (void)enableLocationListening;

/*!
 @method

 @abstract
 Disables location tracking.

 @discussion
 If you want location tracking disabled on startup of the app, call disableLocationListening before you call initializeApiKey.
 */
- (void)disableLocationListening;

/*!
 @method

 @abstract
 Forces the SDK to update with the user's last known location if possible.

 @discussion
 If you want to manually force the SDK to update with the user's last known location, call updateLocation.
 */
- (void)updateLocation;

/*!
 @method

 @abstract
 Uses advertisingIdentifier instead of identifierForVendor as the device ID

 @discussion
 Apple prohibits the use of advertisingIdentifier if your app does not have advertising. Useful for tying together data from advertising campaigns to anlaytics data. Must be called before initializeApiKey: is called to function.
 */
- (void)useAdvertisingIdForDeviceId;

/*!
 @method

 @abstract
 Prints the number of events in the queue.

 @discussion
 Debugging method to find out how many events are being stored locally on the device.
 */
- (void)printEventsCount;

/*!
 @method

 @abstract
 Returns deviceId

 @discussion
 The deviceId is an identifier used by Amplitude to determine unique users when no userId has been set.
 */
- (NSString*)getDeviceId;

/*!
 @method

 @abstract
 Returns the current sessionId

 @discussion
 The sessionId is an identifier used by Amplitude to group together events performed during the same session.
 */
- (long long)getSessionId;



#pragma mark - Deprecated methods

- (void)initializeApiKey:(NSString*) apiKey userId:(NSString*) userId startSession:(BOOL)startSession __attribute((deprecated()));

- (void)startSession __attribute((deprecated()));

+ (void)initializeApiKey:(NSString*) apiKey __attribute((deprecated()));

+ (void)initializeApiKey:(NSString*) apiKey userId:(NSString*) userId __attribute((deprecated()));

+ (void)logEvent:(NSString*) eventType __attribute((deprecated()));

+ (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties __attribute((deprecated()));

+ (void)logRevenue:(NSNumber*) amount __attribute((deprecated()));

+ (void)logRevenue:(NSString*) productIdentifier quantity:(NSInteger) quantity price:(NSNumber*) price __attribute((deprecated())) __attribute((deprecated()));

+ (void)logRevenue:(NSString*) productIdentifier quantity:(NSInteger) quantity price:(NSNumber*) price receipt:(NSData*) receipt __attribute((deprecated()));

+ (void)uploadEvents __attribute((deprecated()));

+ (void)setUserProperties:(NSDictionary*) userProperties __attribute((deprecated()));

+ (void)setUserId:(NSString*) userId __attribute((deprecated()));

+ (void)enableLocationListening __attribute((deprecated()));

+ (void)disableLocationListening __attribute((deprecated()));

+ (void)useAdvertisingIdForDeviceId __attribute((deprecated()));

+ (void)printEventsCount __attribute((deprecated()));

+ (NSString*)getDeviceId __attribute((deprecated()));
@end

#pragma mark - constants

extern NSString *const kAMPSessionStartEvent;
extern NSString *const kAMPSessionEndEvent;
extern NSString *const kAMPRevenueEvent;
