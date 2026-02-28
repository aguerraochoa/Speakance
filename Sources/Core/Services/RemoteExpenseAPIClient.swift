import Foundation

struct SupabaseFunctionExpenseAPIClient: ExpenseAPIClientProtocol {
    let config: SupabaseAppConfig
    var accessTokenProvider: @Sendable () async -> String?
    var session: URLSession = .shared
    var voiceCapturesBucket = "voice-captures"

    func parseExpense(_ request: ParseExpenseRequestDTO) async throws -> ParseExpenseResponseDTO {
        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else {
            throw ExpenseAPIError.missingAuthSession
        }
        let url = try makeFunctionsURL()

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let uploadedVoiceObject = try await uploadVoiceCaptureIfNeeded(for: request, accessToken: accessToken)
        let payload = SupabaseParseExpenseRequestPayload(
            from: request,
            storageBucket: uploadedVoiceObject?.bucket,
            storageObjectPath: uploadedVoiceObject?.objectPath
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        urlRequest.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ExpenseAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        let apiResponse: SupabaseParseExpenseResponsePayload
        do {
            apiResponse = try decoder.decode(SupabaseParseExpenseResponsePayload.self, from: data)
        } catch {
            throw ExpenseAPIError.server("Unexpected server response. \(error.localizedDescription)")
        }

        switch http.statusCode {
        case 200 where apiResponse.status == "saved" || apiResponse.status == "needs_review":
            let parsed = apiResponse.parse
            let parseConfidence = parsed?.confidence ?? (apiResponse.status == "saved" ? 0.95 : 0.5)
            let parseRawText = (parsed?.rawText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? parsed?.rawText
                : request.rawText)
                ?? ""
            if parsed == nil || apiResponse.parse?.confidence == nil || apiResponse.parse?.rawText == nil {
            }
            guard let expense = apiResponse.expense else {
                throw ExpenseAPIError.server("Missing expense payload")
            }
            guard
                let serverClientExpenseID = expense.clientExpenseId,
                let serverAmount = expense.amount,
                let serverCurrency = expense.currency,
                let serverCategory = expense.category,
                let serverExpenseDate = expense.expenseDate
            else {
                throw ExpenseAPIError.server("Server expense payload is incomplete.")
            }

            let draft = ExpenseDraft(
                clientExpenseID: UUID(uuidString: serverClientExpenseID) ?? request.clientExpenseID,
                amountText: formatAmountString(serverAmount),
                currency: serverCurrency,
                category: serverCategory,
                categoryID: expense.categoryId.flatMap(UUID.init(uuidString:)),
                description: expense.description ?? request.rawText,
                merchant: expense.merchant ?? "",
                tripID: expense.tripId.flatMap(UUID.init(uuidString:)) ?? request.tripID,
                tripName: expense.tripName ?? request.tripName,
                paymentMethodID: expense.paymentMethodId.flatMap(UUID.init(uuidString:)) ?? request.paymentMethodID,
                paymentMethodName: expense.paymentMethodName ?? request.paymentMethodName,
                expenseDate: try parseServerDate(serverExpenseDate),
                rawText: parseRawText,
                source: request.source,
                parseConfidence: parseConfidence
            )

            let status: QueueStatus = apiResponse.status == "saved" ? .saved : .needsReview
            return ParseExpenseResponseDTO(
                status: status,
                draft: draft,
                serverExpenseID: expense.id.flatMap(UUID.init(uuidString:))
            )

        case 401:
            throw ExpenseAPIError.unauthorized
        case 429:
            throw ExpenseAPIError.limitExceeded(apiResponse.error ?? "Daily voice limit reached")
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ExpenseAPIError.server(apiResponse.error ?? apiResponse.message ?? (body.isEmpty ? "Unexpected server error" : body))
        }
    }

    func updateExpense(_ request: UpdateExpenseRequestDTO) async throws {
        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else {
            throw ExpenseAPIError.missingAuthSession
        }

        var urlRequest = URLRequest(url: try makeRestURL(path: "expenses", queryItems: [
            URLQueryItem(name: "id", value: "eq.\(request.expenseID.uuidString)"),
            URLQueryItem(name: "select", value: "id"),
        ]))
        urlRequest.httpMethod = "PATCH"
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("representation", forHTTPHeaderField: "Prefer")
        urlRequest.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let payload = ExpenseUpdatePayload(from: request)
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ExpenseAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw ExpenseAPIError.unauthorized }
            throw ExpenseAPIError.server(String(data: data, encoding: .utf8) ?? "Failed to update expense")
        }
    }

    func deleteExpense(_ expenseID: UUID) async throws {
        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else {
            throw ExpenseAPIError.missingAuthSession
        }

        var urlRequest = URLRequest(url: try makeRestURL(path: "expenses", queryItems: [
            URLQueryItem(name: "id", value: "eq.\(expenseID.uuidString)"),
            URLQueryItem(name: "select", value: "id"),
        ]))
        urlRequest.httpMethod = "DELETE"
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ExpenseAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw ExpenseAPIError.unauthorized }
            throw ExpenseAPIError.server(String(data: data, encoding: .utf8) ?? "Failed to delete expense")
        }
    }

    func syncMetadata(_ snapshot: UserMetadataSyncSnapshotDTO) async throws {
        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else {
            throw ExpenseAPIError.missingAuthSession
        }

        try await syncProfilePreferences(snapshot, accessToken: accessToken)
        let remoteSnapshot = try await fetchMetadataInternal(accessToken: accessToken)
        try await syncCategories(snapshot.categories, remote: remoteSnapshot.categories, accessToken: accessToken)
        try await syncTrips(snapshot.trips, remote: remoteSnapshot.trips, accessToken: accessToken)
        try await syncPaymentMethods(snapshot.paymentMethods, remote: remoteSnapshot.paymentMethods, accessToken: accessToken)
    }

    func fetchMetadata() async throws -> UserMetadataSyncSnapshotDTO? {
        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else { return nil }
        return try await fetchMetadataInternal(accessToken: accessToken)
    }

    func fetchExpenses() async throws -> [ExpenseRecord] {
        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else { return [] }
        let decoder = makeSupabaseDecoder()
        var request = makeJSONRequest(
            url: try makeRestURL(path: "expenses", queryItems: [
                URLQueryItem(name: "select", value: "id,client_expense_id,amount,currency,category,category_id,description,merchant,trip_id,trip_name,payment_method_id,payment_method_name,expense_date,captured_at_device,synced_at,source,parse_status,parse_confidence,raw_text,audio_duration_seconds,created_at,updated_at"),
                URLQueryItem(name: "order", value: "expense_date.desc,updated_at.desc"),
            ]),
            accessToken: accessToken
        )
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateREST(response: response, data: data)
        let rows = try decoder.decode([RESTExpense].self, from: data)
        return rows.compactMap(\.asModel)
    }

    private func parseServerDate(_ value: String) throws -> Date {
        if let date = DateOnlyFormatter.shared.date(from: value) {
            return date
        }
        throw ExpenseAPIError.server("Invalid expense_date from server")
    }

    private func makeFunctionsURL() throws -> URL {
        guard var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) else {
            throw ExpenseAPIError.server("Invalid Supabase URL")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "functions", "v1", "parse-expense"]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        guard let url = components.url else {
            throw ExpenseAPIError.server("Invalid Supabase function URL")
        }
        return url
    }

    private func makeRestURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) else {
            throw ExpenseAPIError.server("Invalid Supabase URL")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "rest", "v1", path]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw ExpenseAPIError.server("Invalid Supabase rest URL")
        }
        return url
    }

    private func makeJSONRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func uploadVoiceCaptureIfNeeded(
        for request: ParseExpenseRequestDTO,
        accessToken: String
    ) async throws -> UploadedVoiceObject? {
        guard request.source == .voice else { return nil }
        guard let localPath = request.localAudioFilePath, !localPath.isEmpty else { return nil }

        let fileURL = URL(fileURLWithPath: localPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // Recover old/stale voice queue items by falling back to the stored text transcript/placeholder.
            if !request.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            throw ExpenseAPIError.server("Recorded audio file is missing.")
        }

        guard let userID = jwtSubject(from: accessToken) else {
            throw ExpenseAPIError.unauthorized
        }

        let objectPath = makeVoiceObjectPath(
            userID: userID,
            capturedAt: request.capturedAtDevice,
            clientExpenseID: request.clientExpenseID,
            preferredExtension: fileURL.pathExtension
        )

        let data = try await readAudioFileDataWithRetry(fileURL)

        var uploadRequest = URLRequest(url: try makeStorageObjectURL(bucket: voiceCapturesBucket, objectPath: objectPath))
        uploadRequest.httpMethod = "POST"
        uploadRequest.timeoutInterval = 30
        uploadRequest.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        uploadRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        uploadRequest.setValue(contentType(for: fileURL), forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue("true", forHTTPHeaderField: "x-upsert")
        let (responseData, response) = try await session.upload(for: uploadRequest, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw ExpenseAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: responseData, encoding: .utf8) ?? "Upload failed"
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ExpenseAPIError.unauthorized
            }
            throw ExpenseAPIError.server("Voice upload failed: \(body)")
        }

        return UploadedVoiceObject(bucket: voiceCapturesBucket, objectPath: objectPath)
    }

    private func makeStorageObjectURL(bucket: String, objectPath: String) throws -> URL {
        guard var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) else {
            throw ExpenseAPIError.server("Invalid Supabase URL")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedPath = objectPath
            .split(separator: "/")
            .map { segment in
                String(segment).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "/")
        components.path = "/" + [basePath, "storage", "v1", "object", bucket, encodedPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        guard let url = components.url else {
            throw ExpenseAPIError.server("Invalid Supabase storage URL")
        }
        return url
    }

    private func contentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        case "aac":
            return "audio/aac"
        default:
            return "application/octet-stream"
        }
    }

    private func readAudioFileDataWithRetry(_ fileURL: URL) async throws -> Data {
        let minimumExpectedBytes = 1_024
        let maxAttempts = 8
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let data = try Data(contentsOf: fileURL)
                if data.count >= minimumExpectedBytes || attempt == maxAttempts {
                    return data
                }
            } catch {
                lastError = error
            }
            try? await Task.sleep(for: .milliseconds(120))
        }

        if let lastError {
            throw ExpenseAPIError.server("Could not read local audio file for upload. \(lastError.localizedDescription)")
        }
        throw ExpenseAPIError.server("Recorded audio file is empty or incomplete.")
    }

    private func makeVoiceObjectPath(
        userID: String,
        capturedAt: Date,
        clientExpenseID: UUID,
        preferredExtension: String
    ) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0) ?? .current, from: capturedAt)
        let year = comps.year ?? 1970
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let ext = preferredExtension.isEmpty ? "m4a" : preferredExtension.lowercased()
        return "\(userID)/\(String(format: "%04d", year))/\(String(format: "%02d", month))/\(String(format: "%02d", day))/\(clientExpenseID.uuidString).\(ext)"
    }

    private func jwtSubject(from accessToken: String) -> String? {
        jwtPayload(from: accessToken)?["sub"] as? String
    }

    private func jwtPayload(from token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        let payloadSegment = String(segments[1])
        guard
            let data = base64URLDecode(payloadSegment),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json
    }

    private func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    private func formatAmountString(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue
    }

    private func fetchMetadataInternal(accessToken: String) async throws -> UserMetadataSyncSnapshotDTO {
        async let profileTask = fetchProfile(accessToken: accessToken)
        async let categoriesTask = fetchCategories(accessToken: accessToken)
        async let tripsTask = fetchTrips(accessToken: accessToken)
        async let paymentMethodsTask = fetchPaymentMethods(accessToken: accessToken)
        let (profile, categories, trips, paymentMethods) = try await (profileTask, categoriesTask, tripsTask, paymentMethodsTask)
        let activeTripID = trips.first(where: { $0.status == .active })?.id
        return UserMetadataSyncSnapshotDTO(
            categories: categories,
            trips: trips,
            paymentMethods: paymentMethods,
            activeTripID: activeTripID,
            defaultCurrencyCode: profile?.defaultCurrency,
            dailyVoiceLimit: profile?.dailyVoiceLimit
        )
    }

    private func fetchProfile(accessToken: String) async throws -> RESTProfile? {
        guard let userID = jwtSubject(from: accessToken) else { throw ExpenseAPIError.unauthorized }
        let decoder = makeSupabaseDecoder()
        var request = makeJSONRequest(
            url: try makeRestURL(path: "profiles", queryItems: [
                URLQueryItem(name: "select", value: "id,default_currency,daily_voice_limit"),
                URLQueryItem(name: "id", value: "eq.\(userID)"),
                URLQueryItem(name: "limit", value: "1"),
            ]),
            accessToken: accessToken
        )
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateREST(response: response, data: data)
        return try decoder.decode([RESTProfile].self, from: data).first
    }

    private func fetchCategories(accessToken: String) async throws -> [CategoryDefinition] {
        let decoder = makeSupabaseDecoder()
        var request = makeJSONRequest(
            url: try makeRestURL(path: "categories", queryItems: [
                URLQueryItem(name: "select", value: "id,name,color_hex,is_default,created_at"),
                URLQueryItem(name: "order", value: "is_default.desc,name.asc"),
            ]),
            accessToken: accessToken
        )
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateREST(response: response, data: data)
        let categories = try decoder.decode([RESTCategory].self, from: data)

        var hintRequest = makeJSONRequest(
            url: try makeRestURL(path: "category_hints", queryItems: [
                URLQueryItem(name: "select", value: "category_id,phrase"),
            ]),
            accessToken: accessToken
        )
        hintRequest.httpMethod = "GET"
        let (hintData, hintResponse) = try await session.data(for: hintRequest)
        try validateREST(response: hintResponse, data: hintData)
        let hints = try decoder.decode([RESTCategoryHint].self, from: hintData)
        let hintsByCategory = Dictionary(grouping: hints, by: \.categoryID)

        return categories.compactMap { row in
            guard let id = UUID(uuidString: row.id) else { return nil }
            return CategoryDefinition(
                id: id,
                name: row.name,
                colorHex: row.colorHex,
                isDefault: row.isDefault,
                hintKeywords: (hintsByCategory[row.id] ?? []).map(\.phrase).sorted(),
                createdAt: row.createdAt ?? .now
            )
        }
    }

    private func fetchTrips(accessToken: String) async throws -> [TripRecord] {
        let decoder = makeSupabaseDecoder()
        var request = makeJSONRequest(
            url: try makeRestURL(path: "trips", queryItems: [
                URLQueryItem(name: "select", value: "id,name,destination,start_date,end_date,base_currency,status,created_at"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]),
            accessToken: accessToken
        )
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateREST(response: response, data: data)
        let rows = try decoder.decode([RESTTrip].self, from: data)
        return rows.compactMap { $0.asModel }
    }

    private func fetchPaymentMethods(accessToken: String) async throws -> [PaymentMethod] {
        let decoder = makeSupabaseDecoder()
        var request = makeJSONRequest(
            url: try makeRestURL(path: "payment_methods", queryItems: [
                URLQueryItem(name: "select", value: "id,name,method_type,network,last4,color_hex,is_default,is_active,created_at"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]),
            accessToken: accessToken
        )
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validateREST(response: response, data: data)
        let methods = try decoder.decode([RESTPaymentMethod].self, from: data)

        var aliasRequest = makeJSONRequest(
            url: try makeRestURL(path: "payment_method_aliases", queryItems: [
                URLQueryItem(name: "select", value: "payment_method_id,phrase"),
            ]),
            accessToken: accessToken
        )
        aliasRequest.httpMethod = "GET"
        let (aliasData, aliasResponse) = try await session.data(for: aliasRequest)
        try validateREST(response: aliasResponse, data: aliasData)
        let aliases = try decoder.decode([RESTPaymentMethodAlias].self, from: aliasData)
        let aliasesByMethod = Dictionary(grouping: aliases, by: \.paymentMethodID)

        return methods.compactMap { row in
            guard let id = UUID(uuidString: row.id) else { return nil }
            return PaymentMethod(
                id: id,
                name: row.name,
                network: row.network,
                last4: row.last4,
                aliases: (aliasesByMethod[row.id] ?? []).map(\.phrase).sorted(),
                isDefault: row.isDefault,
                isActive: row.isActive,
                createdAt: row.createdAt ?? .now
            )
        }
    }

    private func syncCategories(
        _ local: [CategoryDefinition],
        remote: [CategoryDefinition],
        accessToken: String
    ) async throws {
        guard let userID = jwtSubject(from: accessToken) else { throw ExpenseAPIError.unauthorized }
        let localIDs = Set(local.map(\.id))
        let remoteCustomIDs = Set(remote.filter { !$0.isDefault }.map(\.id))
        let deleteIDs = remoteCustomIDs.subtracting(localIDs)
        if !deleteIDs.isEmpty {
            var deleteReq = makeJSONRequest(
                url: try makeRestURL(path: "categories", queryItems: [
                    URLQueryItem(name: "id", value: "in.(\(deleteIDs.map(\.uuidString).joined(separator: ",")))"),
                ]),
                accessToken: accessToken
            )
            deleteReq.httpMethod = "DELETE"
            let (data, response) = try await session.data(for: deleteReq)
            try validateREST(response: response, data: data)
        }

        let customCategories = local.filter { !$0.isDefault }.map { RESTCategoryUpsert($0, userID: userID) }
        if !customCategories.isEmpty {
            var upsertReq = makeJSONRequest(
                url: try makeRestURL(path: "categories", queryItems: [
                    URLQueryItem(name: "on_conflict", value: "id"),
                ]),
                accessToken: accessToken
            )
            upsertReq.httpMethod = "POST"
            upsertReq.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
            upsertReq.httpBody = try JSONEncoder().encode(customCategories)
            let (data, response) = try await session.data(for: upsertReq)
            try validateREST(response: response, data: data)
        }

        try await replaceCategoryHints(localCategories: local, accessToken: accessToken, userID: userID)
    }

    private func replaceCategoryHints(localCategories: [CategoryDefinition], accessToken: String, userID: String) async throws {
        var deleteReq = makeJSONRequest(url: try makeRestURL(path: "category_hints"), accessToken: accessToken)
        deleteReq.httpMethod = "DELETE"
        let (deleteData, deleteResponse) = try await session.data(for: deleteReq)
        try validateREST(response: deleteResponse, data: deleteData)

        let rows = localCategories
            .flatMap { category in
                category.hintKeywords.map { hint in
                    RESTCategoryHintUpsert(categoryID: category.id.uuidString, phrase: hint, normalizedPhrase: hint.lowercased())
                        .withUserID(userID)
                }
            }
        guard !rows.isEmpty else { return }
        var insertReq = makeJSONRequest(url: try makeRestURL(path: "category_hints"), accessToken: accessToken)
        insertReq.httpMethod = "POST"
        insertReq.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        insertReq.httpBody = try JSONEncoder().encode(rows)
        let (data, response) = try await session.data(for: insertReq)
        try validateREST(response: response, data: data)
    }

    private func syncTrips(_ local: [TripRecord], remote: [TripRecord], accessToken: String) async throws {
        guard let userID = jwtSubject(from: accessToken) else { throw ExpenseAPIError.unauthorized }
        let localIDs = Set(local.map(\.id))
        let remoteIDs = Set(remote.map(\.id))
        let deleteIDs = remoteIDs.subtracting(localIDs)
        if !deleteIDs.isEmpty {
            var deleteReq = makeJSONRequest(
                url: try makeRestURL(path: "trips", queryItems: [URLQueryItem(name: "id", value: "in.(\(deleteIDs.map(\.uuidString).joined(separator: ",")))")]),
                accessToken: accessToken
            )
            deleteReq.httpMethod = "DELETE"
            let (data, response) = try await session.data(for: deleteReq)
            try validateREST(response: response, data: data)
        }

        guard !local.isEmpty else { return }
        var upsertReq = makeJSONRequest(
            url: try makeRestURL(path: "trips", queryItems: [URLQueryItem(name: "on_conflict", value: "id")]),
            accessToken: accessToken
        )
        upsertReq.httpMethod = "POST"
        upsertReq.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        upsertReq.httpBody = try JSONEncoder().encode(local.map { RESTTripUpsert($0, userID: userID) })
        let (data, response) = try await session.data(for: upsertReq)
        try validateREST(response: response, data: data)
    }

    private func syncPaymentMethods(
        _ local: [PaymentMethod],
        remote: [PaymentMethod],
        accessToken: String
    ) async throws {
        guard let userID = jwtSubject(from: accessToken) else { throw ExpenseAPIError.unauthorized }
        let localIDs = Set(local.map(\.id))
        let remoteIDs = Set(remote.map(\.id))
        let deleteIDs = remoteIDs.subtracting(localIDs)
        if !deleteIDs.isEmpty {
            var deleteReq = makeJSONRequest(
                url: try makeRestURL(path: "payment_methods", queryItems: [URLQueryItem(name: "id", value: "in.(\(deleteIDs.map(\.uuidString).joined(separator: ",")))")]),
                accessToken: accessToken
            )
            deleteReq.httpMethod = "DELETE"
            let (data, response) = try await session.data(for: deleteReq)
            try validateREST(response: response, data: data)
        }

        if !local.isEmpty {
            var upsertReq = makeJSONRequest(
                url: try makeRestURL(path: "payment_methods", queryItems: [URLQueryItem(name: "on_conflict", value: "id")]),
                accessToken: accessToken
            )
            upsertReq.httpMethod = "POST"
            upsertReq.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
            upsertReq.httpBody = try JSONEncoder().encode(local.map { RESTPaymentMethodUpsert($0, userID: userID) })
            let (data, response) = try await session.data(for: upsertReq)
            try validateREST(response: response, data: data)
        }

        var deleteAliasesReq = makeJSONRequest(url: try makeRestURL(path: "payment_method_aliases"), accessToken: accessToken)
        deleteAliasesReq.httpMethod = "DELETE"
        let (deleteData, deleteResponse) = try await session.data(for: deleteAliasesReq)
        try validateREST(response: deleteResponse, data: deleteData)

        let aliasRows = local.flatMap { method in
            method.aliases.map {
                    RESTPaymentMethodAliasUpsert(
                        paymentMethodID: method.id.uuidString,
                        phrase: $0,
                        normalizedPhrase: $0.lowercased()
                    ).withUserID(userID)
                }
            }
        guard !aliasRows.isEmpty else { return }
        var insertReq = makeJSONRequest(url: try makeRestURL(path: "payment_method_aliases"), accessToken: accessToken)
        insertReq.httpMethod = "POST"
        insertReq.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        insertReq.httpBody = try JSONEncoder().encode(aliasRows)
        let (data, response) = try await session.data(for: insertReq)
        try validateREST(response: response, data: data)
    }

    private func syncProfilePreferences(_ snapshot: UserMetadataSyncSnapshotDTO, accessToken: String) async throws {
        guard let userID = jwtSubject(from: accessToken) else { throw ExpenseAPIError.unauthorized }
        let currency = (snapshot.defaultCurrencyCode ?? "USD")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let dailyVoiceLimit = snapshot.dailyVoiceLimit

        var upsertReq = makeJSONRequest(
            url: try makeRestURL(path: "profiles", queryItems: [URLQueryItem(name: "on_conflict", value: "id")]),
            accessToken: accessToken
        )
        upsertReq.httpMethod = "POST"
        upsertReq.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        upsertReq.httpBody = try JSONEncoder().encode([RESTProfileUpsert(id: userID, defaultCurrency: currency, dailyVoiceLimit: dailyVoiceLimit)])
        let (data, response) = try await session.data(for: upsertReq)
        try validateREST(response: response, data: data)
    }

    private func validateREST(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ExpenseAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw ExpenseAPIError.unauthorized }
            throw ExpenseAPIError.server(String(data: data, encoding: .utf8) ?? "Supabase REST request failed")
        }
    }

    private func makeSupabaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = fractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(raw)")
        }
        return decoder
    }
}

