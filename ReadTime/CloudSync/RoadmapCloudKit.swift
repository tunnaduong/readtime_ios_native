import SwiftUI
#if !SKIP
import CloudKit
#endif

// MARK: - Roadmap

/// A feature on the public roadmap, stored in the CloudKit public database.
///
/// CloudKit setup (container `iCloud.com.fatties.readtime`, CloudKit Console):
/// - `FeatureRequest`: title (String), details (String), status (String), listed (Int64, Queryable).
///   Only records with `listed = 1` appear, so set it after reviewing a suggestion.
/// - `Vote`: featureName (String, Queryable). One record per user and feature.
/// Deploy the schema to Production before release.
struct FeatureRequest: Identifiable, Hashable {
    enum Status: String, CaseIterable, Identifiable {
        case inReview, planned, inProgress, completed

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .inReview: "In Review"
            case .planned: "Planned"
            case .inProgress: "In Progress"
            case .completed: "Completed"
            }
        }

        var color: Color {
            switch self {
            case .inReview: .blue
            case .planned: .readTimePurple
            case .inProgress: .orange
            case .completed: .readTimeGreen
            }
        }
    }

    let id: String
    var title: String
    var details: String
    var status: Status
    var votes: Int
    var hasVoted: Bool
}

#if !SKIP

@MainActor
final class RoadmapStore: ObservableObject {
    static let containerIdentifier = "iCloud.com.fatties.readtime"

    @Published private(set) var requests: [FeatureRequest] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    /// False when there's no iCloud account on the device, which blocks the public database too.
    @Published private(set) var isSignedIn = true
    @Published var message: String?

    private let container = CKContainer(identifier: RoadmapStore.containerIdentifier)
    private var database: CKDatabase { container.publicCloudDatabase }
    private var userID: CKRecord.ID?

    func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        isSignedIn = (try? await container.accountStatus()) == .available
        userID = try? await container.userRecordID()
        do {
            // Fetch everything and hide only what's explicitly unlisted, so a record created
            // without `listed` still shows up.
            let features = try await fetchAll(CKQuery(recordType: "FeatureRequest", predicate: NSPredicate(value: true)))
                .filter { ($0["listed"] as? Int64) != 0 }
            let names = features.map(\.recordID.recordName)
            let votes = names.isEmpty ? [] : try await fetchAll(CKQuery(recordType: "Vote", predicate: NSPredicate(format: "featureName IN %@", names)))

            var counts: [String: Int] = [:]
            var mine: Set<String> = []
            for vote in votes {
                guard let name = vote["featureName"] as? String else { continue }
                counts[name, default: 0] += 1
                if let userID, vote.creatorUserRecordID?.recordName == userID.recordName
                    || vote.creatorUserRecordID?.recordName == CKCurrentUserDefaultName {
                    mine.insert(name)
                }
            }

            requests = features.map { record in
                let name = record.recordID.recordName
                return FeatureRequest(
                    id: name,
                    title: record["title"] as? String ?? "",
                    details: record["details"] as? String ?? "",
                    status: FeatureRequest.Status(rawValue: record["status"] as? String ?? "") ?? .inReview,
                    votes: counts[name] ?? 0,
                    hasVoted: mine.contains(name)
                )
            }
            .sorted { $0.votes == $1.votes ? $0.title < $1.title : $0.votes > $1.votes }
        } catch let error as CKError where error.code == .unknownItem {
            // The record types don't exist until the first record is saved.
            requests = []
        } catch {
            loadFailed = true
        }
    }

    func toggleVote(for request: FeatureRequest) async {
        guard let userID else {
            message = String(localized: "Sign in to iCloud in the Settings app to vote.")
            return
        }
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
        let recordID = CKRecord.ID(recordName: "vote-\(request.id)-\(userID.recordName)")
        let wasVoted = requests[index].hasVoted
        requests[index].hasVoted.toggle()
        requests[index].votes += wasVoted ? -1 : 1

        do {
            if wasVoted {
                try await database.deleteRecord(withID: recordID)
            } else {
                let vote = CKRecord(recordType: "Vote", recordID: recordID)
                vote["featureName"] = request.id
                try await database.save(vote)
            }
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .unknownItem {
            // Already voted (or already removed) on another device; the local state is now correct.
        } catch {
            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                requests[index].hasVoted = wasVoted
                requests[index].votes += wasVoted ? 1 : -1
            }
            message = error.localizedDescription
        }
    }

    func suggest(title: String, details: String) async -> Bool {
        guard userID != nil else {
            message = String(localized: "Sign in to iCloud in the Settings app to suggest a feature.")
            return false
        }
        let record = CKRecord(recordType: "FeatureRequest")
        record["title"] = title
        record["details"] = details
        record["status"] = FeatureRequest.Status.inReview.rawValue
        record["listed"] = 0 as Int64
        do {
            try await database.save(record)
            message = String(localized: "Thanks! Your suggestion will appear on the roadmap once it's been reviewed.")
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func fetchAll(_ query: CKQuery) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var (results, cursor) = try await database.records(matching: query)
        records += results.compactMap { try? $0.1.get() }
        while let next = cursor {
            (results, cursor) = try await database.records(continuingMatchFrom: next)
            records += results.compactMap { try? $0.1.get() }
        }
        return records
    }
}

