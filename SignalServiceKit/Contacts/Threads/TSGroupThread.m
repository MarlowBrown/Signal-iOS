//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSGroupThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSGroupThreadAvatarChangedNotification = @"TSGroupThreadAvatarChangedNotification";
NSString *const TSGroupThread_NotificationKey_UniqueId = @"TSGroupThread_NotificationKey_UniqueId";

@interface TSGroupThread ()

@property (nonatomic) TSGroupModel *groupModel;

@end

#pragma mark -

@implementation TSGroupThread

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
   conversationColorNameObsolete:(NSString *)conversationColorNameObsolete
                    creationDate:(nullable NSDate *)creationDate
             editTargetTimestamp:(nullable NSNumber *)editTargetTimestamp
              isArchivedObsolete:(BOOL)isArchivedObsolete
          isMarkedUnreadObsolete:(BOOL)isMarkedUnreadObsolete
            lastInteractionRowId:(uint64_t)lastInteractionRowId
          lastSentStoryTimestamp:(nullable NSNumber *)lastSentStoryTimestamp
       lastVisibleSortIdObsolete:(uint64_t)lastVisibleSortIdObsolete
lastVisibleSortIdOnScreenPercentageObsolete:(double)lastVisibleSortIdOnScreenPercentageObsolete
         mentionNotificationMode:(TSThreadMentionNotificationMode)mentionNotificationMode
                    messageDraft:(nullable NSString *)messageDraft
          messageDraftBodyRanges:(nullable MessageBodyRanges *)messageDraftBodyRanges
          mutedUntilDateObsolete:(nullable NSDate *)mutedUntilDateObsolete
     mutedUntilTimestampObsolete:(uint64_t)mutedUntilTimestampObsolete
           shouldThreadBeVisible:(BOOL)shouldThreadBeVisible
                   storyViewMode:(TSThreadStoryViewMode)storyViewMode
                      groupModel:(TSGroupModel *)groupModel
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId
     conversationColorNameObsolete:conversationColorNameObsolete
                      creationDate:creationDate
               editTargetTimestamp:editTargetTimestamp
                isArchivedObsolete:isArchivedObsolete
            isMarkedUnreadObsolete:isMarkedUnreadObsolete
              lastInteractionRowId:lastInteractionRowId
            lastSentStoryTimestamp:lastSentStoryTimestamp
         lastVisibleSortIdObsolete:lastVisibleSortIdObsolete
lastVisibleSortIdOnScreenPercentageObsolete:lastVisibleSortIdOnScreenPercentageObsolete
           mentionNotificationMode:mentionNotificationMode
                      messageDraft:messageDraft
            messageDraftBodyRanges:messageDraftBodyRanges
            mutedUntilDateObsolete:mutedUntilDateObsolete
       mutedUntilTimestampObsolete:mutedUntilTimestampObsolete
             shouldThreadBeVisible:shouldThreadBeVisible
                     storyViewMode:storyViewMode];

    if (!self) {
        return self;
    }

    _groupModel = groupModel;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithGroupModel:(TSGroupModelV2 *)groupModel
{
    OWSAssertDebug(groupModel);
    OWSAssertDebug(groupModel.groupId.length > 0);
#ifdef DEBUG
    for (SignalServiceAddress *address in groupModel.groupMembers) {
        OWSAssertDebug(address.isValid);
    }
#endif

    NSString *uniqueIdentifier = [[self class] defaultThreadIdForGroupId:groupModel.groupId];
    self = [super initWithUniqueId:uniqueIdentifier];
    if (!self) {
        return self;
    }

    _groupModel = groupModel;

    return self;
}

+ (nullable instancetype)fetchWithGroupId:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *uniqueId = [self threadIdForGroupId:groupId transaction:transaction];
    return [TSGroupThread anyFetchGroupThreadWithUniqueId:uniqueId transaction:transaction];
}