private struct UploadedVoiceObject {
    let bucket: String
    let objectPath: String
}

struct FallbackExpenseAPIClient: ExpenseAPIClientProtocol {
    let primary: ExpenseAPIClientProtocol
    let fallback: ExpenseAPIClientProtocol

    func parseExpense(_ request: ParseExpenseRequestDTO) async throws -> ParseExpenseResponseDTO {
        do {
            return try await primary.parseExpense(request)
        } catch ExpenseAPIError.missingAuthSession {
            return try await fallback.parseExpense(request)
        } catch ExpenseAPIError.unauthorized {
            return try await fallback.parseExpense(request)
        }
    }

    func updateExpense(_ request: UpdateExpenseRequestDTO) async throws {
        do {
            try await primary.updateExpense(request)
        } catch ExpenseAPIError.missingAuthSession {
            return
        } catch ExpenseAPIError.unauthorized {
            return
        }
    }

    func deleteExpense(_ expenseID: UUID) async throws {
        do {
            try await primary.deleteExpense(expenseID)
        } catch ExpenseAPIError.missingAuthSession {
            return
        } catch ExpenseAPIError.unauthorized {
            return
        }
    }

    func syncMetadata(_ snapshot: UserMetadataSyncSnapshotDTO) async throws {
        do {
            try await primary.syncMetadata(snapshot)
        } catch ExpenseAPIError.missingAuthSession {
            return
        } catch ExpenseAPIError.unauthorized {
            return
        }
    }

