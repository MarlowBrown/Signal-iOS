//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SSKEnvironment: NSObject {

    private static var _shared: SSKEnvironment?

    public static var hasShared: Bool { _shared != nil }

    @objc
    public static var shared: SSKEnvironment { _shared! }

    public static func setShared(_ env: SSKEnvironment, isRunningTests: Bool) {
        owsPrecondition(_shared == nil || isRunningTests)
        _shared = env
    }

    #if TESTABLE_BUILD
    private(set) public var contactManagerRef: any ContactManager
    private(set) public var messageSenderRef: MessageSender
    private(set) public var networkManagerRef: NetworkManager
    private(set) public var paymentsHelperRef: PaymentsHelperSwift
    private(set) public var groupsV2Ref: GroupsV2
    #else
    public let contactManagerRef: any ContactManager
    public let messageSenderRef: MessageSender
    public let networkManagerRef: NetworkManager
    public let paymentsHelperRef: PaymentsHelperSwift
    public let groupsV2Ref: GroupsV2
    #endif
    /// This should be deprecated.
    public var contactManagerImplRef: OWSContactsManager { contactManagerRef as! OWSContactsManager }
    @objc
    public var contactManagerObjcRef: ContactsManagerProtocol { contactManagerRef }

    public let pendingReceiptRecorderRef: PendingReceiptRecorder
    public let profileManagerRef: ProfileManager
    /// This should be deprecated.
    public var profileManagerImplRef: OWSProfileManager { profileManagerRef as! OWSProfileManager }
    public let messageReceiverRef: MessageReceiver
    public let blockingManagerRef: BlockingManager
    public let remoteConfigManagerRef: RemoteConfigManager
    public let udManagerRef: OWSUDManager
    public let messageDecrypterRef: OWSMessageDecrypter
    public let groupsV2MessageProcessorRef: GroupsV2MessageProcessor
    public let ows2FAManagerRef: OWS2FAManager
    @objc
    public let disappearingMessagesJobRef: OWSDisappearingMessagesJob
    @objc
    public let receiptManagerRef: OWSReceiptManager
    @objc
    public let receiptSenderRef: ReceiptSender
    public let reachabilityManagerRef: SSKReachabilityManager
    public let syncManagerRef: SyncManagerProtocol
    public let typingIndicatorsRef: TypingIndicators
    public let stickerManagerRef: StickerManager
    @objc
    public let databaseStorageRef: SDSDatabaseStorage
    public let signalServiceAddressCacheRef: SignalServiceAddressCache
    public let signalServiceRef: OWSSignalServiceProtocol
    public let accountServiceClientRef: AccountServiceClient
    public let storageServiceManagerRef: StorageServiceManager
    public let sskPreferencesRef: SSKPreferences
    public let groupV2UpdatesRef: GroupV2Updates
    public let messageFetcherJobRef: MessageFetcherJob
    public let versionedProfilesRef: VersionedProfilesSwift
    @objc
    public let modelReadCachesRef: ModelReadCaches
    public let earlyMessageManagerRef: EarlyMessageManager
    public let messagePipelineSupervisorRef: MessagePipelineSupervisor
    public let messageProcessorRef: MessageProcessor
    public let paymentsCurrenciesRef: PaymentsCurrenciesSwift
    @objc
    public let paymentsEventsRef: PaymentsEvents
    public let owsPaymentsLockRef: OWSPaymentsLock
    public let mobileCoinHelperRef: MobileCoinHelper
    public let spamChallengeResolverRef: SpamChallengeResolver
    public let senderKeyStoreRef: SenderKeyStore
    public let phoneNumberUtilRef: PhoneNumberUtil
    public let webSocketFactoryRef: WebSocketFactory
    public let legacyChangePhoneNumberRef: LegacyChangePhoneNumber
    public let systemStoryManagerRef: SystemStoryManagerProtocol
    public let contactDiscoveryManagerRef: ContactDiscoveryManager
    public let notificationPresenterRef: any NotificationPresenter
    public let messageSendLogRef: MessageSendLog
    public let messageSenderJobQueueRef: MessageSenderJobQueue
    public let localUserLeaveGroupJobQueueRef: LocalUserLeaveGroupJobQueue
    public let callRecordDeleteAllJobQueueRef: CallRecordDeleteAllJobQueue
    public let bulkDeleteInteractionJobQueueRef: BulkDeleteInteractionJobQueue
    public let preferencesRef: Preferences
    public let proximityMonitoringManagerRef: OWSProximityMonitoringManager
    public let avatarBuilderRef: AvatarBuilder
    public let smJobQueuesRef: SignalMessagingJobQueues
    public let groupCallManagerRef: GroupCallManager
    public let profileFetcherRef: any ProfileFetcher

    private let appExpiryRef: AppExpiry
    private let aciSignalProtocolStoreRef: SignalProtocolStore
    private let pniSignalProtocolStoreRef: SignalProtocolStore

    public init(
        contactManager: any ContactManager,
        messageSender: MessageSender,
        pendingReceiptRecorder: PendingReceiptRecorder,
        profileManager: ProfileManager,
        networkManager: NetworkManager,
        messageReceiver: MessageReceiver,
        blockingManager: BlockingManager,
        remoteConfigManager: RemoteConfigManager,
        aciSignalProtocolStore: SignalProtocolStore,
        pniSignalProtocolStore: SignalProtocolStore,
        udManager: OWSUDManager,
        messageDecrypter: OWSMessageDecrypter,
        groupsV2MessageProcessor: GroupsV2MessageProcessor,
        ows2FAManager: OWS2FAManager,
        disappearingMessagesJob: OWSDisappearingMessagesJob,
        receiptManager: OWSReceiptManager,
        receiptSender: ReceiptSender,
        reachabilityManager: SSKReachabilityManager,
        syncManager: SyncManagerProtocol,
        typingIndicators: TypingIndicators,
        stickerManager: StickerManager,
        databaseStorage: SDSDatabaseStorage,
        signalServiceAddressCache: SignalServiceAddressCache,
        signalService: OWSSignalServiceProtocol,
        accountServiceClient: AccountServiceClient,
        storageServiceManager: StorageServiceManager,
        sskPreferences: SSKPreferences,
        groupsV2: GroupsV2,
        groupV2Updates: GroupV2Updates,
        messageFetcherJob: MessageFetcherJob,
        versionedProfiles: VersionedProfilesSwift,
        modelReadCaches: ModelReadCaches,
        earlyMessageManager: EarlyMessageManager,
        messagePipelineSupervisor: MessagePipelineSupervisor,
        appExpiry: AppExpiry,
        messageProcessor: MessageProcessor,
        paymentsHelper: PaymentsHelperSwift,
        paymentsCurrencies: PaymentsCurrenciesSwift,
        paymentsEvents: PaymentsEvents,
        paymentsLock: OWSPaymentsLock,
        mobileCoinHelper: MobileCoinHelper,
        spamChallengeResolver: SpamChallengeResolver,
        senderKeyStore: SenderKeyStore,
        phoneNumberUtil: PhoneNumberUtil,
        webSocketFactory: WebSocketFactory,
        legacyChangePhoneNumber: LegacyChangePhoneNumber,
        systemStoryManager: SystemStoryManagerProtocol,
        contactDiscoveryManager: ContactDiscoveryManager,
        notificationPresenter: any NotificationPresenter,
        messageSendLog: MessageSendLog,
        messageSenderJobQueue: MessageSenderJobQueue,
        localUserLeaveGroupJobQueue: LocalUserLeaveGroupJobQueue,
        callRecordDeleteAllJobQueue: CallRecordDeleteAllJobQueue,
        bulkdDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue,
        preferences: Preferences,
        proximityMonitoringManager: OWSProximityMonitoringManager,
        avatarBuilder: AvatarBuilder,
        smJobQueues: SignalMessagingJobQueues,
        groupCallManager: GroupCallManager,
        profileFetcher: any ProfileFetcher
    ) {
        self.contactManagerRef = contactManager
        self.messageSenderRef = messageSender
        self.pendingReceiptRecorderRef = pendingReceiptRecorder
        self.profileManagerRef = profileManager
        self.networkManagerRef = networkManager
        self.messageReceiverRef = messageReceiver
        self.blockingManagerRef = blockingManager
        self.remoteConfigManagerRef = remoteConfigManager
        self.aciSignalProtocolStoreRef = aciSignalProtocolStore
        self.pniSignalProtocolStoreRef = pniSignalProtocolStore
        self.udManagerRef = udManager
        self.messageDecrypterRef = messageDecrypter
        self.groupsV2MessageProcessorRef = groupsV2MessageProcessor
        self.ows2FAManagerRef = ows2FAManager
        self.disappearingMessagesJobRef = disappearingMessagesJob
        self.receiptManagerRef = receiptManager
        self.receiptSenderRef = receiptSender
        self.syncManagerRef = syncManager
        self.reachabilityManagerRef = reachabilityManager
        self.typingIndicatorsRef = typingIndicators
        self.stickerManagerRef = stickerManager
        self.databaseStorageRef = databaseStorage
        self.signalServiceAddressCacheRef = signalServiceAddressCache
        self.signalServiceRef = signalService
        self.accountServiceClientRef = accountServiceClient
        self.storageServiceManagerRef = storageServiceManager
        self.sskPreferencesRef = sskPreferences
        self.groupsV2Ref = groupsV2
        self.groupV2UpdatesRef = groupV2Updates
        self.messageFetcherJobRef = messageFetcherJob
        self.versionedProfilesRef = versionedProfiles
        self.modelReadCachesRef = modelReadCaches
        self.earlyMessageManagerRef = earlyMessageManager
        self.messagePipelineSupervisorRef = messagePipelineSupervisor
        self.appExpiryRef = appExpiry
        self.messageProcessorRef = messageProcessor
        self.paymentsHelperRef = paymentsHelper
        self.paymentsCurrenciesRef = paymentsCurrencies
        self.paymentsEventsRef = paymentsEvents
        self.owsPaymentsLockRef = paymentsLock
        self.mobileCoinHelperRef = mobileCoinHelper
        self.spamChallengeResolverRef = spamChallengeResolver
        self.senderKeyStoreRef = senderKeyStore
        self.phoneNumberUtilRef = phoneNumberUtil
        self.webSocketFactoryRef = webSocketFactory
        self.legacyChangePhoneNumberRef = legacyChangePhoneNumber
        self.systemStoryManagerRef = systemStoryManager
        self.contactDiscoveryManagerRef = contactDiscoveryManager
        self.notificationPresenterRef = notificationPresenter
        self.messageSendLogRef = messageSendLog
        self.messageSenderJobQueueRef = messageSenderJobQueue
        self.localUserLeaveGroupJobQueueRef = localUserLeaveGroupJobQueue
        self.callRecordDeleteAllJobQueueRef = callRecordDeleteAllJobQueue
        self.bulkDeleteInteractionJobQueueRef = bulkdDeleteInteractionJobQueue
        self.preferencesRef = preferences
        self.proximityMonitoringManagerRef = proximityMonitoringManager
        self.avatarBuilderRef = avatarBuilder
        self.smJobQueuesRef = smJobQueues
        self.groupCallManagerRef = groupCallManager
        self.profileFetcherRef = profileFetcher
    }

    public func signalProtocolStoreRef(for identity: OWSIdentity) -> SignalProtocolStore {
        switch identity {
        case .aci:
            return aciSignalProtocolStoreRef
        case .pni:
            return pniSignalProtocolStoreRef
        }
    }

    public static let warmCachesNotification = Notification.Name("WarmCachesNotification")

    func warmCaches(appReadiness: AppReadiness) {
        SignalProxy.warmCaches(appReadiness: appReadiness)
        DependenciesBridge.shared.tsAccountManager.warmCaches()
        fixLocalRecipientIfNeeded()
        SSKEnvironment.shared.signalServiceAddressCacheRef.warmCaches()
        SSKEnvironment.shared.signalServiceRef.warmCaches()
        SSKEnvironment.shared.remoteConfigManagerRef.warmCaches()
        SSKEnvironment.shared.blockingManagerRef.warmCaches()
        SSKEnvironment.shared.profileManagerRef.warmCaches()
        SSKEnvironment.shared.receiptManagerRef.prepareCachedValues()
        DependenciesBridge.shared.svr.warmCaches()
        SSKEnvironment.shared.typingIndicatorsRef.warmCaches()
        SSKEnvironment.shared.paymentsHelperRef.warmCaches()
        SSKEnvironment.shared.paymentsCurrenciesRef.warmCaches()
        StoryManager.setup(appReadiness: appReadiness)
        DonationSubscriptionManager.warmCaches()
        DependenciesBridge.shared.db.read { tx in appExpiryRef.warmCaches(with: tx) }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.localUserLeaveGroupJobQueueRef.start(appContext: CurrentAppContext())
            self.callRecordDeleteAllJobQueueRef.start(appContext: CurrentAppContext())
            self.bulkDeleteInteractionJobQueueRef.start(appContext: CurrentAppContext())
            self.smJobQueuesRef.incomingContactSyncJobQueue.start(appContext: CurrentAppContext())
            self.smJobQueuesRef.receiptCredentialJobQueue.start(appContext: CurrentAppContext())
            self.smJobQueuesRef.sendGiftBadgeJobQueue.start(appContext: CurrentAppContext())
            self.smJobQueuesRef.sessionResetJobQueue.start(appContext: CurrentAppContext())
        }

        NotificationCenter.default.post(name: SSKEnvironment.warmCachesNotification, object: nil)
    }

    /// Ensures the local SignalRecipient is correct.
    ///
    /// This primarily serves to ensure the local SignalRecipient has its own
    /// Pni (a one-time migration), but it also helps ensure that the value is
    /// always consistent with TSAccountManager's values.
    private func fixLocalRecipientIfNeeded() {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                return  // Not registered yet.
            }
            guard let phoneNumber = E164(localIdentifiers.phoneNumber) else {
                return  // Registered with an invalid phone number.
            }
            let recipientMerger = DependenciesBridge.shared.recipientMerger
            _ = recipientMerger.applyMergeForLocalAccount(
                aci: localIdentifiers.aci,
                phoneNumber: phoneNumber,
                pni: localIdentifiers.pni,
                tx: tx.asV2Write
            )
        }
    }

    #if TESTABLE_BUILD

    public func setContactManagerForUnitTests(_ contactManager: any ContactManager) {
        self.contactManagerRef = contactManager
    }

    public func setMessageSenderForUnitTests(_ messageSender: MessageSender) {
        self.messageSenderRef = messageSender
    }

    public func setNetworkManagerForUnitTests(_ networkManager: NetworkManager) {
        self.networkManagerRef = networkManager
    }

    public func setPaymentsHelperForUnitTests(_ paymentsHelper: PaymentsHelperSwift) {
        self.paymentsHelperRef = paymentsHelper
    }

    public func setGroupsV2ForUnitTests(_ groupsV2: GroupsV2) {
        self.groupsV2Ref = groupsV2
    }

    #endif
}
