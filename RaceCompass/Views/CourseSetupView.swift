import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

struct CourseSetupView: View {
    @ObservedObject var waypointStore: WaypointStore
    @Binding var isPresented: Bool
    var currentLocation: CLLocation?
    var onCourseSet: (CLLocation?, CLLocation?) -> Void  // (pinLocation, stbdStartLocation)

    @State private var showingFilePicker = false
    @State private var showingWaypointPicker = false
    @State private var showingNamePrompt = false
    @State private var newWaypointName = ""
    @State private var pickerMode: PickerMode = .portStart
    @State private var importMessage: String? = nil

    enum PickerMode {
        case portStart
        case stbdStart
        case mark
        case endPin
    }

    // Check if start line is fully configured
    private var isStartLineReady: Bool {
        waypointStore.portStart != nil && waypointStore.firstMark != nil
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    // START LINE SECTION
                    Section(header: Text("START LINE")) {
                        // Port Start (Pin)
                        Button(action: { pickerMode = .portStart; showingWaypointPicker = true }) {
                            HStack {
                                Image(systemName: "flag.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 30)
                                Text("Port Start")
                                    .foregroundColor(.primary)
                                Spacer()
                                if let wp = waypointStore.portStart {
                                    Text(wp.name)
                                        .foregroundColor(.green)
                                        .fontWeight(.semibold)
                                } else {
                                    Text("Select")
                                        .foregroundColor(.gray)
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }

                        // Stbd Start (RC Boat) - selectable or auto
                        Button(action: { pickerMode = .stbdStart; showingWaypointPicker = true }) {
                            HStack {
                                Image(systemName: "flag.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 30)
                                Text("Stbd Start (RCB)")
                                    .foregroundColor(.primary)
                                Spacer()
                                if let wp = waypointStore.stbdStart {
                                    Text(wp.name)
                                        .foregroundColor(.green)
                                        .fontWeight(.semibold)
                                } else if isStartLineReady {
                                    Text("Auto (50')")
                                        .foregroundColor(.blue)
                                } else {
                                    Text("Select or Auto")
                                        .foregroundColor(.gray)
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }

                    // COURSE MARKS SECTION
                    Section(header: Text("COURSE MARKS")) {
                        // Existing marks
                        ForEach(Array(waypointStore.courseMarks.enumerated()), id: \.element.id) { index, mark in
                            HStack {
                                Image(systemName: "\(index + 1).circle.fill")
                                    .foregroundColor(.orange)
                                    .frame(width: 30)
                                Text(mark.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if index == 0 {
                                    Text("(Windward)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .onDelete(perform: deleteMark)

                        // Add mark button
                        Button(action: { pickerMode = .mark; showingWaypointPicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 30)
                                Text("Add Mark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    // FINISH SECTION
                    Section(header: Text("FINISH")) {
                        Button(action: { pickerMode = .endPin; showingWaypointPicker = true }) {
                            HStack {
                                Image(systemName: "flag.checkered")
                                    .foregroundColor(.black)
                                    .frame(width: 30)
                                Text("End Pin")
                                    .foregroundColor(.primary)
                                Spacer()
                                if let wp = waypointStore.endPin {
                                    Text(wp.name)
                                        .foregroundColor(.green)
                                        .fontWeight(.semibold)
                                } else {
                                    Text("Select")
                                        .foregroundColor(.gray)
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }

                    // WAYPOINTS SECTION
                    Section(header: Text("IMPORTED WAYPOINTS (\(waypointStore.waypoints.count))")) {
                        if waypointStore.waypoints.isEmpty {
                            Text("No waypoints imported")
                                .foregroundColor(.gray)
                                .italic()
                        } else {
                            ForEach(waypointStore.waypoints) { waypoint in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(waypoint.name)
                                        .fontWeight(.medium)
                                    Text(String(format: "%.5f, %.5f", waypoint.latitude, waypoint.longitude))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .onDelete(perform: deleteWaypoints)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())

                // Import Message
                if let message = importMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.vertical, 4)
                }

                // Bottom Buttons
                VStack(spacing: 10) {
                    // Add from GPS button
                    if currentLocation != nil {
                        Button(action: {
                            newWaypointName = "Mark \(waypointStore.waypoints.count + 1)"
                            showingNamePrompt = true
                        }) {
                            Label("Add Mark at Current Position", systemImage: "location.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }

                    HStack(spacing: 15) {
                        Button(action: { showingFilePicker = true }) {
                            Label("Import GPX", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        Button(action: {
                            waypointStore.clearCourse()
                            onCourseSet(nil, nil)
                        }) {
                            Label("Clear Course", systemImage: "xmark.circle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Course Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        let pinLocation = waypointStore.portStart?.location
                        let stbdLocation = waypointStore.stbdStartLocation()
                        onCourseSet(pinLocation, stbdLocation)
                        isPresented = false
                    }
                    .fontWeight(.bold)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        let count = waypointStore.importGPX(from: url)
                        importMessage = "Imported \(count) waypoints"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            importMessage = nil
                        }
                    }
                case .failure(let error):
                    print("Import failed: \(error)")
                    importMessage = "Import failed"
                }
            }
            .sheet(isPresented: $showingWaypointPicker) {
                WaypointPickerView(
                    waypoints: waypointStore.waypoints,
                    title: pickerTitle,
                    showAutoOption: pickerMode == .stbdStart,
                    onSelect: { waypoint in
                        handleWaypointSelection(waypoint)
                        showingWaypointPicker = false
                    }
                )
            }
            .alert("Name This Mark", isPresented: $showingNamePrompt) {
                TextField("Mark name", text: $newWaypointName)
                Button("Cancel", role: .cancel) { }
                Button("Add") {
                    if let location = currentLocation {
                        let _ = waypointStore.addFromLocation(location, name: newWaypointName)
                        importMessage = "Added \(newWaypointName)"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            importMessage = nil
                        }
                    }
                }
            } message: {
                Text("Enter a name for this waypoint")
            }
        }
    }

    private var pickerTitle: String {
        switch pickerMode {
        case .portStart: return "Select Port Start"
        case .stbdStart: return "Select Stbd Start (RCB)"
        case .mark: return "Add Course Mark"
        case .endPin: return "Select End Pin"
        }
    }

    private func handleWaypointSelection(_ waypoint: Waypoint?) {
        switch pickerMode {
        case .portStart:
            waypointStore.setPortStart(waypoint)
        case .stbdStart:
            waypointStore.setStbdStart(waypoint)  // nil = use auto-calculation
        case .mark:
            if let wp = waypoint {
                waypointStore.addCourseMark(wp)
            }
        case .endPin:
            waypointStore.setEndPin(waypoint)
        }
    }

    private func deleteMark(at offsets: IndexSet) {
        for index in offsets {
            waypointStore.removeCourseMark(at: index)
        }
    }

    private func deleteWaypoints(at offsets: IndexSet) {
        for index in offsets {
            waypointStore.remove(waypointStore.waypoints[index])
        }
    }
}

// MARK: - Waypoint Picker
struct WaypointPickerView: View {
    let waypoints: [Waypoint]
    let title: String
    var showAutoOption: Bool = false
    var onSelect: (Waypoint?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                // Auto option for Stbd Start
                if showAutoOption {
                    Button(action: {
                        onSelect(nil)  // nil = use auto-calculation
                    }) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.blue)
                            Text("Use Auto (50' perpendicular)")
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                    }
                }

                if waypoints.isEmpty {
                    Text("No waypoints available. Import a GPX file first.")
                        .foregroundColor(.gray)
                        .italic()
                } else {
                    ForEach(waypoints) { waypoint in
                        Button(action: {
                            onSelect(waypoint)
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(waypoint.name)
                                        .foregroundColor(.primary)
                                        .fontWeight(.medium)
                                    Text(String(format: "%.5f, %.5f", waypoint.latitude, waypoint.longitude))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    CourseSetupView(
        waypointStore: WaypointStore(),
        isPresented: .constant(true),
        currentLocation: CLLocation(latitude: 30.5, longitude: -87.9),
        onCourseSet: { _, _ in }
    )
}