    func fetchMetadata() async throws -> UserMetadataSyncSnapshotDTO? {
        do {
            return try await primary.fetchMetadata()
        } catch ExpenseAPIError.missingAuthSession {
            return nil
        } catch ExpenseAPIError.unauthorized {
            return nil
        }
    }

    func fetchExpenses() async throws -> [ExpenseRecord] {
        do {
            return try await primary.fetchExpenses()
        } catch ExpenseAPIError.missingAuthSession {
            return []
        } catch ExpenseAPIError.unauthorized {
            return []
        }
    }
}

enum ExpenseAPIError: LocalizedError {
    case missingAuthSession
    case unauthorized
    case invalidResponse
    case server(String)
    case limitExceeded(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthSession:
            return "Sign in is required before syncing to the server."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .invalidResponse:
            return "The server returned an invalid response."
        case let .server(message):
            return message
        case let .limitExceeded(message):
            return message
        }
    }
}

private struct SupabaseParseExpenseRequestPayload: Encodable {
    let clientExpenseId: String
    let source: String
    let capturedAtDevice: Date
    let timezone: String
    let audioDurationSeconds: Int?
    let rawText: String
    let currencyHint: String?
    let languageHint: String?
    let allowAutoSave: Bool
    let storageBucket: String?
    let storageObjectPath: String?
    let tripId: String?
    let tripName: String?
    let paymentMethodId: String?
    let paymentMethodName: String?

