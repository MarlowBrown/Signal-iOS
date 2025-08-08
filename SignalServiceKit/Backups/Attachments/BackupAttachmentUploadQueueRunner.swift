//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol BackupAttachmentUploadQueueRunner {

    /// Backs up all pending attachments in the BackupAttachmentUploadQueue.
    ///
    /// Will keep backing up attachments until there are none left, then returns.
    /// Is cooperatively cancellable; will check and early terminate if the task is cancelled
    /// in between individual attachments.
    ///
    /// Returns immediately if there's no attachments left to back up.
    ///
    /// Each individual attachments is either freshly uploaded or copied from the transit
    /// tier to the media tier as needed. Thumbnail versions are also created, uploaded, and
    /// backed up as needed.
    ///
    /// Throws an error IFF something would prevent all attachments from backing up (e.g. network issue).
    func backUpAllAttachments() async throws
}

extension BackupAttachmentUploadQueueRunner where Self: Sendable {

    public func backUpAllAttachmentsAfterTxCommits(
        tx: DBWriteTransaction
    ) {
        tx.addSyncCompletion { [self] in
            Task {
                try await self.backUpAllAttachments()
            }
        }
    }
}

class BackupAttachmentUploadQueueRunnerImpl: BackupAttachmentUploadQueueRunner {

    private let accountKeyStore: AccountKeyStore
    private let attachmentStore: AttachmentStore
    private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
    private let backupRequestManager: BackupRequestManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: any DB
    private let logger: PrefixedLogger
    private let listMediaManager: BackupListMediaManager
    private let progress: BackupAttachmentUploadProgress
    private let statusManager: BackupAttachmentUploadQueueStatusManager
    private let taskQueue: TaskQueueLoader<TaskRunner>
    private let tsAccountManager: TSAccountManager