enum ReferralReport {
    private static let sentKey = "onboarding_referral_sent"

    static func send(source: String) async {
        guard !UserDefaults.standard.bool(forKey: sentKey) else { return }
        let record = CKRecord(recordType: "ReferralAnswer")
        record["source"] = source
        record["appVersion"] = AppInfo.version
        do {
            try await CKContainer(identifier: RoadmapStore.containerIdentifier).publicCloudDatabase.save(record)
            UserDefaults.standard.set(true, forKey: sentKey)
        } catch {
            // Not worth interrupting onboarding; the answer stays on the device.
        }
    }
}

#else

// MARK: - Android: CloudKit Web Services REST client
//
// Skip has no CloudKit binding, so the Android side talks to the same public
// database directly over CloudKit Web Services (a plain HTTPS JSON API; see
// https://developer.apple.com/documentation/cloudkitjs and the CloudKit Web
// Services reference). This mirrors `CloudKit/schema.ckdb`'s `FeatureRequest`,
// `Vote`, and `ReferralAnswer` record types.
//
// TODO(android): `apiToken` below is the CloudKit Dashboard "API Token" (Server-to-Server
// Keys → API Access → Tokens), scoped to the public database. Anonymous public writes
// (voting, suggesting a feature, the referral answer) need "World" write permission granted
// on those record types in CloudKit Dashboard; if Apple requires request signing for writes
// in your container's configuration, replace `apiToken`-only auth below with a signed
// server-to-server key (ES256 over the request body + timestamp, per CloudKit Web Services'
// "Server-to-Server Authentication" docs) — this file's request-building is structured so
// that signing can be added as one extra header-building step without touching call sites.
private enum CloudKitWebServices {
    static let containerIdentifier = "iCloud.com.fatties.readtime"
    static let environment = "production" // or "development"
    static let apiToken = "" // TODO(android): fill in from CloudKit Dashboard.

    static var baseURL: URL {
        URL(string: "https://api.apple-cloudkit.com/database/1/\(containerIdentifier)/\(environment)/public")!
    }

    static func request(path: String, body: [String: Any]) async throws -> [String: Any] {
        var url = baseURL.appendingPathComponent(path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "ckAPIToken", value: apiToken)]
        url = components.url!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }

    static func fieldValue(_ record: [String: Any], _ key: String) -> Any? {
        (record["fields"] as? [String: Any])
            .flatMap { $0[key] as? [String: Any] }
            .flatMap { $0["value"] }
    }
}

@MainActor
final class RoadmapStore: ObservableObject {
    @Published private(set) var requests: [FeatureRequest] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    /// Android has no iCloud account concept; voting/suggesting relies only on the API token.
    @Published private(set) var isSignedIn = true
    @Published var message: String?