    init(from dto: ParseExpenseRequestDTO, storageBucket: String?, storageObjectPath: String?) {
        clientExpenseId = dto.clientExpenseID.uuidString
        source = dto.source.rawValue
        capturedAtDevice = dto.capturedAtDevice
        timezone = dto.timezone
        audioDurationSeconds = dto.audioDurationSeconds
        rawText = dto.rawText
        currencyHint = dto.currencyHint
        languageHint = dto.languageHint
        allowAutoSave = true
        self.storageBucket = storageBucket
        self.storageObjectPath = storageObjectPath
        tripId = dto.tripID?.uuidString
        tripName = dto.tripName
        paymentMethodId = dto.paymentMethodID?.uuidString
        paymentMethodName = dto.paymentMethodName
    }

    enum CodingKeys: String, CodingKey {
        case clientExpenseId = "client_expense_id"
        case source
        case capturedAtDevice = "captured_at_device"
        case timezone
        case audioDurationSeconds = "audio_duration_seconds"
        case rawText = "raw_text"
        case currencyHint = "currency_hint"
        case languageHint = "language_hint"
        case allowAutoSave = "allow_auto_save"
        case storageBucket = "storage_bucket"
        case storageObjectPath = "storage_object_path"
        case tripId = "trip_id"
        case tripName = "trip_name"
        case paymentMethodId = "payment_method_id"
        case paymentMethodName = "payment_method_name"
    }
}

