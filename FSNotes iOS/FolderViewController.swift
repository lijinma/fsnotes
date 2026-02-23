//
//  FolderViewController.swift
//  FSNotes iOS
//
//  Apple Notes style folder content view: sub-folders first, then notes.
//

import UIKit

class FoldersRootViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var projects: [Project] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Folders", comment: "")
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemGroupedBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(FolderCellView.self, forCellReuseIdentifier: "folderCell")
        tableView.rowHeight = 52
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        loadProjects()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadProjects()
        tableView.reloadData()
    }

    private func loadProjects() {
        projects = Storage.shared()
            .getSidebarProjects()
            .filter { !$0.isVirtual && !$0.isTrash && $0.settings.showInSidebar }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return projects.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "folderCell", for: indexPath) as! FolderCellView
        guard projects.indices.contains(indexPath.row) else { return cell }

        cell.configure(project: projects[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard projects.indices.contains(indexPath.row) else { return }

        let folderVC = FolderViewController(project: projects[indexPath.row])
        navigationController?.pushViewController(folderVC, animated: true)
    }
}

class FolderViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {

    let project: Project
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var childProjects: [Project] = []
    private var notes: [Note] = []

    // Filtered results for search
    private var filteredNotes: [Note] = []
    private var filteredChildProjects: [Project] = []
    private var isSearching: Bool {
        guard let text = navigationItem.searchController?.searchBar.text else { return false }
        return !text.isEmpty
    }

    // Toolbar items
    private var noteCountItem: UIBarButtonItem!

    // MARK: - Init

    init(project: Project) {
        self.project = project
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = project.label
        navigationItem.largeTitleDisplayMode = .automatic
        navigationController?.navigationBar.prefersLargeTitles = true

        view.backgroundColor = .systemBackground

        configureSearchController()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(FolderCellView.self, forCellReuseIdentifier: "folderCell")
        tableView.register(NoteSummaryCell.self, forCellReuseIdentifier: "noteCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 70

        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        configureToolbar()
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.setToolbarHidden(false, animated: true)
        loadData()
        tableView.reloadData()
        updateNoteCount()
    }

    // MARK: - Search

    private func configureSearchController() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("Search", comment: "")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true
        definesPresentationContext = true
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?.lowercased() ?? ""
        if query.isEmpty {
            filteredNotes = []
            filteredChildProjects = []
        } else {
            filteredNotes = notes.filter { note in
                let title = (note.getTitle() ?? note.getFileName()).lowercased()
                let content = note.content.string.lowercased()
                return title.contains(query) || content.contains(query)
            }
            filteredChildProjects = childProjects.filter {
                $0.label.lowercased().contains(query)
            }
        }
        tableView.reloadData()
        updateNoteCount()
    }

    // MARK: - Data

    private func loadData() {
        childProjects = Storage.shared().getChildProjects(project: project)
        let all = Storage.shared().noteList.filter { $0.project == project && !$0.isTrash() }
        notes = Storage.shared().sortNotes(noteList: all)
    }

    // Active data sources depending on search state
    private var activeChildProjects: [Project] {
        return isSearching ? filteredChildProjects : childProjects
    }

    private var activeNotes: [Note] {
        return isSearching ? filteredNotes : notes
    }

    // MARK: - Toolbar

    private func configureToolbar() {
        let flexLeft = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let flexRight = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        noteCountItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        noteCountItem.isEnabled = false
        noteCountItem.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.secondaryLabel
        ], for: .disabled)

        let composeButton = UIBarButtonItem(barButtonSystemItem: .compose, target: self, action: #selector(newNoteAction))

        toolbarItems = [flexLeft, noteCountItem, flexRight, composeButton]
    }

    private func updateNoteCount() {
        let count = activeNotes.count
        if count == 1 {
            noteCountItem.title = "1 Note"
        } else {
            noteCountItem.title = "\(count) Notes"
        }
    }

    @objc private func newNoteAction() {
        let note = Note(name: "", project: project)
        if note.save() {
            Storage.shared().add(note)
        }

        let evc = UIApplication.getEVC()
        if let editArea = evc.editArea, let u = editArea.undoManager {
            u.removeAllActions()
        }
        evc.fill(note: note)

        if let controllers = navigationController?.viewControllers,
           !controllers.contains(where: { $0 is EditorViewController }) {
            navigationController?.pushViewController(evc, animated: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if note.previewState {
                evc.togglePreview()
            }
            evc.editArea?.becomeFirstResponder()
        }
    }

    // MARK: - UITableViewDataSource

    private var hasFolders: Bool { !activeChildProjects.isEmpty }

    func numberOfSections(in tableView: UITableView) -> Int {
        return hasFolders ? 2 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if hasFolders && section == 0 {
            return activeChildProjects.count
        }
        return activeNotes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if hasFolders && indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "folderCell", for: indexPath) as! FolderCellView
            cell.configure(project: activeChildProjects[indexPath.row])
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "noteCell", for: indexPath) as! NoteSummaryCell
        let currentNotes = activeNotes
        guard currentNotes.indices.contains(indexPath.row) else { return cell }
        let note = currentNotes[indexPath.row]
        if !note.isLoaded && !note.isLoadedFromCache {
            note.uiLoad()
        }
        cell.configure(note: note)
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if hasFolders && indexPath.section == 0 {
            let child = activeChildProjects[indexPath.row]
            let vc = FolderViewController(project: child)
            navigationController?.pushViewController(vc, animated: true)
            return
        }

        let currentNotes = activeNotes
        guard currentNotes.indices.contains(indexPath.row) else { return }
        let note = currentNotes[indexPath.row]
        note.loadPreviewState()

        let evc = UIApplication.getEVC()
        if let editArea = evc.editArea, let u = editArea.undoManager {
            u.removeAllActions()
        }

        evc.fill(note: note, clearPreview: true)

        if let controllers = navigationController?.viewControllers,
           !controllers.contains(where: { $0 is EditorViewController }) {
            navigationController?.pushViewController(evc, animated: true)
        }
    }
}

// MARK: - Note Summary Cell (programmatic, no XIB needed)

class NoteSummaryCell: UITableViewCell {

    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let previewLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.font = UIFont.systemFont(ofSize: 15)
        dateLabel.textColor = .secondaryLabel
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)

        previewLabel.font = UIFont.systemFont(ofSize: 15)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 1
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        let secondRow = UIStackView(arrangedSubviews: [dateLabel, previewLabel])
        secondRow.axis = .horizontal
        secondRow.spacing = 6
        secondRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, secondRow])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    func configure(note: Note) {
        titleLabel.text = note.getTitle() ?? note.getFileName()

        dateLabel.text = note.getDateForLabel()

        previewLabel.text = note.preview
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        dateLabel.text = nil
        previewLabel.text = nil
    }
}
