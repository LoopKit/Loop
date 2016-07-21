// Generated by Apple Swift version 2.2 (swiftlang-703.0.18.8 clang-703.0.31)
#pragma clang diagnostic push

#if defined(__has_include) && __has_include(<swift/objc-prologue.h>)
# include <swift/objc-prologue.h>
#endif

#pragma clang diagnostic ignored "-Wauto-import"
#include <objc/NSObject.h>
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#if !defined(SWIFT_TYPEDEFS)
# define SWIFT_TYPEDEFS 1
# if defined(__has_include) && __has_include(<uchar.h>)
#  include <uchar.h>
# elif !defined(__cplusplus) || __cplusplus < 201103L
typedef uint_least16_t char16_t;
typedef uint_least32_t char32_t;
# endif
typedef float swift_float2  __attribute__((__ext_vector_type__(2)));
typedef float swift_float3  __attribute__((__ext_vector_type__(3)));
typedef float swift_float4  __attribute__((__ext_vector_type__(4)));
typedef double swift_double2  __attribute__((__ext_vector_type__(2)));
typedef double swift_double3  __attribute__((__ext_vector_type__(3)));
typedef double swift_double4  __attribute__((__ext_vector_type__(4)));
typedef int swift_int2  __attribute__((__ext_vector_type__(2)));
typedef int swift_int3  __attribute__((__ext_vector_type__(3)));
typedef int swift_int4  __attribute__((__ext_vector_type__(4)));
#endif

#if !defined(SWIFT_PASTE)
# define SWIFT_PASTE_HELPER(x, y) x##y
# define SWIFT_PASTE(x, y) SWIFT_PASTE_HELPER(x, y)
#endif
#if !defined(SWIFT_METATYPE)
# define SWIFT_METATYPE(X) Class
#endif

#if defined(__has_attribute) && __has_attribute(objc_runtime_name)
# define SWIFT_RUNTIME_NAME(X) __attribute__((objc_runtime_name(X)))
#else
# define SWIFT_RUNTIME_NAME(X)
#endif
#if defined(__has_attribute) && __has_attribute(swift_name)
# define SWIFT_COMPILE_NAME(X) __attribute__((swift_name(X)))
#else
# define SWIFT_COMPILE_NAME(X)
#endif
#if !defined(SWIFT_CLASS_EXTRA)
# define SWIFT_CLASS_EXTRA
#endif
#if !defined(SWIFT_PROTOCOL_EXTRA)
# define SWIFT_PROTOCOL_EXTRA
#endif
#if !defined(SWIFT_ENUM_EXTRA)
# define SWIFT_ENUM_EXTRA
#endif
#if !defined(SWIFT_CLASS)
# if defined(__has_attribute) && __has_attribute(objc_subclassing_restricted)
#  define SWIFT_CLASS(SWIFT_NAME) SWIFT_RUNTIME_NAME(SWIFT_NAME) __attribute__((objc_subclassing_restricted)) SWIFT_CLASS_EXTRA
#  define SWIFT_CLASS_NAMED(SWIFT_NAME) __attribute__((objc_subclassing_restricted)) SWIFT_COMPILE_NAME(SWIFT_NAME) SWIFT_CLASS_EXTRA
# else
#  define SWIFT_CLASS(SWIFT_NAME) SWIFT_RUNTIME_NAME(SWIFT_NAME) SWIFT_CLASS_EXTRA
#  define SWIFT_CLASS_NAMED(SWIFT_NAME) SWIFT_COMPILE_NAME(SWIFT_NAME) SWIFT_CLASS_EXTRA
# endif
#endif

#if !defined(SWIFT_PROTOCOL)
# define SWIFT_PROTOCOL(SWIFT_NAME) SWIFT_RUNTIME_NAME(SWIFT_NAME) SWIFT_PROTOCOL_EXTRA
# define SWIFT_PROTOCOL_NAMED(SWIFT_NAME) SWIFT_COMPILE_NAME(SWIFT_NAME) SWIFT_PROTOCOL_EXTRA
#endif

#if !defined(SWIFT_EXTENSION)
# define SWIFT_EXTENSION(M) SWIFT_PASTE(M##_Swift_, __LINE__)
#endif