private struct SupabaseParseExpenseResponsePayload: Decodable {
    let status: String?
    let expense: ExpensePayload?
    let parse: ParsePayload?
    let error: String?
    let message: String?

    struct ExpensePayload: Decodable {
        let id: String?
        let clientExpenseId: String?
        let amount: Decimal?
        let currency: String?
        let category: String?
        let categoryId: String?
        let description: String?
        let merchant: String?
        let expenseDate: String?
        let source: String?
        let parseStatus: String?
        let tripId: String?
        let tripName: String?
        let paymentMethodId: String?
        let paymentMethodName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case clientExpenseId = "client_expense_id"
            case amount
            case currency
            case category
            case categoryId = "category_id"
            case description
            case merchant
            case expenseDate = "expense_date"
            case source
            case parseStatus = "parse_status"
            case tripId = "trip_id"
            case tripName = "trip_name"
            case paymentMethodId = "payment_method_id"
            case paymentMethodName = "payment_method_name"
        }
    }

    struct ParsePayload: Decodable {
        let confidence: Double?
        let rawText: String?
        let needsReview: Bool?

        enum CodingKeys: String, CodingKey {
            case confidence
            case rawText = "raw_text"
            case needsReview = "needs_review"
        }
    }

    enum CodingKeys: String, CodingKey {
        case status
        case expense
        case parse
        case error
        case message
    }
}