- (NSArray<SignalServiceAddress *> *)recipientAddressesWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSMutableArray<SignalServiceAddress *> *groupMembers = [self.groupModel.groupMembers mutableCopy];
    if (groupMembers == nil) {
        return @[];
    }

    [groupMembers removeObject:[TSAccountManagerObjcBridge localAciAddressWith:transaction]];

    return [groupMembers copy];
}

- (NSString *)groupNameOrDefault
{
    return self.groupModel.groupNameOrDefault;
}

+ (NSString *)defaultGroupName
{
    return OWSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
}

- (void)updateWithGroupModel:(TSGroupModel *)groupModel transaction:(SDSAnyWriteTransaction *)transaction
{
    [self updateWithGroupModel:groupModel shouldUpdateChatListUi:YES transaction:transaction];
}

- (void)updateWithGroupModel:(TSGroupModel *)newGroupModel
      shouldUpdateChatListUi:(BOOL)shouldUpdateChatListUi
                 transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(newGroupModel);
    OWSAssertDebug(transaction);

    switch (newGroupModel.groupsVersion) {
        case GroupsVersionV1:
            OWSAssertDebug(newGroupModel.groupsVersion == self.groupModel.groupsVersion);
            break;
        case GroupsVersionV2:
            // Group version may be changing due to migration.
            break;
    }

    BOOL didAvatarChange = ![NSObject isNullableObject:newGroupModel.avatarHash equalTo:self.groupModel.avatarHash];
    BOOL didNameChange = ![newGroupModel.groupNameOrDefault isEqualToString:self.groupModel.groupNameOrDefault];

    NSArray<SignalServiceAddress *> *oldGroupMembers = self.groupModel.groupMembers;

    [self
        anyUpdateGroupThreadWithTransaction:transaction
                                      block:^(TSGroupThread *thread) {
                                          if ([thread.groupModel isKindOfClass:TSGroupModelV2.class]) {
                                              if (![newGroupModel isKindOfClass:TSGroupModelV2.class]) {
                                                  // Can't downgrade a v2 group to a v1 group.
                                                  OWSFail(@"Invalid group model.");
                                              } else {
                                                  // Can't downgrade a v2 group to an earlier revision.
                                                  TSGroupModelV2 *oldGroupModelV2 = (TSGroupModelV2 *)thread.groupModel;
                                                  TSGroupModelV2 *newGroupModelV2 = (TSGroupModelV2 *)newGroupModel;
                                                  OWSPrecondition(oldGroupModelV2.revision <= newGroupModelV2.revision);
                                              }
                                          }

                                          thread.groupModel = [newGroupModel copy];
                                      }];
    [self updateGroupMemberRecordsWithTransaction:transaction];
    [self clearGroupSendEndorsementsIfNeededWithOldGroupMembers:oldGroupMembers tx:transaction];

    // We only need to re-index the group if the group name changed.
    [SSKEnvironment.shared.databaseStorageRef touchThread:self
                                            shouldReindex:didNameChange
                                   shouldUpdateChatListUi:shouldUpdateChatListUi
                                              transaction:transaction];

    if (didAvatarChange) {
        [transaction addAsyncCompletionOnMain:^{ [self fireAvatarChangedNotification]; }];
    }
}

- (void)fireAvatarChangedNotification
{
    OWSAssertIsOnMainThread();

    NSDictionary *userInfo = @{ TSGroupThread_NotificationKey_UniqueId : self.uniqueId };

    [[NSNotificationCenter defaultCenter] postNotificationName:TSGroupThreadAvatarChangedNotification
                                                        object:self.uniqueId
                                                      userInfo:userInfo];
}

#pragma mark -

- (void)anyWillInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillInsertWithTransaction:transaction];
    [self updateGroupMemberRecordsWithTransaction:transaction];
}

- (void)anyWillUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillUpdateWithTransaction:transaction];

    // We used to update the group member records here, but there are many updates that don't touch membership.
    // Now it's done explicitly where we update the group model, and not for other updates.
}

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidInsertWithTransaction:transaction];

    OWSLogInfo(@"Inserted group thread: %@", self.groupId.hexadecimalString);
}

@end

NS_ASSUME_NONNULL_END
