//
//  EntriesViewDataSource.swift
//  Gigapet
//
//  Created by Jon Bash on 2020-01-07.
//  Copyright © 2020 Jon Bash. All rights reserved.
//

import UIKit
import PieCharts

protocol EntriesViewDataDelegate: AnyObject {
    func entryDeletionDidFail(withError error: Error)
}

class EntriesViewDataSource: NSObject {

    // MARK: - Properties

    weak var foodEntryController: FoodEntryController?
    weak var delegate: EntriesViewDataDelegate?

    private(set) var currentDisplayType: EntryDisplayType
    private(set) var entryPeriodsByDisplayType = [EntryDisplayType: [EntryDisplayPeriod]]()
    private(set) var currentReferenceDate = Date()

    private lazy var percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    // MARK: Computed

    private(set) var currentEntryPeriods: [EntryDisplayPeriod] {
        get {
            if let currentPeriods = entryPeriodsByDisplayType[currentDisplayType] {
                return currentPeriods
            } else {
                let currentPeriods = entryPeriods(for: currentDisplayType)
                entryPeriodsByDisplayType[currentDisplayType] = currentPeriods
                return currentPeriods
            }
        } set {
            entryPeriodsByDisplayType[currentDisplayType] = newValue
        }
    }
    private(set) var currentEntryPeriod: EntryDisplayPeriod? {
        get {
            if let index = currentEntryPeriodIndex {
                return currentEntryPeriods[index]
            } else { return nil }
        } set {
            if let index = currentEntryPeriodIndex {
                guard let newPeriod = newValue else {
                    currentEntryPeriods.remove(at: index)
                    return
                }
                currentEntryPeriods[index] = newPeriod
            } else {
                guard let newPeriod = newValue else { return }
                currentEntryPeriods.append(newPeriod)
                currentReferenceDate = newPeriod.referenceDate
            }
        }
    }
    private var currentEntryPeriodIndex: Int? {
        return currentEntryPeriods.firstIndex {
            $0.startDateComponents == currentDateComponents
        }
    }

    private var currentDateComponents: DateComponents? {
        currentReferenceDate.components(for: currentDisplayType)
    }

    // MARK: - Init

    init(
        foodEntryController: FoodEntryController?,
        startingDisplayType: EntryDisplayType = .all
    ) {
        self.currentDisplayType = startingDisplayType
        self.foodEntryController = foodEntryController

        super.init()

        self.entryPeriodsByDisplayType = [
            startingDisplayType: entryPeriods(for: startingDisplayType)
        ]
    }

    // MARK: - Entry Periods API

    func change(displayType: EntryDisplayType) {
        self.currentDisplayType = displayType
    }

    func changeDate(incrementing: Bool) {
        currentReferenceDate = currentReferenceDate
            .incremented(incrementing, by: currentDisplayType)
    }

    func entryWasAdded() {
        // TODO: handle more efficiently
        entryPeriodsByDisplayType = [:]
        currentEntryPeriods = entryPeriods(for: currentDisplayType)
    }

    // MARK: - Pie Charts API

    func getPieChartInfo()
        -> (models: [PieSliceModel], layers: [PiePlainTextLayer])
    {
        guard let entries = currentEntryPeriod?.entries else {
            return (models: [], layers: [])
        }

        var categoryCounts = [FoodCategory: Int]()
        for entry in entries {
            guard
                let categoryString = entry.foodCategory,
                let category = FoodCategory(rawValue: categoryString)
                else { continue }

            let currentCount = categoryCounts[category] ?? 0
            categoryCounts[category] = currentCount + Int(entry.foodAmount)
        }

        var models = [PieSliceModel]()
        var layers = [PiePlainTextLayer]()

        for category in categoryCounts.keys {
            models.append(PieSliceModel(
                value: Double(categoryCounts[category] ?? 0),
                color: category.color))

            let layer = PiePlainTextLayer()
            let layerSettings = PiePlainTextLayerSettings()
            layerSettings.label.textGenerator = { slice in
                return self.percentFormatter
                    .string(from: slice.data.percentage * 100 as NSNumber)
                    .map{"\($0)%"} ?? ""
            }
            layer.settings = layerSettings

            layers.append(layer)
        }

        return (models: models, layers: layers)
    }

    // MARK: - Private

    private func entryPeriods(
        for displayType: EntryDisplayType
    ) -> [EntryDisplayPeriod] {
        guard let entries = foodEntryController?.entries else { return [] }

        if displayType == .all {
            return [EntryDisplayPeriod(
                type: displayType,
                entries: entries,
                referenceDate: Date())]
        }

        var entryPeriods = [EntryDisplayPeriod]()

        for entry in entries {
            if let periodIndex = entryPeriods.firstIndex(where: {
                $0.startDateComponents == entry
                    .dateFed?.components(for: displayType)
            }) {
                entryPeriods[periodIndex].entries.append(entry)
            } else {
                entryPeriods.append(EntryDisplayPeriod(
                    type: displayType,
                    entries: [entry],
                    referenceDate: entry.dateFed ?? Date()))
            }
        }

        entryPeriods.sort { $0.referenceDate < $1.referenceDate }

        return entryPeriods
    }
}

// MARK: - Table Data Source

extension EntriesViewDataSource: UITableViewDataSource {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        return currentEntryPeriod?.entries.count ?? 0
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if currentDisplayType == .all {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "EntryCell",
                for: indexPath)
                as? EntryTableViewCell
                else { return UITableViewCell() }
            cell.entry = currentEntryPeriod?.entries[indexPath.row]

            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "EntryCell",
                for: indexPath)
                as? EntryTableViewCell
                else { return UITableViewCell() }
            return cell
        }
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        if editingStyle == .delete,
            let entry = foodEntryController?.entries[indexPath.row] {
            currentEntryPeriod?.entries.removeAll(where: { $0 == entry })
            foodEntryController?.deleteFoodEntry(entry) { [weak self] result in
                DispatchQueue.main.async {
                    if let error = result {
                        self?.delegate?.entryDeletionDidFail(withError: error)
                    } else {
                        tableView.deleteRows(at: [indexPath], with: .automatic)
                    }
                }
            }
        }
    }
}