private struct ExpenseUpdatePayload: Encodable {
    let amount: Decimal
    let currency: String
    let category: String
    let categoryId: String?
    let description: String?
    let merchant: String?
    let expenseDate: String
    let parseStatus: String
    let parseConfidence: Double?
    let rawText: String?
    let tripId: String?
    let tripName: String?
    let paymentMethodId: String?
    let paymentMethodName: String?

    init(from request: UpdateExpenseRequestDTO) {
        let draft = request.draft
        amount = Decimal(string: draft.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        currency = draft.currency.uppercased()
        category = draft.category
        categoryId = draft.categoryID?.uuidString
        description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.description
        merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.merchant
        expenseDate = DateOnlyFormatter.shared.string(from: draft.expenseDate)
        parseStatus = "edited"
        parseConfidence = draft.parseConfidence
        rawText = draft.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.rawText
        tripId = draft.tripID?.uuidString
        tripName = draft.tripName
        paymentMethodId = draft.paymentMethodID?.uuidString
        paymentMethodName = draft.paymentMethodName
    }

    enum CodingKeys: String, CodingKey {
        case amount, currency, category, description, merchant
        case categoryId = "category_id"
        case expenseDate = "expense_date"
        case parseStatus = "parse_status"
        case parseConfidence = "parse_confidence"
        case rawText = "raw_text"
        case tripId = "trip_id"
        case tripName = "trip_name"
        case paymentMethodId = "payment_method_id"
        case paymentMethodName = "payment_method_name"
    }
}

private struct RESTCategory: Decodable {
    let id: String
    let name: String
    let colorHex: String?
    let isDefault: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color_hex"
        case isDefault = "is_default"
        case createdAt = "created_at"
    }
}

