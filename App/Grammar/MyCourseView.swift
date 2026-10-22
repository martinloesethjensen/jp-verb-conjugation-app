import SwiftUI
import VerbKit

/// Settings › Grammar › My course: pick textbooks to start from, then edit the lessons.
struct MyCourseView: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(CourseStore.self) private var courseStore
    @State private var selectedBooks: Set<String> = []
    @State private var confirmingReset = false
    @State private var addingLesson = false
    @State private var newLessonName = ""
    @State private var renaming: CourseLesson?
    @State private var renameText = ""
    @State private var pickingFor: CourseLesson?
    @State private var deleting: CourseLesson?

    private var points: [GrammarPoint] { verbStore.grammarPoints }
    private var textbooks: [Textbook] { verbStore.textbooks }

    var body: some View {
        Group {
            if let course = courseStore.course {
                courseList(course)
            } else {
                startForm
            }
        }
        .navigationTitle("My course")
    }

    // MARK: - No course

    private var startForm: some View {
        Form {
            Section {
                ForEach(textbooks) { book in
                    Toggle(book.title, isOn: Binding(
                        get: { selectedBooks.contains(book.id) },
                        set: { on in if on { selectedBooks.insert(book.id) } else { selectedBooks.remove(book.id) } }
                    ))
                }
            } header: {
                Text("Start from")
            } footer: {
                Text("Textbook lessons are matched by us and marked unreviewed until checked.")
            }
            Section {
                Button("Create course") {
                    let ids = textbooks.map(\.id).filter(selectedBooks.contains)
                    courseStore.start(from: ids, points: points, textbooks: textbooks)
                }
                .disabled(points.isEmpty || selectedBooks.isEmpty)
                Button("Start empty") {
                    courseStore.start(from: [], points: points, textbooks: textbooks)
                }
                .disabled(points.isEmpty)
            }
        }
    }

    // MARK: - Course

    private func courseList(_ course: MyCourse) -> some View {
        let lessons = course.resolved(points: points, textbooks: textbooks)
        return List {
            ForEach(lessons) { lesson in
                Section {
                    if lesson.grammarIDs.isEmpty {
                        Text("No grammar yet").foregroundStyle(.secondary)
                    }
                    ForEach(lesson.grammarIDs, id: \.self) { id in
                        if let point = points.first(where: { $0.id == id }) {
                            JapaneseText(point.title)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { lesson.grammarIDs[$0] }
                        courseStore.edit { course in
                            for id in ids { course.remove(id, from: lesson.id, points: points, textbooks: textbooks) }
                        }
                    }
                    .onMove { source, destination in
                        var ids = lesson.grammarIDs
                        ids.move(fromOffsets: source, toOffset: destination)
                        courseStore.edit { $0.setOrder(ids, in: lesson.id, points: points, textbooks: textbooks) }
                    }
                } header: {
                    lessonHeader(lesson)
                }
            }
            Section {
                Button("Reset course", role: .destructive) { confirmingReset = true }
            }
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button("Add lesson") { newLessonName = ""; addingLesson = true }
            }
        }
        .confirmationDialog("Reset My course? Your lessons and edits will be removed.",
                            isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset course", role: .destructive) { courseStore.clear() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleting.map { "Delete “\($0.name)”?" } ?? "Delete lesson?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { lesson in
            Button("Delete lesson", role: .destructive) {
                courseStore.edit { $0.deleteLesson(lesson.id, points: points, textbooks: textbooks) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { lesson in
            Text(lesson.base == nil
                 ? "Its grammar list will be removed."
                 : "Its grammar list will be removed. A textbook lesson can only come back with Reset course.")
        }
        .alert("Add lesson", isPresented: $addingLesson) {
            TextField("Name", text: $newLessonName)
            Button("Add") {
                let name = newLessonName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                courseStore.edit { _ = $0.addLesson(named: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename lesson", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if let lesson = renaming, !name.isEmpty {
                    courseStore.edit { $0.rename(lesson.id, to: name, points: points, textbooks: textbooks) }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .sheet(item: $pickingFor) { lesson in
            GrammarPointPicker(points: points, existing: Set(lesson.grammarIDs)) { ids in
                courseStore.edit { course in
                    for id in ids { course.add(id, to: lesson.id, points: points, textbooks: textbooks) }
                }
            }
        }
    }

    private func lessonHeader(_ lesson: CourseLesson) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(lesson.name)
                if lesson.unreviewed {
                    Text("unreviewed").font(.caption).foregroundStyle(.orange).textCase(nil)
                }
            }
            Spacer()
            Menu {
                Button("Add grammar…") { pickingFor = lesson }
                Button("Rename…") { renameText = lesson.name; renaming = lesson }
                Button("Delete lesson", role: .destructive) {
                    deleting = lesson
                }
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("Lesson actions")
            }
            .textCase(nil)
        }
    }
}
