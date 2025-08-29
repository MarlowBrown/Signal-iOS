//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct PollOptionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "PollOption"

    public var id: Int64?
    public let pollId: Int64
    public let option: String
    public let optionIndex: Int32

    mutating public func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    public init(
        pollId: Int64,
        option: String,
        optionIndex: Int32
    ) {
        self.pollId = pollId
        self.option = option
        self.optionIndex = optionIndex
    }

    enum CodingKeys: String, CodingKey {
        case id
        case pollId
        case option
        case optionIndex
    }
}
