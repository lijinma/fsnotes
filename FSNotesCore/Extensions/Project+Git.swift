//
//  Project+Git.swift
//  FSNotes
//
//  Created by Oleksandr Hlushchenko on 31.10.2022.
//  Copyright © 2022 Oleksandr Hlushchenko. All rights reserved.
//

import Foundation

private class StaticPasswordDelegate: PasswordDelegate {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func get(username: String?, url: URL?) -> PasswordData {
        return RawPasswordData(username: self.username, password: self.password)
    }
}

extension Project {
    private var oauthKeychainAccount: String {
        return "GitOAuth-\(settingsKey)"
    }

    private var oauthKeychainItem: KeychainPasswordItem {
        return KeychainPasswordItem(
            service: "\(KeychainConfiguration.serviceName).GitOAuth",
            account: oauthKeychainAccount,
            accessGroup: KeychainConfiguration.accessGroup
        )
    }

    public func getGitOrigin() -> String? {
        if let origin = settings.gitOrigin, origin.count > 0 {
            return origin
        }

        if let globalOrigin = UserDefaultsManagement.gitOrigin, !globalOrigin.isEmpty {
            settings.setOrigin(globalOrigin)
            saveSettings()
            return globalOrigin
        }

        if let inherited = inheritGitOriginFromParents(), !inherited.isEmpty {
            settings.setOrigin(inherited)
            UserDefaultsManagement.gitOrigin = inherited
            saveSettings()
            return inherited
        }

        _ = syncGitOriginFromLocalRepository()

        if let origin = settings.gitOrigin, origin.count > 0 {
            return origin
        }

        return nil
    }

    private func inheritGitOriginFromParents() -> String? {
        var current = parent

        while let project = current {
            if let origin = project.settings.gitOrigin, !origin.isEmpty {
                return origin
            }
            current = project.parent
        }

        return nil
    }

    @discardableResult
    public func syncGitOriginFromLocalRepository() -> Bool {
        if let origin = settings.gitOrigin, !origin.isEmpty {
            return true
        }

        if let repository = try? getRepository() {
            if let remote = try? repository.remotes.get(remoteName: "origin"),
               let localOrigin = remote.urlString(),
               !localOrigin.isEmpty {
                settings.setOrigin(localOrigin)
                UserDefaultsManagement.gitOrigin = localOrigin
                saveSettings()
                return true
            }

            if let names = try? repository.remotes.remoteNames() {
                for name in names {
                    if let remote = try? repository.remotes.get(remoteName: name),
                       let remoteURL = remote.urlString(),
                       !remoteURL.isEmpty {
                        settings.setOrigin(remoteURL)
                        UserDefaultsManagement.gitOrigin = remoteURL
                        saveSettings()
                        return true
                    }
                }
            }
        }

        if let localOrigin = readOriginFromDotGitConfig(), !localOrigin.isEmpty {
            settings.setOrigin(localOrigin)
            UserDefaultsManagement.gitOrigin = localOrigin
            saveSettings()
            return true
        }

        return false
    }