#if !defined(OBJC_DESIGNATED_INITIALIZER)
# if defined(__has_attribute) && __has_attribute(objc_designated_initializer)
#  define OBJC_DESIGNATED_INITIALIZER __attribute__((objc_designated_initializer))
# else
#  define OBJC_DESIGNATED_INITIALIZER
# endif
#endif
#if !defined(SWIFT_ENUM)
# define SWIFT_ENUM(_type, _name) enum _name : _type _name; enum SWIFT_ENUM_EXTRA _name : _type
# if defined(__has_feature) && __has_feature(generalized_swift_name)
#  define SWIFT_ENUM_NAMED(_type, _name, SWIFT_NAME) enum _name : _type _name SWIFT_COMPILE_NAME(SWIFT_NAME); enum SWIFT_COMPILE_NAME(SWIFT_NAME) SWIFT_ENUM_EXTRA _name : _type
# else
#  define SWIFT_ENUM_NAMED(_type, _name, SWIFT_NAME) SWIFT_ENUM(_type, _name)
# endif
#endif
#if defined(__has_feature) && __has_feature(modules)
@import UIKit;
@import CoreGraphics;
@import HealthKit;
@import Foundation;
#endif

#pragma clang diagnostic ignored "-Wproperty-attribute-mismatch"
#pragma clang diagnostic ignored "-Wduplicate-method-arg"
@class NSCoder;
@class UIBarButtonItem;
@class NSTimeZone;
@class UITableView;
@class NSIndexPath;
@class UITableViewCell;

SWIFT_CLASS("_TtC7LoopKit37DailyValueScheduleTableViewController")
@interface DailyValueScheduleTableViewController : UITableViewController
- (nonnull instancetype)init OBJC_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder * _Nonnull)aDecoder OBJC_DESIGNATED_INITIALIZER;
- (void)viewDidLoad;
- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
- (void)viewWillDisappear:(BOOL)animated;
- (UIBarButtonItem * _Nonnull)insertButtonItem;
@property (nonatomic, strong) NSTimeZone * _Nonnull timeZone;
@property (nonatomic, copy) NSString * _Nonnull unitDisplayString;
- (NSInteger)numberOfSectionsInTableView:(UITableView * _Nonnull)tableView;
- (NSInteger)tableView:(UITableView * _Nonnull)tableView numberOfRowsInSection:(NSInteger)section;
- (BOOL)tableView:(UITableView * _Nonnull)tableView canEditRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (BOOL)tableView:(UITableView * _Nonnull)tableView canMoveRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (UITableViewCell * _Nonnull)tableView:(UITableView * _Nonnull)tableView cellForRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (void)tableView:(UITableView * _Nonnull)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (CGFloat)tableView:(UITableView * _Nonnull)tableView heightForRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (BOOL)tableView:(UITableView * _Nonnull)tableView shouldHighlightRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (NSIndexPath * _Nullable)tableView:(UITableView * _Nonnull)tableView willSelectRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (void)tableView:(UITableView * _Nonnull)tableView didDeselectRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (void)tableView:(UITableView * _Nonnull)tableView didSelectRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (NSIndexPath * _Nonnull)tableView:(UITableView * _Nonnull)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath * _Nonnull)sourceIndexPath toProposedIndexPath:(NSIndexPath * _Nonnull)proposedDestinationIndexPath;
@end


SWIFT_CLASS("_TtC7LoopKit38SingleValueScheduleTableViewController")
@interface SingleValueScheduleTableViewController : DailyValueScheduleTableViewController
- (void)viewDidLoad;
- (NSInteger)tableView:(UITableView * _Nonnull)tableView numberOfRowsInSection:(NSInteger)section;
- (UITableViewCell * _Nonnull)tableView:(UITableView * _Nonnull)tableView cellForRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (void)tableView:(UITableView * _Nonnull)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (void)tableView:(UITableView * _Nonnull)tableView moveRowAtIndexPath:(NSIndexPath * _Nonnull)sourceIndexPath toIndexPath:(NSIndexPath * _Nonnull)destinationIndexPath;
- (NSIndexPath * _Nonnull)tableView:(UITableView * _Nonnull)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath * _Nonnull)sourceIndexPath toProposedIndexPath:(NSIndexPath * _Nonnull)proposedDestinationIndexPath;
- (nonnull instancetype)init OBJC_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder * _Nonnull)aDecoder OBJC_DESIGNATED_INITIALIZER;
@end

@class HKUnit;

SWIFT_CLASS("_TtC7LoopKit40DailyQuantityScheduleTableViewController")
@interface DailyQuantityScheduleTableViewController : SingleValueScheduleTableViewController
@property (nonatomic, strong) HKUnit * _Nonnull unit;
- (nonnull instancetype)init OBJC_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder * _Nonnull)aDecoder OBJC_DESIGNATED_INITIALIZER;
@end