private struct RESTProfile: Decodable {
    let id: String
    let defaultCurrency: String?
    let dailyVoiceLimit: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case defaultCurrency = "default_currency"
        case dailyVoiceLimit = "daily_voice_limit"
    }
}

private struct RESTProfileUpsert: Encodable {
    let id: String
    let defaultCurrency: String
    let dailyVoiceLimit: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case defaultCurrency = "default_currency"
        case dailyVoiceLimit = "daily_voice_limit"
    }
}

private struct RESTExpense: Decodable {
    let id: String
    let clientExpenseID: String
    let amount: Decimal
    let currency: String
    let category: String
    let categoryID: String?
    let description: String?
    let merchant: String?
    let tripID: String?
    let tripName: String?
    let paymentMethodID: String?
    let paymentMethodName: String?
    let expenseDate: String
    let capturedAtDevice: Date?
    let syncedAt: Date?
    let source: String
    let parseStatus: String
    let parseConfidence: Double?
    let rawText: String?
    let audioDurationSeconds: Int?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case clientExpenseID = "client_expense_id"
        case amount, currency, category, description, merchant, source
        case categoryID = "category_id"
        case tripID = "trip_id"
        case tripName = "trip_name"
        case paymentMethodID = "payment_method_id"
        case paymentMethodName = "payment_method_name"
        case expenseDate = "expense_date"
        case capturedAtDevice = "captured_at_device"
        case syncedAt = "synced_at"
        case parseStatus = "parse_status"
        case parseConfidence = "parse_confidence"
        case rawText = "raw_text"
        case audioDurationSeconds = "audio_duration_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var asModel: ExpenseRecord? {
        guard
            let id = UUID(uuidString: id),
            let clientExpenseID = UUID(uuidString: clientExpenseID),
            let date = DateOnlyFormatter.shared.date(from: expenseDate)
        else { return nil }