    public func gitDiagnosticsSummary() -> String {
        var parts: [String] = []
        let candidates = getRepositoryCandidates()
        let existing = candidates.filter { fileExistsWithScope($0) }

        parts.append("vault=\(label)")
        parts.append("settingsKey=\(settingsKey.prefix(8))")
        parts.append("repo=\(existing.isEmpty ? "missing" : "found")")
        parts.append("candidates=\(candidates.map { $0.lastPathComponent }.joined(separator: ","))")
        if let gitStorage = UserDefaultsManagement.gitStorage {
            let storageRepos = (try? FileManager.default.contentsOfDirectory(at: gitStorage, includingPropertiesForKeys: nil))?
                .filter { $0.lastPathComponent.hasSuffix(".git") }.count ?? 0
            parts.append("gitStorageCount=\(storageRepos)")
        }
        parts.append("globalOrigin=\((UserDefaultsManagement.gitOrigin ?? "").isEmpty ? "empty" : "set")")

        if let repoURL = existing.first {
            parts.append("repoPath=\(repoURL.lastPathComponent)")
        }

        if let repository = try? getRepository() {
            if let names = try? repository.remotes.remoteNames(), !names.isEmpty {
                var remotes: [String] = []
                for name in names {
                    let url = (try? repository.remotes.get(remoteName: name).urlString()) ?? "-"
                    remotes.append("\(name)=\(url)")
                }
                parts.append("remotes=\(remotes.joined(separator: ","))")
            } else {
                parts.append("remotes=none")
            }
        } else {
            parts.append("openRepo=failed")
        }

        let hadOrigin = settings.gitOrigin
        let didSync = syncGitOriginFromLocalRepository()
        let origin = settings.gitOrigin ?? ""
        parts.append("origin=\(origin.isEmpty ? "empty" : "set")")
        if didSync && (hadOrigin ?? "") != origin {
            parts.append("originSource=auto")
        } else if let hadOrigin = hadOrigin, !hadOrigin.isEmpty {
            parts.append("originSource=settings")
        } else {
            parts.append("originSource=none")
        }

        return parts.joined(separator: " | ")
    }

#if os(OSX)
    public func getRepositoryUrl() -> URL {
        if UserDefaultsManagement.separateRepo && !isCloudProject() {
            return url.appendingPathComponent(".git", isDirectory: true)
        }

        let key = String(url.path.md5.prefix(4))
        let repoURL = UserDefaultsManagement.gitStorage!.appendingPathComponent(key + " - " + label + ".git")

        return repoURL
    }
#else
    public func getRepositoryUrl() -> URL {
        if !UserDefaultsManagement.iCloudDrive {
            return url.appendingPathComponent(".git")
        }

        let key = String(settingsKey.prefix(6))
        let repoURL = UserDefaultsManagement.gitStorage!.appendingPathComponent(key + ".git")

        return repoURL
    }
#endif

    public func hasRepository() -> Bool {
        for candidate in getRepositoryCandidates() {
            if fileExistsWithScope(candidate) {
                return true
            }
        }

        return false
    }

    public func getGitProject() -> Project? {
        if hasRepository() {
            return self
        }

        if let parent = parent, let root = parent.getGitProject() {
            return root
        }

        return nil
    }

    public func initBareRepository() throws {
        let repositoryManager = RepositoryManager()
        let repoURL = getRepositoryUrl()

        // Prepare temporary dir
        let tempURL = UserDefaultsManagement.gitStorage!.appendingPathComponent("tmp")

        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)

        // Init
        let signature = Signature(name: "FSNotes App", email: "support@fsnot.es")
        let repository = try repositoryManager.initRepository(at: tempURL, signature: signature)

        if isUseWorkTree() {
            repository.setWorkTree(path: url.path)
        }

        let dotGit = tempURL.appendingPathComponent(".git")