    init(
        accountKeyStore: AccountKeyStore,
        appReadiness: AppReadiness,
        attachmentStore: AttachmentStore,
        attachmentUploadManager: AttachmentUploadManager,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        backupListMediaManager: BackupListMediaManager,
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
        orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
        progress: BackupAttachmentUploadProgress,
        statusManager: BackupAttachmentUploadQueueStatusManager,
        tsAccountManager: TSAccountManager
    ) {
        self.accountKeyStore = accountKeyStore
        self.attachmentStore = attachmentStore
        self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.backupRequestManager = backupRequestManager
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.listMediaManager = backupListMediaManager
        self.progress = progress
        self.statusManager = statusManager
        self.tsAccountManager = tsAccountManager
        let taskRunner = TaskRunner(
            accountKeyStore: accountKeyStore,
            attachmentStore: attachmentStore,
            attachmentUploadManager: attachmentUploadManager,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            logger: logger,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            progress: progress,
            statusManager: statusManager,
            tsAccountManager: tsAccountManager
        )
        self.taskQueue = TaskQueueLoader(
            maxConcurrentTasks: Constants.numParallelUploads,
            dateProvider: dateProvider,
            db: db,
            runner: taskRunner
        )

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            self?.startObservingQueueStatus()
            Task { [weak self] in
                try await self?.backUpAllAttachments()
            }
        }
    }

    public func backUpAllAttachments() async throws {
        guard FeatureFlags.Backups.supported else {
            return
        }
        let (isPrimary, localAci, backupPlan, backupKey) = db.read { tx in
            (
                self.tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? false,
                self.tsAccountManager.localIdentifiers(tx: tx)?.aci,
                backupSettingsStore.backupPlan(tx: tx),
                accountKeyStore.getMediaRootBackupKey(tx: tx)
            )
        }

        guard isPrimary, let localAci else {
            return
        }

        guard let backupKey else {
            Logger.info("Skipping attachment backups while media backup key is missing")
            return
        }

        switch backupPlan {
        case .disabled, .disabling, .free:
            return
        case .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        let backupAuth: BackupServiceAuth
        do {
            // If we have no credentials, or a free credential, we want to fetch new
            // credentials, as we think we're paid tier according to local state.
            // We'll need the paid credential to upload in each task; we load and cache
            // it now so its available (and so we can bail early if its somehow free tier).
            backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                for: backupKey,
                localAci: localAci,
                auth: .implicit(),
                forceRefreshUnlessCachedPaidCredential: true
            )
        } catch let error as BackupAuthCredentialFetchError {
            switch error {
            case .noExistingBackupId:
                // If we have no backup, we sure won't be uploading.
                logger.info("Bailing on attachment backups when backup id not registered")
                return
            }
        } catch let error {
            throw error
        }

        switch backupAuth.backupLevel {
        case .free:
            owsFailDebug("Local backupPlan is paid but credential is free")
            // If our force refreshed credential is free tier, we definitely
            // aren't uploading anything, so may as well stop the queue.
            try? await taskQueue.stop()
            return
        case .paid:
            break
        }

        if FeatureFlags.Backups.supported {
            try await listMediaManager.queryListMediaIfNeeded()
        }

        switch await statusManager.beginObservingIfNecessary() {
        case .running:
            logger.info("Running Backup uploads.")
            let backgroundTask = OWSBackgroundTask(label: #function) { [weak taskQueue] status in
                switch status {
                case .expired:
                    Task {
                        try await taskQueue?.stop()
                    }
                case .couldNotStart, .success:
                    break
                }
            }
            defer { backgroundTask.end() }
            try await taskQueue.loadAndRunTasks()
        case .empty:
            logger.info("Skipping Backup uploads: queue is empty.")
            return
        case .notRegisteredAndReady:
            logger.warn("Skipping Backup uploads: not registered and ready.")
            try await taskQueue.stop()
        case .noWifiReachability:
            logger.warn("Skipping Backup uploads: need wifi.")
            try await taskQueue.stop()
        case .noReachability:
            logger.warn("Skipping Backup uploads: need internet.")
            try await taskQueue.stop()
        case .lowBattery:
            logger.warn("Skipping Backup uploads: low battery.")
            try await taskQueue.stop()
        case .appBackgrounded:
            logger.warn("Skipping Backup uploads: app backgrounded")
        }
    }

    // MARK: - Observation

    private func startObservingQueueStatus() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queueStatusDidChange),
            name: .backupAttachmentUploadQueueStatusDidChange,
            object: nil
        )
    }

    @objc
    private func queueStatusDidChange() {
        Task {
            try await self.backUpAllAttachments()
        }
    }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let accountKeyStore: AccountKeyStore
        private let attachmentStore: AttachmentStore
        private let attachmentUploadManager: AttachmentUploadManager
        private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
        private let backupAttachmentUploadStore: BackupAttachmentUploadStore
        private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
        private let backupRequestManager: BackupRequestManager
        private let backupSettingsStore: BackupSettingsStore
        private let dateProvider: DateProvider
        private let db: any DB
        private let logger: PrefixedLogger
        private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore
        private let progress: BackupAttachmentUploadProgress
        private let statusManager: BackupAttachmentUploadQueueStatusManager
        private let tsAccountManager: TSAccountManager

        let store: TaskStore

        init(
            accountKeyStore: AccountKeyStore,
            attachmentStore: AttachmentStore,
            attachmentUploadManager: AttachmentUploadManager,
            backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
            backupAttachmentUploadStore: BackupAttachmentUploadStore,
            backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
            backupRequestManager: BackupRequestManager,
            backupSettingsStore: BackupSettingsStore,
            dateProvider: @escaping DateProvider,
            db: any DB,
            logger: PrefixedLogger,
            orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
            progress: BackupAttachmentUploadProgress,
            statusManager: BackupAttachmentUploadQueueStatusManager,
            tsAccountManager: TSAccountManager
        ) {
            self.accountKeyStore = accountKeyStore
            self.attachmentStore = attachmentStore
            self.attachmentUploadManager = attachmentUploadManager
            self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
            self.backupAttachmentUploadStore = backupAttachmentUploadStore
            self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
            self.backupRequestManager = backupRequestManager
            self.backupSettingsStore = backupSettingsStore
            self.dateProvider = dateProvider
            self.db = db
            self.logger = logger
            self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
            self.progress = progress
            self.statusManager = statusManager
            self.tsAccountManager = tsAccountManager

            self.store = TaskStore(backupAttachmentUploadStore: backupAttachmentUploadStore)
        }

        func runTask(record: Store.Record, loader: TaskQueueLoader<TaskRunner>) async -> TaskRecordResult {
            guard FeatureFlags.Backups.supported else {
                return .cancelled
            }

            struct NeedsBatteryError: Error {}
            struct NeedsInternetError: Error {}
            struct NeedsToBeRegisteredError: Error {}
            struct AppBackgroundedError: Error {}

            switch await statusManager.currentStatus() {
            case .running:
                break
            case .empty:
                // The queue will stop on its own, finish this task.
                break
            case .lowBattery:
                try? await loader.stop()
                return .retryableError(NeedsBatteryError())
            case .noWifiReachability, .noReachability:
                try? await loader.stop()
                return .retryableError(NeedsInternetError())
            case .notRegisteredAndReady:
                try? await loader.stop()
                return .retryableError(NeedsToBeRegisteredError())
            case .appBackgrounded:
                try? await loader.stop()
                return .retryableError(AppBackgroundedError())
            }

            let (attachment, backupPlan, currentUploadEra, backupKey) = db.read { tx in
                return (
                    self.attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx),
                    self.backupSettingsStore.backupPlan(tx: tx),
                    self.backupAttachmentUploadEraStore.currentUploadEra(tx: tx),
                    self.accountKeyStore.getMediaRootBackupKey(tx: tx)
                )
            }
            guard let attachment else {
                // Attachment got deleted; early exit.
                return .cancelled
            }

            guard attachment.asStream() != nil, let mediaName = attachment.mediaName else {
                // We only back up attachments we've downloaded (streams)
                return .cancelled
            }

            guard let backupKey else {
                owsFailDebug("Missing media backup key.  Unable to upload attachments.")
                return .cancelled
            }

            // We're about to upload; ensure we aren't also enqueuing a media tier delete.
            // This is only defensive as we should be cancelling any deletes any time we
            // create an attachmenr stream and enqueue an upload to begin with.
            do {
                try await db.awaitableWrite { tx in
                    if record.record.isFullsize {
                        let mediaId = try backupKey.mediaEncryptionMetadata(
                            mediaName: mediaName,
                            // Doesn't matter what we use, we just want the mediaId
                            type: .outerLayerFullsizeOrThumbnail
                        ).mediaId
                        try orphanedBackupAttachmentStore.removeFullsize(
                            mediaName: mediaName,
                            fullsizeMediaId: mediaId,
                            tx: tx
                        )
                    } else {
                        let mediaId = try backupKey.mediaEncryptionMetadata(
                            mediaName: AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName),
                            // Doesn't matter what we use, we just want the mediaId
                            type: .outerLayerFullsizeOrThumbnail
                        ).mediaId
                        try orphanedBackupAttachmentStore.removeThumbnail(
                            fullsizeMediaName: mediaName,
                            thumbnailMediaId: mediaId,
                            tx: tx
                        )
                    }
                }
            } catch {
                owsFailDebug("Unable to delete orphan row. Proceeding anyway.")
            }

            struct IsFreeTierError: Error {}
            switch backupPlan {
            case .disabled, .disabling, .free:
                try? await loader.stop()
                return .retryableError(IsFreeTierError())
            case .paid, .paidExpiringSoon, .paidAsTester:
                break
            }

            let localAci = db.read { tx in
                return self.tsAccountManager.localIdentifiers(tx: tx)?.aci
            }
            guard let localAci else {
                let error = OWSAssertionError("Not registered!")
                try? await loader.stop(reason: error)
                return .retryableError(error)
            }

            let backupAuth: BackupServiceAuth
            do {
                backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                    for: backupKey,
                    localAci: localAci,
                    auth: .implicit(),
                    // No need to force it here; when we start up the queue we force
                    // a fetch, and should've bailed and never gotten this far if it
                    // was a free tier credential. (Though the paid state and credential
                    // can change _after_ this queue has already started running, so we
                    // do need to handle that case).
                    forceRefreshUnlessCachedPaidCredential: false
                )
            } catch let error {
                try? await loader.stop(reason: error)
                return .retryableError(error)
            }

            switch backupAuth.backupLevel {
            case .paid:
                break
            case .free:
                // If we find ourselves with a free tier credential,
                // all uploads will fail. Just quit.
                try? await loader.stop()
                return .retryableError(IsFreeTierError())
            }

            let progressSink = await progress.willBeginUploadingAttachment(
                uploadRecord: record.record
            )

            guard
                db.read(block: { tx in
                    backupAttachmentUploadScheduler.isEligibleToUpload(
                        attachment,
                        fullsize: record.record.isFullsize,
                        currentUploadEra: currentUploadEra,
                        tx: tx
                    )
                })
            else {
                await progress.didFinishUploadOfAttachment(
                    uploadRecord: record.record
                )
                // Not eligible anymore, count as success.
                return .success
            }

            do {
                if record.record.isFullsize {
                    try await attachmentUploadManager.uploadMediaTierAttachment(
                        attachmentId: attachment.id,
                        uploadEra: currentUploadEra,
                        localAci: localAci,
                        backupKey: backupKey,
                        auth: backupAuth,
                        progress: progressSink
                    )
                } else {
                    try await attachmentUploadManager.uploadMediaTierThumbnailAttachment(
                        attachmentId: attachment.id,
                        uploadEra: currentUploadEra,
                        localAci: localAci,
                        backupKey: backupKey,
                        auth: backupAuth
                    )
                }
            } catch let error {
                switch error as? BackupArchive.Response.CopyToMediaTierError {
                case .sourceObjectNotFound:
                    // Any time we find this error, retry. It means the upload
                    // expired, and so the copy failed. This is always transient
                    // and can always be fixed by reuploading, don't even increment
                    // the retry count.
                    return .retryableError(error)
                case .forbidden:
                    // This only happens if we've lost write access to the media tier.
                    // As a final check, force refresh our crednetial and check if its
                    // paid. If its not (we just got a 403 so that's what we expect),
                    // all uploads will fail so dequeue them and quit.
                    let credential = try? await backupRequestManager.fetchBackupServiceAuth(
                        for: backupKey,
                        localAci: localAci,
                        auth: .implicit(),
                        forceRefreshUnlessCachedPaidCredential: true
                    )
                    switch credential?.backupLevel {
                    case .free, nil:
                        try? await loader.stop()
                        return .retryableError(IsFreeTierError())
                    case .paid:
                        break
                    }
                    fallthrough
                default:
                    // All other errors should be treated as per normal.
                    if error.httpStatusCode == 429 {
                        if let retryAfter = error.httpResponseHeaders?.retryAfterTimeInterval {
                            return .retryableError(RateLimitedRetryError(retryAfter: retryAfter))
                        }

                        // If for whatever reason we don't have a retry-after,
                        // treat this like a network error that retries with
                        // backoff.
                        return .retryableError(NetworkRetryError())
                    } else if error.isNetworkFailureOrTimeout {
                        switch await statusManager.currentStatus() {
                        case .running:
                            // If we _think_ we are connected and should be running,
                            // use a more crude retry time mechanism to retry later.
                            // Note that we update the individual row but really this
                            // will end up holding up the entire queue because we don't
                            // reorder when popping off the queue based on retry time,
                            // so this row will remain first in line (unless something else
                            // changes, in which case we retry and either succeed or fall back
                            // into here) and block the rest of the queue from trying,
                            // which is what we want because the error is a general network
                            // issue.
                            return .retryableError(NetworkRetryError())
                        case .noWifiReachability, .notRegisteredAndReady,
                                .lowBattery, .appBackgrounded, .empty:
                            // These other states may be overriding reachability;
                            // just allow the queue itself to retry and once the
                            // other states are resolved reachability will kick in,
                            // or won't.
                            fallthrough
                        case .noReachability:
                            // If reachability thinks we are not connected, queue status
                            // will cover us. Don't touch the record itself; the queue will stop
                            // running and start again once reconnected, and we want to try
                            // the record again immediately then.
                            return .retryableError(error)
                        }
                    } else if record.record.isFullsize {
                        switch error as? Upload.Error {
                        case .missingFile:
                            // The file is missing! We can never retry this upload;
                            // call it a "success" so we don't mess with progress
                            // state and so we wipe the upload task row, and move on.
                            logger.error("Missing attachment file; skipping and proceeding")
                            await progress.didFinishUploadOfAttachment(
                                uploadRecord: record.record
                            )
                            return .success
                        default:
                            break
                        }
                        // For other errors stop the queue to prevent thundering herd;
                        // when it starts up again (e.g. on app launch) we will retry.
                        logger.error("Unknown error occurred; stopping the queue")
                        try? await loader.stop()
                        return .retryableError(error)
                    } else {
                        // Ignore the error if we e.g. fail to generate a thumbnail;
                        // just upload the fullsize.
                        logger.error("Failed to upload thumbnail; proceeding")
                        await progress.didFinishUploadOfAttachment(
                            uploadRecord: record.record
                        )
                        return .success
                    }
                }
            }

            await progress.didFinishUploadOfAttachment(
                uploadRecord: record.record
            )

            return .success
        }

        func didSucceed(record: Store.Record, tx: DBWriteTransaction) throws {
            logger.info("Finished backing up attachment \(record.record.attachmentRowId), upload \(record.id)")
        }

        private struct RateLimitedRetryError: Error {
            let retryAfter: TimeInterval
        }
        private struct NetworkRetryError: Error {}

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            logger.warn("Failed backing up attachment \(record.record.attachmentRowId), upload \(record.id), isRetryable: \(isRetryable), error: \(error)")

            guard isRetryable else {
                return
            }

            var record = record.record
            let retryDelay: TimeInterval

            if error is NetworkRetryError {
                record.numRetries += 1
                retryDelay = OWSOperation.retryIntervalForExponentialBackoff(failureCount: record.numRetries)
            } else if let rateLimitedError = error as? RateLimitedRetryError {
                retryDelay = rateLimitedError.retryAfter
            } else {
                return
            }

            record.minRetryTimestamp = dateProvider().addingTimeInterval(retryDelay).ows_millisecondsSince1970
            try record.update(tx.database)
        }

        func didCancel(record: Store.Record, tx: DBWriteTransaction) throws {
            logger.warn("Cancelled backing up attachment \(record.record.attachmentRowId), upload \(record.id)")
        }

        func didDrainQueue() async {
            await progress.didEmptyUploadQueue()
            await statusManager.didEmptyQueue()
        }
    }

    // MARK: - TaskRecordStore

    struct TaskRecord: SignalServiceKit.TaskRecord {
        let id: Int64
        let record: QueuedBackupAttachmentUpload

        var nextRetryTimestamp: UInt64? {
            return record.minRetryTimestamp
        }
    }

    class TaskStore: TaskRecordStore {

        private let backupAttachmentUploadStore: BackupAttachmentUploadStore

        init(backupAttachmentUploadStore: BackupAttachmentUploadStore) {
            self.backupAttachmentUploadStore = backupAttachmentUploadStore
        }

        func peek(count: UInt, tx: DBReadTransaction) throws -> [TaskRecord] {
            return try backupAttachmentUploadStore.fetchNextUploads(count: count, tx: tx).map {
                return .init(id: $0.id!, record: $0)
            }
        }

        func removeRecord(_ record: TaskRecord, tx: DBWriteTransaction) throws {
            try backupAttachmentUploadStore.removeQueuedUpload(
                for: record.record.attachmentRowId,
                fullsize: record.record.isFullsize,
                tx: tx
            )
        }
    }

    // MARK: -

    private enum Constants {
        static let numParallelUploads: UInt = 8
    }
}

#if TESTABLE_BUILD

open class BackupAttachmentUploadQueueRunnerMock: BackupAttachmentUploadQueueRunner {

    public init() {}

    public func backUpAllAttachments() async throws {
        // Do nothing
    }
}

#endif