    /// Stable per-install identifier standing in for CloudKit's per-user `CKRecord.ID`,
    /// so a device's own votes are recognized on repeat visits without an Apple account.
    private lazy var deviceVoterID: String = {
        let key = "cloudkit_device_voter_id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }()

    func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let featureResponse = try await CloudKitWebServices.request(
                path: "records/query",
                body: ["query": ["recordType": "FeatureRequest"]]
            )
            let featureRecords = (featureResponse["records"] as? [[String: Any]]) ?? []
            let features = featureRecords
                .filter { (CloudKitWebServices.fieldValue($0, "listed") as? Int ?? 1) != 0 }
                .map { record -> FeatureRequest in
                    let name = record["recordName"] as? String ?? UUID().uuidString
                    return FeatureRequest(
                        id: name,
                        title: CloudKitWebServices.fieldValue(record, "title") as? String ?? "",
                        details: CloudKitWebServices.fieldValue(record, "details") as? String ?? "",
                        status: FeatureRequest.Status(rawValue: CloudKitWebServices.fieldValue(record, "status") as? String ?? "") ?? .inReview,
                        votes: 0,
                        hasVoted: false
                    )
                }

            let names = features.map(\.id)
            var counts: [String: Int] = [:]
            var mine: Set<String> = []
            if !names.isEmpty {
                let voteResponse = try await CloudKitWebServices.request(
                    path: "records/query",
                    body: ["query": [
                        "recordType": "Vote",
                        "filterBy": [["fieldName": "featureName", "comparator": "IN", "fieldValue": ["value": names]]]
                    ]]
                )
                let voteRecords = (voteResponse["records"] as? [[String: Any]]) ?? []
                for vote in voteRecords {
                    guard let name = CloudKitWebServices.fieldValue(vote, "featureName") as? String else { continue }
                    counts[name, default: 0] += 1
                    if CloudKitWebServices.fieldValue(vote, "voterID") as? String == deviceVoterID {
                        mine.insert(name)
                    }
                }
            }

            requests = features.map { feature in
                var updated = feature
                updated.votes = counts[feature.id] ?? 0
                updated.hasVoted = mine.contains(feature.id)
                return updated
            }
            .sorted { $0.votes == $1.votes ? $0.title < $1.title : $0.votes > $1.votes }
        } catch {
            loadFailed = true
        }
    }

    func toggleVote(for request: FeatureRequest) async {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
        let recordName = "vote-\(request.id)-\(deviceVoterID)"
        let wasVoted = requests[index].hasVoted
        requests[index].hasVoted.toggle()
        requests[index].votes += wasVoted ? -1 : 1

        do {
            if wasVoted {
                _ = try await CloudKitWebServices.request(
                    path: "records/modify",
                    body: ["operations": [["operationType": "forceDelete", "record": ["recordName": recordName]]]]
                )
            } else {
                _ = try await CloudKitWebServices.request(
                    path: "records/modify",
                    body: ["operations": [[
                        "operationType": "create",
                        "record": [
                            "recordName": recordName,
                            "recordType": "Vote",
                            "fields": [
                                "featureName": ["value": request.id],
                                "voterID": ["value": deviceVoterID]
                            ]
                        ]
                    ]]]
                )
            }
        } catch {
            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                requests[index].hasVoted = wasVoted
                requests[index].votes += wasVoted ? 1 : -1
            }
            message = error.localizedDescription
        }
    }

    func suggest(title: String, details: String) async -> Bool {
        do {
            _ = try await CloudKitWebServices.request(
                path: "records/modify",
                body: ["operations": [[
                    "operationType": "create",
                    "record": [
                        "recordType": "FeatureRequest",
                        "fields": [
                            "title": ["value": title],
                            "details": ["value": details],
                            "status": ["value": FeatureRequest.Status.inReview.rawValue],
                            "listed": ["value": 0]
                        ]
                    ]
                ]]]
            )
            message = String(localized: "Thanks! Your suggestion will appear on the roadmap once it's been reviewed.")
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}

enum ReferralReport {
    private static let sentKey = "onboarding_referral_sent"

    static func send(source: String) async {
        guard !UserDefaults.standard.bool(forKey: sentKey) else { return }
        do {
            _ = try await CloudKitWebServices.request(
                path: "records/modify",
                body: ["operations": [[
                    "operationType": "create",
                    "record": [
                        "recordType": "ReferralAnswer",
                        "fields": [
                            "source": ["value": source],
                            "appVersion": ["value": AppInfo.version]
                        ]
                    ]
                ]]]
            )
            UserDefaults.standard.set(true, forKey: sentKey)
        } catch {
            // Not worth interrupting onboarding; the answer stays on the device.
        }
    }
}

#endif