SWIFT_CLASS("_TtC7LoopKit39GlucoseRangeScheduleTableViewController")
@interface GlucoseRangeScheduleTableViewController : DailyValueScheduleTableViewController
@property (nonatomic, strong) HKUnit * _Nonnull unit;
- (void)viewDidLoad;
- (NSInteger)numberOfSectionsInTableView:(UITableView * _Nonnull)tableView;
- (NSInteger)tableView:(UITableView * _Nonnull)tableView numberOfRowsInSection:(NSInteger)section;
- (UITableViewCell * _Nonnull)tableView:(UITableView * _Nonnull)tableView cellForRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (void)tableView:(UITableView * _Nonnull)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (void)tableView:(UITableView * _Nonnull)tableView moveRowAtIndexPath:(NSIndexPath * _Nonnull)sourceIndexPath toIndexPath:(NSIndexPath * _Nonnull)destinationIndexPath;
- (BOOL)tableView:(UITableView * _Nonnull)tableView canEditRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (BOOL)tableView:(UITableView * _Nonnull)tableView canMoveRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (NSString * _Nullable)tableView:(UITableView * _Nonnull)tableView titleForHeaderInSection:(NSInteger)section;
- (nonnull instancetype)init OBJC_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder * _Nonnull)aDecoder OBJC_DESIGNATED_INITIALIZER;
@end


@interface GlucoseRangeScheduleTableViewController (SWIFT_EXTENSION(LoopKit))
@end


@interface HKQuantity (SWIFT_EXTENSION(LoopKit))
@end


@interface HKUnit (SWIFT_EXTENSION(LoopKit))
+ (HKUnit * _Nonnull)milligramsPerDeciliterUnit;
+ (HKUnit * _Nonnull)millimolesPerLiterUnit;

/// A formatting helper for determining the preferred decimal style for a given unit
@property (nonatomic, readonly) NSInteger preferredMinimumFractionDigits;

/// A presentation helper for the localized unit string
@property (nonatomic, readonly, copy) NSString * _Nonnull glucoseUnitDisplayString;
@end


@interface NSDate (SWIFT_EXTENSION(LoopKit))
@end


@interface NSDate (SWIFT_EXTENSION(LoopKit))
- (NSDate * _Nonnull)dateFlooredToTimeInterval:(NSTimeInterval)interval;
- (NSDate * _Nonnull)dateCeiledToTimeInterval:(NSTimeInterval)interval;
@end


@class UITextField;
@class NSBundle;

SWIFT_CLASS("_TtC7LoopKit28TextFieldTableViewController")
@interface TextFieldTableViewController : UITableViewController <UITextFieldDelegate>
@property (nonatomic, strong) NSIndexPath * _Nullable indexPath;
@property (nonatomic, copy) NSString * _Nullable placeholder;
@property (nonatomic, copy) NSString * _Nullable value;
@property (nonatomic) UIKeyboardType keyboardType;
- (nonnull instancetype)init;
- (void)viewDidLoad;
- (void)viewDidAppear:(BOOL)animated;
- (NSInteger)tableView:(UITableView * _Nonnull)tableView numberOfRowsInSection:(NSInteger)section;
- (UITableViewCell * _Nonnull)tableView:(UITableView * _Nonnull)tableView cellForRowAtIndexPath:(NSIndexPath * _Nonnull)indexPath;
- (BOOL)textFieldShouldEndEditing:(UITextField * _Nonnull)textField;
- (BOOL)textFieldShouldReturn:(UITextField * _Nonnull)textField;
- (nonnull instancetype)initWithStyle:(UITableViewStyle)style OBJC_DESIGNATED_INITIALIZER;
- (nonnull instancetype)initWithNibName:(NSString * _Nullable)nibNameOrNil bundle:(NSBundle * _Nullable)nibBundleOrNil OBJC_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder * _Nonnull)aDecoder OBJC_DESIGNATED_INITIALIZER;
@end


@interface UITableViewCell (SWIFT_EXTENSION(LoopKit))
@end


@interface UIViewController (SWIFT_EXTENSION(LoopKit))

/// Convenience method to present an alert controller on the active view controller
///
/// \param title The title of the alert
///
/// \param message The message of the alert
///
/// \param animated Whether to animate the alert
///
/// \param completion An optional closure to execute after the presentation finishes
- (void)presentAlertControllerWithTitle:(NSString * _Nullable)title message:(NSString * _Nonnull)message animated:(BOOL)animated completion:(void (^ _Nullable)(void))completion;

/// Convenience method to present a view controller on the active view controller.
///
/// If the receiver is not in a window, or already has a presented view controller, this method will
/// attempt to find the most appropriate view controller for presenting.
///
/// \param viewControllerToPresent The view controller to display over the view controller’s content
///
/// \param animated Whether to animate the presentation
///
/// \param completion An optional closure to execute after the presentation finishes
- (void)presentViewControllerOnActiveViewController:(UIViewController * _Nonnull)viewControllerToPresent animated:(BOOL)animated completion:(void (^ _Nullable)(void))completion;
@end

#pragma clang diagnostic pop
