import UIKit

@MainActor
final class TeakDemoLanguageListViewController: UITableViewController {
    private let files = TeakDemoFiles()
    private var samples: [TeakDemoLanguageSamples] = []
    private var operation: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Teak Languages")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let samples = try await self.files.catalog()
                try Task.checkCancellation()
                self.samples = samples
                self.tableView.reloadData()
            } catch is CancellationError {} catch {
                let label = UILabel()
                label.text = String(localized: "Could not load demo files") + "\n" + error.localizedDescription
                label.textAlignment = .center
                label.numberOfLines = 0
                self.tableView.backgroundView = label
            }
        }
    }

    deinit { operation?.cancel() }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        samples.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellID)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: Constants.cellID)
        let sample = samples[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = String(localized: String.LocalizationValue(sample.displayName))
        content.secondaryText = String(format: String(localized: "Normal: %@ · %@\nLarge: %@ · %@"),
            sample.normal.fileName, sample.normal.sizeDescription, sample.large.fileName, sample.large.sizeDescription)
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(TeakDemoViewController(samples: samples[indexPath.row]), animated: true)
    }
}

private extension TeakDemoLanguageListViewController {
    enum Constants {
        static let cellID = "language"
    }
}
