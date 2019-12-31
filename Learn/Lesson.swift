//
//  Lesson.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import UIKit


protocol Lesson {
    init(dataManager: DataManager)

    var title: String { get }

    var subtitle: String { get }

    var configurationSections: [LessonSectionProviding] { get }

    func execute(completion: @escaping (_ resultSections: [LessonSectionProviding]) -> Void)
}


protocol LessonSectionProviding {
    var headerTitle: String? { get }

    var footerTitle: String? { get }

    var cells: [LessonCellProviding] { get }
}

extension LessonSectionProviding {
    var headerTitle: String? {
        return nil
    }

    var footerTitle: String? {
        return nil
    }
}


protocol LessonCellProviding {
    func registerCell(for tableView: UITableView)

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
}


struct LessonSection: LessonSectionProviding {
    let headerTitle: String?

    let footerTitle: String?

    let cells: [LessonCellProviding]

    init(headerTitle: String? = nil, footerTitle: String? = nil, cells: [LessonCellProviding]) {
        self.headerTitle = headerTitle
        self.footerTitle = footerTitle
        self.cells = cells
    }
}