        if FileManager.default.directoryExists(atUrl: dotGit) {
            try? FileManager.default.moveItem(at: dotGit, to: repoURL)
        }
    }

    public func cloneRepository() throws -> Repository? {
        let repositoryManager = RepositoryManager()
        let repoURL = getRepositoryUrl()

        // Prepare temporary dir
        guard let tempURL = UserDefaultsManagement.gitStorage?.appendingPathComponent("tmp") else { return nil }

        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)

        // Clone
        if let originString = getGitOrigin(), let origin = URL(string: originString) {
            let repository = try repositoryManager.cloneRepository(from: origin, at: tempURL, authentication: getAuthHandler())

            if isUseWorkTree() {
                repository.setWorkTree(path: url.path)
            }

            let dotGit = tempURL.appendingPathComponent(".git")

            if FileManager.default.directoryExists(atUrl: dotGit) {
                try? FileManager.default.moveItem(at: dotGit, to: repoURL)

                return try repositoryManager.openRepository(at: repoURL)
            }

            return nil
        }

        return nil
    }

    public func getRepository() throws -> Repository {
        let repositoryManager = RepositoryManager()
        let candidates = getRepositoryCandidates()

        var firstError: Error?
        for candidate in candidates {
            if !fileExistsWithScope(candidate) {
                continue
            }

            do {
                return try repositoryManager.openRepository(at: candidate)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError = firstError {
            throw firstError
        }

        return try repositoryManager.openRepository(at: getRepositoryUrl())
    }

    public func useSeparateRepo() -> Bool {
        return UserDefaultsManagement.separateRepo && !isCloudProject()
    }

    public func isCloudProject() -> Bool {
        guard let storagePath = UserDefaultsManagement.storagePath,
              let documentsProject = UserDefaultsManagement.iCloudDocumentsContainer else { return false }

        if storagePath == documentsProject.path, url.path.contains(storagePath) {
            return true
        }

        return false
    }

    public func getAuthHandler() -> AuthenticationHandler? {
        let mayUseOAuth = settings.gitAuthMode == "oauth" || (settings.gitAuthMode == nil && settings.gitPrivateKey == nil)
        if mayUseOAuth, let token = getGitOAuthToken(), !token.isEmpty {
            let username = settings.gitOAuthUsername ?? "x-access-token"
            return PasswordHandler(passwordDelegate: StaticPasswordDelegate(username: username, password: token))
        }

        var rsa: URL?

        if let rsaURL = installSSHKey() {
            rsa = rsaURL
        }

        guard let rsaURL = rsa else { return nil }

        let passphrase = settings.gitPrivateKeyPassphrase ?? ""
        let sshKeyDelegate = StaticSshKeyDelegate(privateUrl: rsaURL, passphrase: passphrase)
        let handler = SshKeyHandler(sshKeyDelegate: sshKeyDelegate)

        return handler
    }

    public func getSSHKeyUrl() -> URL? {
        let keyName = getSettingsKey()

        return storage
            .getGitKeysDir()?
            .appendingPathComponent(keyName)
    }

    public func removeSSHKey() {
        guard let url = getSSHKeyUrl() else { return }

        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("pub"))
    }

    public func installSSHKey() -> URL? {
        guard let url = getSSHKeyUrl() else { return nil }

        if let key = settings.gitPrivateKey {
            do {
                try key.write(to: url)

                if let publicKey = settings.gitPublicKey {
                    let publicKeyUrl = url.appendingPathExtension("pub")
                    try publicKey.write(to: publicKeyUrl)
                }

                return url
            } catch {/*_*/}
        }

        return nil
    }

    public func getSign() -> Signature {
        return Signature(name: "FSNotes App", email: "support@fsnot.es")
    }

    public func commit(message: String? = nil, progress: GitProgress? = nil) throws {
        let repository = try getRepository()
        let lastCommit = try? repository.head().targetCommit()

        // Add all and save index
        let head = try repository.head().index()
        if let progress = progress {
            progress.log(message: "git add .")
        }

        let success = head.add(path: ".")

        // No commits yet or added files was found
        if success || lastCommit == nil {
            try head.save()

            do {
                progress?.log(message: "git commit")

                let sign = getSign()
                if lastCommit == nil {
                    let commitMessage = message ?? "FSNotes Init"
                    _ = try head.createInitialCommit(msg: commitMessage, signature: sign)
                } else {
                    let commitMessage = message ?? "Usual commit"
                    _ = try head.createCommit(msg: commitMessage, signature: sign)
                }

                progress?.log(message: "git commit done 🤟")

                cacheHistory(progress: progress)
            } catch {
                progress?.log(message: "commit error: \(error)")
            }
        } else {
            progress?.log(message: "git add: no new data")

            throw GitError.noAddedFiles
        }
    }

    public func checkGitState() throws -> Bool {
        let repository = try getRepository()
        let statuses = Statuses(repository: repository)

        isCleanGit = statuses.workingDirectoryClean
        return isCleanGit
    }

    public func getLocalBranch(repository: Repository) -> Branch? {
        do {
            let names = try Branches(repository: repository).names(type: .local)

            guard names.count > 0 else { return nil }
            guard let branchName = names.first?.components(separatedBy: "/").last else { return nil }

            let localMaster = try repository.branches.get(name: branchName)
            return localMaster
        } catch {/**/}

        return nil
    }

    public func push(progress: GitProgress? = nil) throws {
        guard let origin = getGitOrigin() else { return }

        let repository = try getRepository()
        repository.addRemoteOrigin(path: origin)

        let handler = getAuthHandler()

        let names = try Branches(repository: repository).names(type: .local)
        guard names.count > 0 else { return }
        guard let branchName = names.first?.components(separatedBy: "/").last else { return }

        let localMaster = try repository.branches.get(name: branchName)
        try repository.remotes.get(remoteName: "origin").push(local: localMaster, authentication: handler)

        if let progress = progress {
            progress.log(message: "\(label) – successful push 👌")
        }
    }

    public func pull(progress: GitProgress? = nil) throws {
        guard let origin = getGitOrigin() else { return }

        let repository = try getRepository()
        repository.addRemoteOrigin(path: origin)

        if isUseWorkTree() {
            repository.setWorkTree(path: url.path)
        }

        let authHandler = getAuthHandler()
        let sign = getSign()

        let remote = repository.remotes
        let remoteBranch = try remote.get(remoteName: "origin")

        do {
            try remoteBranch.pull(signature: sign, authentication: authHandler, project: self)
        } catch GitError.uncommittedConflict {
            try commit()
            try remoteBranch.pull(signature: sign, authentication: authHandler, project: self)
            try push()
        }

        if let progress = progress {
            progress.log(message: "\(label) – successful git pull 👌")
        }
    }

    public func isUseWorkTree() -> Bool {
    #if os(iOS)
        return UserDefaultsManagement.iCloudDrive
    #else
        return !UserDefaultsManagement.separateRepo || isCloudProject()
    #endif
    }

    public func isGitOriginExist() -> Bool {
        return getGitOrigin() != nil
    }

    private func readOriginFromDotGitConfig() -> String? {
        let dotGitURL = url.appendingPathComponent(".git")
        var configURL: URL?
        var isDir = ObjCBool(false)

        if fileExistsWithScope(dotGitURL, isDirectory: &isDir) {
            if isDir.boolValue {
                configURL = dotGitURL.appendingPathComponent("config")
            } else if let gitRef = try? String(contentsOf: dotGitURL, encoding: .utf8) {
                let prefix = "gitdir:"
                if let line = gitRef.split(separator: "\n").first(where: { $0.lowercased().contains(prefix) }) {
                    let raw = String(line)
                    if let range = raw.range(of: ":", options: .literal) {
                        let path = raw[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                        let gitDirURL: URL
                        if path.hasPrefix("/") {
                            gitDirURL = URL(fileURLWithPath: path)
                        } else {
                            gitDirURL = url.appendingPathComponent(path)
                        }
                        configURL = gitDirURL.appendingPathComponent("config")
                    }
                }
            }
        }

        guard let cfg = configURL,
              let text = try? String(contentsOf: cfg, encoding: .utf8) else { return nil }

        return parseOriginURLFromGitConfig(text)
    }

    private func parseOriginURLFromGitConfig(_ text: String) -> String? {
        var inOriginSection = false
        var firstRemoteURL: String?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let lowered = trimmed.lowercased()
                inOriginSection = lowered == "[remote \"origin\"]"
                continue
            }

            if trimmed.lowercased().hasPrefix("url") {
                let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2 {
                    let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        if inOriginSection {
                            return value
                        }
                        if firstRemoteURL == nil {
                            firstRemoteURL = value
                        }
                    }
                }
            }
        }

        return firstRemoteURL
    }

    private func fileExistsWithScope(_ target: URL, isDirectory: UnsafeMutablePointer<ObjCBool>? = nil) -> Bool {
        #if os(iOS)
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        #endif
        return FileManager.default.fileExists(atPath: target.path, isDirectory: isDirectory)
    }

    private func getRepositoryCandidates() -> [URL] {
        var candidates: [URL] = []

        let inlineRepo = url.appendingPathComponent(".git")
        candidates.append(inlineRepo)

        let primary = getRepositoryUrl()
        if !candidates.contains(primary) {
            candidates.append(primary)
        }

        #if os(iOS)
        if UserDefaultsManagement.iCloudDrive,
           let gitStorage = UserDefaultsManagement.gitStorage {
            let stableKey = String(settingsKey.prefix(6))
            let legacyHashKey = String(settingsKey.md5.prefix(6))
            let keys = [stableKey, legacyHashKey]

            for key in keys {
                let byKey = gitStorage.appendingPathComponent("\(key).git")
                if !candidates.contains(byKey) {
                    candidates.append(byKey)
                }

                let byLabel = gitStorage.appendingPathComponent("\(key) - \(label).git")
                if !candidates.contains(byLabel) {
                    candidates.append(byLabel)
                }
            }

            if let entries = try? FileManager.default.contentsOfDirectory(at: gitStorage, includingPropertiesForKeys: nil) {
                let matchedByKey = entries.filter {
                    let name = $0.lastPathComponent
                    guard name.hasSuffix(".git") else { return false }
                    return keys.contains(where: { name.hasPrefix("\($0).") || name.hasPrefix("\($0) - ") })
                }
                for item in matchedByKey where !candidates.contains(item) {
                    candidates.append(item)
                }

                // Fallback: recover repo by matching core.worktree to current vault path.
                for repoURL in entries where repoURL.lastPathComponent.hasSuffix(".git") {
                    guard let workTree = readWorkTreeFromRepositoryConfig(repoURL),
                          pathEquivalent(workTree, url.path) else { continue }
                    if !candidates.contains(repoURL) {
                        candidates.append(repoURL)
                    }
                }
            }
        }
        #endif

        return candidates
    }

    private func readWorkTreeFromRepositoryConfig(_ repoURL: URL) -> String? {
        let configURL = repoURL.appendingPathComponent("config")
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }

        var inCore = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inCore = trimmed.lowercased() == "[core]"
                continue
            }

            guard inCore, trimmed.lowercased().hasPrefix("worktree") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }

            let rawPath = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if rawPath.hasPrefix("/") {
                return URL(fileURLWithPath: rawPath).standardized.path
            }

            return repoURL.deletingLastPathComponent().appendingPathComponent(rawPath).standardized.path
        }

        return nil
    }

    private func pathEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.replacingOccurrences(of: "/private/", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let b = rhs.replacingOccurrences(of: "/private/", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return a == b
    }

    public func getGitOAuthToken() -> String? {
        if let token = settings.gitOAuthAccessToken, !token.isEmpty {
            try? oauthKeychainItem.savePassword(token)
            return token
        }

        if let token = try? oauthKeychainItem.readPassword(), !token.isEmpty {
            settings.gitOAuthAccessToken = token
            if settings.gitAuthMode == nil {
                settings.gitAuthMode = "oauth"
            }
            if settings.gitOAuthProvider == nil {
                settings.gitOAuthProvider = "github"
            }
            if settings.gitOAuthUsername == nil {
                settings.gitOAuthUsername = "x-access-token"
            }
            saveSettings()
            return token
        }

        return nil
    }

    public func setGitOAuthToken(_ token: String, provider: String = "github", username: String = "x-access-token") {
        settings.gitAuthMode = "oauth"
        settings.gitOAuthProvider = provider
        settings.gitOAuthAccessToken = token
        settings.gitOAuthUsername = username

        try? oauthKeychainItem.savePassword(token)
        saveSettings()
    }

    public func clearGitOAuthToken() {
        settings.gitOAuthAccessToken = nil
        settings.gitOAuthProvider = nil
        settings.gitOAuthUsername = nil
        settings.gitAuthMode = nil

        try? oauthKeychainItem.deleteItem()
        saveSettings()
    }

    public func isGitOAuthAuthorized() -> Bool {
        return getGitOAuthToken() != nil
    }

    public func removeRepository(progress: GitProgress? = nil) {
        let repoURL = getRepositoryUrl()

        if FileManager.default.fileExists(atPath: repoURL.path) {
            try? FileManager.default.removeItem(at: repoURL)
        }

        removeCommitsCache()

        progress?.log(message: "git repository has been deleted")
    }

    public func removeCommitsCache() {
        if let url = getCommitsDiffsCache() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func loadCommitsCache() {
        if !commitsCache.isEmpty {
            return
        }

        if let commitsDiffCache = getCommitsDiffsCache(),
            let data = try? Data(contentsOf: commitsDiffCache),
            let result = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSArray.self, NSString.self], from: data) as? [String: [String]] {
            commitsCache = result
        }
    }

    public func cacheHistory(progress: GitProgress? = nil) {
        progress?.log(message: "git history caching ...")

        guard let repository = try? getRepository() else { return }

        do {
            let fileRevLog = try FileHistoryIterator(repository: repository, path: "Test", project: self)
            fileRevLog.walkCacheDiff()

            let cacheData = try? NSKeyedArchiver.archivedData(withRootObject: commitsCache, requiringSecureCoding: true)
            if let data = cacheData, let writeTo = getCommitsDiffsCache() {
                do {
                    try data.write(to: writeTo)
                } catch {
                    print("Caching error: " + error.localizedDescription)
                }
            }
        } catch {
            print(error)
        }

        progress?.log(message: "git history caching done 🤟")
    }

    public func getCommitsDiffsCache() -> URL? {
        guard let documentDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let fileName = "commitsDiff-\(settingsKey).cache"
        return documentDir.appendingPathComponent(fileName, isDirectory: false)
    }

    public func hasCommitsDiffsCache() -> Bool {
        guard let project = getGitProject() else { return false }

        if let url = project.getCommitsDiffsCache() {
            return FileManager.default.fileExists(atPath: url.path)
        }

        return false
    }

    public func getRepositoryState() -> RepositoryAction {
        let hasOrigin = getGitOrigin() != nil

        if hasRepository() {
            if hasOrigin {
                return .pullPush
            } else {
                return .commit
            }
        } else {
            if hasOrigin {
                return .clonePush
            } else {
                return .initCommit
            }
        }
    }

    public func gitDo(_ action: RepositoryAction, progress: GitProgress? = nil) -> String? {
        var message: String?

        do {
            switch action {
            case .initCommit:
                try initBareRepository()
                try commit(message: nil, progress: progress)
            case .clonePush:
                removeCommitsCache()
                message = clonePush(progress: progress)
            case .commit:
                try commit(message: nil, progress: progress)
            case .pullPush:
                do {
                    do {
                        try commit(message: nil, progress: progress)
                    } catch GitError.noAddedFiles {
                        progress?.log(message: "git add: no new data")
                    }

                    try pull(progress: progress)
                    try push(progress: progress)
                } catch GitError.notFound(let ref) {
                    progress?.log(message: "\(ref) not found, push trying ...")

                    try push(progress: progress)
                }
            }
        } catch {
            if let error = error as? GitError {
                message = error.associatedValue()
            } else {
                message = error.localizedDescription
            }
        }

        return message
    }

    private func clonePush(progress: GitProgress? = nil) -> String? {
        var message: String?

        do {
            if let repo = try cloneRepository(), let local = getLocalBranch(repository: repo) {
                try repo.head().checkout(branch: local, type: .force)
                cacheHistory(progress: progress)
            } else {
                do {
                    try commit(message: nil, progress: progress)
                    try push(progress: progress)
                } catch {
                    message = error.localizedDescription
                }
            }
        } catch GitError.unknownError(let errorMessage, _, let desc) {
            message = errorMessage + " – " + desc
        } catch GitError.notFound(let ref) {

            // Empty repository – commit and push
            if ref == "refs/heads/master" {
                do {
                    try commit(message: nil, progress: progress)
                    try push(progress: progress)
                } catch {
                    message = error.localizedDescription
                }
            }
        } catch {
            message = error.localizedDescription
        }

        return message
    }

    public func saveRevision(commitMessage: String? = nil) throws {
        try commit(message: commitMessage)
        
        // No hands – no mults
        guard getGitOrigin() != nil else { return }
        
        try pull()
        try push()
    }
}
