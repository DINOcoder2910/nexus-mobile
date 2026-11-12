import EventKit
import EventKitUI
import SwiftUI

/// What the calendar's sheet shows: an event (the system's event view, with Edit and Delete), or a new event at a time.
enum EventSheet: Identifiable {
    case show(EKEvent)
    case new(Date)

    var id: String {
        switch self {
        case .show(let e): return "show|\(e.eventIdentifier ?? "")|\(e.startDate?.timeIntervalSince1970 ?? 0)"
        case .new(let d): return "new|\(d.timeIntervalSince1970)"
        }
    }
}

extension View {
    /// The system's event sheets over this view, for the calendar's taps.
    func eventSheet(_ item: Binding<EventSheet?>, store: CalendarStore) -> some View {
        sheet(item: item) { s in
            switch s {
            case .show(let e):
                EventDetailSheet(event: e) { item.wrappedValue = nil; store.reloadCalendars() }
                    .ignoresSafeArea()
            case .new(let d):
                EventEditSheet(store: store.ek, start: d) { item.wrappedValue = nil; store.reloadCalendars() }
                    .ignoresSafeArea()
            }
        }
    }
}

/// The system's event view (what Apple's Calendar shows): details, Edit, Delete, the reply to an invitation.
struct EventDetailSheet: UIViewControllerRepresentable {
    let event: EKEvent
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = EKEventViewController()
        vc.event = event
        vc.allowsEditing = true
        vc.allowsCalendarPreview = true
        vc.delegate = context.coordinator
        let done = onDone
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { _ in done() })
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, EKEventViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) { onDone() }
    }
}

/// The system's new-event form, starting at a time, saved to the default calendar unless another is picked.
struct EventEditSheet: UIViewControllerRepresentable {
    let store: EKEventStore
    let start: Date
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = store
        let e = EKEvent(eventStore: store)
        e.startDate = start
        e.endDate = start.addingTimeInterval(3600)
        if let c = store.defaultCalendarForNewEvents { e.calendar = c }
        vc.event = e
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { onDone() }
    }
}
