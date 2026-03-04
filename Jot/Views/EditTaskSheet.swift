import SwiftUI

struct EditTaskSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var person: String
    @State private var note: String

    private let task: Task
    private let onSave: (Task) -> Void

    init(task: Task, onSave: @escaping (Task) -> Void) {
        self.task = task
        self.onSave = onSave
        _title = State(initialValue: task.title)
        _person = State(initialValue: task.person ?? "")
        _note = State(initialValue: task.note ?? "")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.96, blue: 0.98), Color(red: 0.91, green: 0.94, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Edit Task")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text("Update details and save changes instantly.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Group {
                    labeledField("Title", text: $title, prompt: "Task title")
                    labeledField("Person", text: $person, prompt: "Who is this with?")
                    labeledField("Note", text: $note, prompt: "Optional note")
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var edited = task
                    edited.title = TaskTextFormatter.formattedTitle(title)
                    edited.person = TaskTextFormatter.formattedPerson(person)
                    edited.note = TaskTextFormatter.formattedNote(note)
                    onSave(edited)
                    dismiss()
                }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
            .padding(14)
        }
        .frame(width: 480, height: 330)
    }

    private func labeledField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.4)

            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.66))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.82), lineWidth: 1)
                        )
                )
        }
    }
}
