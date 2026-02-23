//
//  FolderCellView.swift
//  FSNotes iOS
//
//  Sub-folder cell for FolderViewController (Apple Notes style)
//

import UIKit

class FolderCellView: UITableViewCell {

    private let folderIcon = UIImageView()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        folderIcon.image = UIImage(systemName: "folder.fill")
        folderIcon.tintColor = .systemYellow
        folderIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(folderIcon)

        nameLabel.font = UIFont.systemFont(ofSize: 17)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        countLabel.font = UIFont.systemFont(ofSize: 15)
        countLabel.textColor = .secondaryLabel
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(countLabel)

        accessoryType = .disclosureIndicator

        NSLayoutConstraint.activate([
            folderIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            folderIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            folderIcon.widthAnchor.constraint(equalToConstant: 24),
            folderIcon.heightAnchor.constraint(equalToConstant: 24),

            nameLabel.leadingAnchor.constraint(equalTo: folderIcon.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -8),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    func configure(project: Project) {
        nameLabel.text = project.label
        let count = Self.countNotes(in: project)
        countLabel.text = count > 0 ? "\(count)" : ""
    }

    private static func countNotes(in project: Project) -> Int {
        let storage = Storage.shared()
        var count = storage.noteList.filter { $0.project == project && !$0.isTrash() }.count
        for child in project.child {
            count += countNotes(in: child)
        }
        return count
    }
}
