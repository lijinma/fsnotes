//
//  GitViewController.swift
//  FSNotes iOS
//
//  Created by Oleksandr Hlushchenko on 05.02.2023.
//  Copyright © 2023 Oleksandr Hlushchenko. All rights reserved.
//

import UIKit
import CryptoKit

extension Notification.Name {
    static let gitOAuthCallback = Notification.Name("es.fsnotes.git.oauth.callback")
}

class GitViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    @IBOutlet weak var tableView: UITableView!

    enum GitSection: Int, CaseIterable {
        case vault
        case automation
        case oauth
        case origin
        case logs

        var title: String {
            switch self {
            case .vault: return "Vault"
            case .automation: return "Automation"
            case .oauth: return "Authorization"
            case .origin: return "Origin"
            case .logs: return "Status"
            }
        }
    }

    private var hasActiveGit: Bool = false
    private var progress: GitProgress?
    private var project: Project?
    private var pendingPKCE: OAuthPKCEContext?
    private var initialOriginToApply: String?
    private var shouldStartGitHubImportFlow: Bool = false
    private var pendingCloneAfterOAuth: Bool = false
    private var didHandleInitialOrigin: Bool = false
    private var didRunDiagnostics: Bool = false
    private var debugStatusMessage: String = "debug: waiting"

    public var activity: UIActivityIndicatorView?
    public var leftButton: UIButton?
    public var rightButton: UIButton?
    public var logTextField: UITextField?

    public func setProject(_ project: Project) {
        self.project = project.getGitProject() ?? project
        _ = self.project?.syncGitOriginFromLocalRepository()
    }

    public func configureInitialGitOrigin(_ origin: String, startGitHubImport: Bool = false) {
        initialOriginToApply = origin
        shouldStartGitHubImportFlow = startGitHubImport
        pendingCloneAfterOAuth = false
        didHandleInitialOrigin = false
    }

    override func viewDidLoad() {
        self.title = NSLocalizedString("Git", comment: "Settings")
        navigationItem.largeTitleDisplayMode = .always

        tableView.delegate = self
        tableView.dataSource = self

        super.viewDidLoad()

        setupKeyboardObservers()
        tableView.keyboardDismissMode = .interactive
        NotificationCenter.default.addObserver(self, selector: #selector(handleOAuthCallback(_:)), name: .gitOAuthCallback, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = true
        didRunDiagnostics = false

        DispatchQueue.main.async {
            if self.project == nil {
                self.setDebugStatus("debug: project=nil in viewWillAppear")
            } else {
                _ = self.project?.syncGitOriginFromLocalRepository()
            }
            self.updateButtons(isActive: self.hasActiveGit)
            if let status = self.project?.gitStatus {
                self.logTextField?.text = status
            } else {
                self.logTextField?.text = self.debugStatusMessage
            }
            self.tableView.reloadData()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        runDiagnosticsIfNeeded()
        applyInitialOriginIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return GitSection(rawValue: section)?.title
    }

    @objc func cancel() {
        self.navigationController?.popViewController(animated: true)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: false) }

        guard let section = GitSection(rawValue: indexPath.section) else { return }

        if section == .vault {
            return
        }

        if section == .oauth && indexPath.row == 1 {
            authorizeWithPKCE()
            return
        }

        if section == .oauth && indexPath.row == 2 {
            disconnectOAuth()
            return
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 50
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let project = project else { return UITableViewCell() }

        if indexPath.section == GitSection.vault.rawValue {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Selected vault"
            cell.detailTextLabel?.text = project.label
            cell.selectionStyle = .none
            return cell
        }

        if indexPath.section == GitSection.automation.rawValue {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Pull (every 30 sec)", comment: "")

            let uiSwitch = UISwitch()
            uiSwitch.addTarget(self, action: #selector(autoPullDidChange(_:)), for: .valueChanged)
            uiSwitch.isOn = project.settings.gitAutoPull
            cell.accessoryView = uiSwitch
            return cell
        }

        if indexPath.section == GitSection.oauth.rawValue {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.accessoryType = .none
            cell.selectionStyle = .default

            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Provider"
                cell.detailTextLabel?.text = "GitHub"
                cell.selectionStyle = .none
            case 1:
                let authorized = isOAuthAuthorized(project: project)
                cell.textLabel?.text = authorized ? "Re-authorize" : "Authorize with GitHub"
                cell.detailTextLabel?.text = authorized ? "Connected" : "Not connected"
                cell.accessoryType = .disclosureIndicator
            case 2:
                cell.textLabel?.text = "Disconnect"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = nil
                cell.selectionStyle = isOAuthAuthorized(project: project) ? .default : .none
                if !isOAuthAuthorized(project: project) {
                    cell.textLabel?.textColor = .systemGray
                }
            default:
                break
            }

            return cell
        }

        if indexPath.section == GitSection.origin.rawValue && indexPath.row == 0 || (
            indexPath.section == GitSection.logs.rawValue && indexPath.row == 0
        ) {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)

            let textField = UITextField()
            textField.textColor = UIColor.blackWhite

            if indexPath.section == GitSection.origin.rawValue && indexPath.row == 0 {
                textField.addTarget(self, action: #selector(originDidChange), for: .editingChanged)
                textField.placeholder = "https://github.com/username/repo.git"
                textField.text = project.settings.gitOrigin ?? ""
            }

            if indexPath.section == GitSection.logs.rawValue && indexPath.row == 0 {
                textField.placeholder = "no data"
                textField.isEnabled = false
                textField.text = project.gitStatus ?? debugStatusMessage

                logTextField = textField
                progress = GitProgress(statusTextField: textField, project: project)

                AppDelegate.gitProgress = progress
            }

            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.textAlignment = .right

            cell.contentView.addSubview(textField)
            cell.addConstraint(NSLayoutConstraint(item: textField, attribute: .leading, relatedBy: .equal, toItem: cell.textLabel, attribute: .trailing, multiplier: 1, constant: 8))
            cell.addConstraint(NSLayoutConstraint(item: textField, attribute: .top, relatedBy: .equal, toItem: cell.contentView, attribute: .top, multiplier: 1, constant: 8))
            cell.addConstraint(NSLayoutConstraint(item: textField, attribute: .bottom, relatedBy: .equal, toItem: cell.contentView, attribute: .bottom, multiplier: 1, constant: -8))
            cell.addConstraint(NSLayoutConstraint(item: textField, attribute: .trailing, relatedBy: .equal, toItem: cell.contentView, attribute: .trailing, multiplier: 1, constant: -8))

            return cell
        }

        if indexPath.section == GitSection.origin.rawValue && indexPath.row == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "gitTableViewCell", for: indexPath) as! GitTableViewCell
            cell.selectionStyle = .none
            cell.cloneButton.addTarget(self, action: #selector(repoPressed), for: .touchUpInside)
            cell.removeButton.addTarget(self, action: #selector(removePressed), for: .touchUpInside)

            leftButton = cell.cloneButton
            rightButton = cell.removeButton
            activity = cell.activity

            activity?.isHidden = true
            activity?.startAnimating()

            return cell
        }

        return UITableViewCell(style: .value1, reuseIdentifier: nil)
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return GitSection.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == GitSection.vault.rawValue { return 1 }
        if section == GitSection.automation.rawValue { return 1 }
        if section == GitSection.oauth.rawValue { return 3 }
        if section == GitSection.origin.rawValue { return 2 }
        return 1
    }

    @objc func originDidChange(sender: UITextField) {
        guard let project = project, let origin = sender.text else { return }

        project.settings.setOrigin(origin)
        UserDefaultsManagement.gitOrigin = origin.isEmpty ? nil : origin
        project.saveSettings()
        updateButtons()
    }

    @objc func removePressed(sender: UIButton) {
        guard let project = project else { return }

        project.removeRepository()
        rightButton?.isEnabled = false

        progress?.log(message: "git repository removed")
        updateButtons()
    }

    @objc func repoPressed(sender: UIButton) {
        runRepositoryAction()
    }

    private func runRepositoryAction() {
        guard let project = project else { return }

        if requiresRemoteAuth(project: project) && !isOAuthAuthorized(project: project) {
            errorAlert(title: "OAuth required", message: "Please authorize GitHub OAuth before remote operations")
            return
        }

        let action = project.getRepositoryState()
        updateButtons(isActive: true)

        UIApplication.shared.isIdleTimerDisabled = true
        UIApplication.getVC().gitQueue.addOperation({
            defer {
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = false
                    UIApplication.getVC().scheduledGitPull()

                    self.updateButtons(isActive: false)
                }
            }

            if let message = project.gitDo(action, progress: self.progress) {
                DispatchQueue.main.async {
                    self.errorAlert(title: "git error", message: message)

                    if action == .pullPush && !UserDefaultsManagement.iCloudDrive {
                        UIApplication.getVC().checkNew()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.successAlert(title: "Git sync complete", message: project.gitSyncSuccessMessage())
                }
            }
        })
    }

    private func applyInitialOriginIfNeeded() {
        guard !didHandleInitialOrigin else { return }
        guard let project = project else { return }
        guard let initialOrigin = initialOriginToApply, !initialOrigin.isEmpty else { return }

        didHandleInitialOrigin = true

        if project.settings.gitOrigin != initialOrigin {
            project.settings.setOrigin(initialOrigin)
            UserDefaultsManagement.gitOrigin = initialOrigin
            project.saveSettings()
        }

        tableView.reloadData()
        updateButtons()

        if shouldStartGitHubImportFlow {
            shouldStartGitHubImportFlow = false

            if requiresRemoteAuth(project: project) && !isOAuthAuthorized(project: project) {
                pendingCloneAfterOAuth = true
                progress?.log(message: "Authorizing GitHub before clone...")
                authorizeWithPKCE()
                return
            }

            runRepositoryAction()
        }
    }

    private func requiresRemoteAuth(project: Project) -> Bool {
        guard let origin = project.getGitOrigin()?.lowercased(), !origin.isEmpty else {
            return false
        }

        let state = project.getRepositoryState()
        let needsRemote = state == .clonePush || state == .pullPush
        return needsRemote && origin.starts(with: "https://")
    }

    private func isOAuthAuthorized(project: Project) -> Bool {
        return project.isGitOAuthAuthorized()
    }

    private func disconnectOAuth() {
        guard let project = project else { return }
        guard isOAuthAuthorized(project: project) else { return }

        project.clearGitOAuthToken()
        pendingCloneAfterOAuth = false

        progress?.log(message: "OAuth disconnected")
        tableView.reloadData()
    }

    private func authorizeWithPKCE() {
        guard let project = project else { return }

        guard let clientId = getGitHubOAuthClientID(), !clientId.isEmpty else {
            errorAlert(
                title: "OAuth not configured",
                message: "Missing GitHubOAuthClientID in Info.plist"
            )
            return
        }

        guard let redirectURI = getGitHubOAuthRedirectURI(), !redirectURI.isEmpty else {
            errorAlert(
                title: "OAuth not configured",
                message: "Missing GitHubOAuthRedirectURI in Info.plist"
            )
            return
        }

        guard let backendURL = getGitHubOAuthBackendTokenURL(), !backendURL.isEmpty else {
            errorAlert(
                title: "OAuth not configured",
                message: "Missing GitHubOAuthBackendTokenURL in Info.plist"
            )
            return
        }
        _ = backendURL

        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = UUID().uuidString

        pendingPKCE = OAuthPKCEContext(state: state, codeVerifier: verifier, redirectURI: redirectURI)

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "repo"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components?.url else {
            errorAlert(title: "OAuth error", message: "Unable to build authorization URL")
            return
        }

        progress?.log(message: "Opening GitHub in browser...")
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard let self = self else { return }
            if !success {
                self.errorAlert(title: "OAuth error", message: "Unable to open browser for authorization")
            }
        }
    }

    @objc private func handleOAuthCallback(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else { return }
        processOAuthCallback(url: url)
    }

    private func processOAuthCallback(url: URL) {
        guard let project = project else { return }
        guard let context = pendingPKCE else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let queryItems = components.queryItems ?? []

        if let oauthError = queryItems.first(where: { $0.name == "error" })?.value {
            errorAlert(title: "OAuth error", message: oauthError)
            pendingPKCE = nil
            return
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            errorAlert(title: "OAuth error", message: "Missing authorization code")
            pendingPKCE = nil
            return
        }

        guard let callbackState = queryItems.first(where: { $0.name == "state" })?.value,
              callbackState == context.state else {
            errorAlert(title: "OAuth error", message: "State mismatch, please retry")
            pendingPKCE = nil
            return
        }

        pendingPKCE = nil
        progress?.log(message: "Finishing OAuth authorization...")

        Task {
            do {
                let token = try await requestGitHubAccessTokenFromBackend(
                    code: code,
                    codeVerifier: context.codeVerifier,
                    redirectURI: context.redirectURI
                )

                await MainActor.run {
                    project.setGitOAuthToken(token, provider: "github", username: "x-access-token")
                    project.settings.gitPrivateKey = nil
                    project.settings.gitPublicKey = nil
                    project.settings.gitPrivateKeyPassphrase = nil
                    project.saveSettings()

                    self.progress?.log(message: "GitHub OAuth connected")
                    self.tableView.reloadData()

                    if self.pendingCloneAfterOAuth {
                        self.pendingCloneAfterOAuth = false
                        self.runRepositoryAction()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorAlert(title: "OAuth error", message: error.localizedDescription)
                }
            }
        }
    }

    private func getGitHubOAuthClientID() -> String? {
        return Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String
    }

    private func getGitHubOAuthRedirectURI() -> String? {
        return Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthRedirectURI") as? String
    }

    private func getGitHubOAuthBackendTokenURL() -> String? {
        return Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthBackendTokenURL") as? String
    }

    private func generateCodeVerifier() -> String {
        var random = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
        let data = Data(random)
        return base64URLEncode(data)
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(hash))
    }

    private func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func requestGitHubAccessTokenFromBackend(code: String, codeVerifier: String, redirectURI: String) async throws -> String {
        guard let tokenURLString = getGitHubOAuthBackendTokenURL(),
              let tokenURL = URL(string: tokenURLString) else {
            throw NSError(domain: "GitOAuth", code: 10, userInfo: [NSLocalizedDescriptionKey: "Missing GitHubOAuthBackendTokenURL"])
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": redirectURI
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let details = String(data: data, encoding: .utf8) ?? "Unable to exchange OAuth token via backend"
            throw NSError(domain: "GitOAuth", code: 11, userInfo: [NSLocalizedDescriptionKey: details])
        }

        let parsed = try JSONDecoder().decode(BackendTokenResponse.self, from: data)
        if let token = parsed.accessToken, !token.isEmpty {
            return token
        }

        let message = parsed.errorDescription ?? parsed.error ?? "OAuth token not received from backend"
        throw NSError(domain: "GitOAuth", code: 12, userInfo: [NSLocalizedDescriptionKey: message])
    }

    public func errorAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

            let okAction = UIAlertAction(title: "OK", style: .cancel) { (_) in }
            alertController.addAction(okAction)
            if self.presentedViewController == nil {
                self.present(alertController, animated: true, completion: nil)
            } else {
                self.dismiss(animated: false) {
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }

    public func successAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default))

            if self.presentedViewController == nil {
                self.present(alertController, animated: true, completion: nil)
            } else {
                self.dismiss(animated: false) {
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }

    public func updateButtons(isActive: Bool? = nil) {
        guard let project = project else { return }

        if let isActive = isActive {
            hasActiveGit = isActive
            leftButton?.isEnabled = !isActive
            activity?.isHidden = !isActive
        }

        rightButton?.isEnabled = project.hasRepository()

        let state = project.getRepositoryState()
        leftButton?.setTitle(state.title, for: .normal)
    }

    @objc public func autoPullDidChange(_ sender: UISwitch) {
        guard let cell = sender.superview as? UITableViewCell else { return }
        guard let uiSwitch = cell.accessoryView as? UISwitch else { return }
        guard let project = project else { return }

        project.settings.gitAutoPull = uiSwitch.isOn
        project.saveSettings()
    }

    public func setProgress(message: String) {
        progress?.log(message: message)
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let keyboardHeight = keyboardFrame.height
        let bottomSafeArea = view.safeAreaInsets.bottom

        UIView.animate(withDuration: 0.3) {
            self.tableView.contentInset.bottom = keyboardHeight - bottomSafeArea
            self.tableView.verticalScrollIndicatorInsets.bottom = keyboardHeight - bottomSafeArea
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        UIView.animate(withDuration: 0.3) {
            self.tableView.contentInset.bottom = 0
            self.tableView.verticalScrollIndicatorInsets.bottom = 0
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func runDiagnosticsIfNeeded() {
        guard !didRunDiagnostics else { return }
        didRunDiagnostics = true

        guard let project = project else {
            setDebugStatus("debug: project=nil in runDiagnostics")
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let summary = project.gitDiagnosticsSummary()
            self.setDebugStatus(summary)

            DispatchQueue.main.async {
                if let progress = self.progress {
                    progress.log(message: summary)
                } else {
                    self.logTextField?.text = summary
                }
                self.tableView.reloadData()
            }
        }
    }

    private func setDebugStatus(_ message: String) {
        debugStatusMessage = message
        project?.gitStatus = message
        print("[GitDebug] \(message)")
        DispatchQueue.main.async {
            self.logTextField?.text = message
        }
    }
}

private struct OAuthPKCEContext {
    let state: String
    let codeVerifier: String
    let redirectURI: String
}

private struct BackendTokenResponse: Decodable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
    }
}