        let created = createdAt ?? .now
        let updated = updatedAt ?? created
        return ExpenseRecord(
            id: id,
            clientExpenseID: clientExpenseID,
            amount: amount,
            currency: currency,
            category: category,
            categoryID: categoryID.flatMap(UUID.init(uuidString:)),
            description: description,
            merchant: merchant,
            tripID: tripID.flatMap(UUID.init(uuidString:)),
            tripName: tripName,
            paymentMethodID: paymentMethodID.flatMap(UUID.init(uuidString:)),
            paymentMethodName: paymentMethodName,
            expenseDate: date,
            capturedAtDevice: capturedAtDevice ?? created,
            syncedAt: syncedAt,
            source: ExpenseSource(rawValue: source) ?? .text,
            parseStatus: ParseStatus(rawValue: parseStatus) ?? .auto,
            parseConfidence: parseConfidence,
            rawText: rawText,
            audioDurationSeconds: audioDurationSeconds,
            createdAt: created,
            updatedAt: updated
        )
    }
}

private struct RESTCategoryHint: Decodable {
    let categoryID: String
    let phrase: String

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case phrase
    }
}

private struct RESTTrip: Decodable {
    let id: String
    let name: String
    let destination: String?
    let startDate: String
    let endDate: String?
    let baseCurrency: String?
    let status: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, destination, status
        case startDate = "start_date"
        case endDate = "end_date"
        case baseCurrency = "base_currency"
        case createdAt = "created_at"
    }

    var asModel: TripRecord? {
        guard let id = UUID(uuidString: id),
              let start = DateOnlyFormatter.shared.date(from: startDate) else { return nil }
        let end = endDate.flatMap(DateOnlyFormatter.shared.date(from:))
        return TripRecord(
            id: id,
            name: name,
            destination: destination,
            startDate: start,
            endDate: end,
            baseCurrency: baseCurrency,
            status: TripRecord.Status(rawValue: status) ?? .planned,
            createdAt: createdAt ?? .now
        )
    }
}

private struct RESTPaymentMethod: Decodable {
    let id: String
    let name: String
    let network: String?
    let last4: String?
    let isDefault: Bool
    let isActive: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, network, last4
        case isDefault = "is_default"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

private struct RESTPaymentMethodAlias: Decodable {
    let paymentMethodID: String
    let phrase: String

    enum CodingKeys: String, CodingKey {
        case paymentMethodID = "payment_method_id"
        case phrase
    }
}

private struct RESTCategoryUpsert: Encodable {
    let id: String
    let userID: String
    let name: String
    let colorHex: String?
    let isDefault: Bool

    init(_ model: CategoryDefinition, userID: String) {
        id = model.id.uuidString
        self.userID = userID
        name = model.name
        colorHex = model.colorHex
        isDefault = false
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id"
        case colorHex = "color_hex"
        case isDefault = "is_default"
    }
}

private struct RESTCategoryHintUpsert: Encodable {
    var userID: String?
    let categoryID: String
    let phrase: String
    let normalizedPhrase: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case categoryID = "category_id"
        case phrase
        case normalizedPhrase = "normalized_phrase"
    }

    func withUserID(_ userID: String) -> Self {
        var copy = self
        copy.userID = userID
        return copy
    }
}

private struct RESTTripUpsert: Encodable {
    let id: String
    let userID: String
    let name: String
    let destination: String?
    let startDate: String
    let endDate: String?
    let baseCurrency: String?
    let status: String

    init(_ trip: TripRecord, userID: String) {
        id = trip.id.uuidString
        self.userID = userID
        name = trip.name
        destination = trip.destination
        startDate = DateOnlyFormatter.shared.string(from: trip.startDate)
        endDate = trip.endDate.map { DateOnlyFormatter.shared.string(from: $0) }
        baseCurrency = trip.baseCurrency
        status = trip.status.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case id, name, destination, status
        case userID = "user_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case baseCurrency = "base_currency"
    }
}

private struct RESTPaymentMethodUpsert: Encodable {
    let id: String
    let userID: String
    let name: String
    let methodType: String
    let network: String?
    let last4: String?
    let isDefault: Bool
    let isActive: Bool

    init(_ method: PaymentMethod, userID: String) {
        id = method.id.uuidString
        self.userID = userID
        name = method.name
        methodType = "other"
        network = method.network
        last4 = method.last4
        isDefault = method.isDefault
        isActive = method.isActive
    }

    enum CodingKeys: String, CodingKey {
        case id, name, network, last4
        case userID = "user_id"
        case methodType = "method_type"
        case isDefault = "is_default"
        case isActive = "is_active"
    }
}

private struct RESTPaymentMethodAliasUpsert: Encodable {
    var userID: String?
    let paymentMethodID: String
    let phrase: String
    let normalizedPhrase: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case paymentMethodID = "payment_method_id"
        case phrase
        case normalizedPhrase = "normalized_phrase"
    }

    func withUserID(_ userID: String) -> Self {
        var copy = self
        copy.userID = userID
        return copy
    }
}

private enum DateOnlyFormatter {
    static let shared: Foundation.DateFormatter = {
        let formatter = Foundation.DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
