import FlightCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var settings: FlightSettings
    @State private var flight: FlightRequest?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        flight = .tutorial
                    } label: {
                        Text(settings.tutorialDone ? "Tutorial: Your First Flight" : "Start Here: Your First Flight").font(.title2.bold())
                    }
                    .accessibilityHint("A guided flight for people who have never flown. The instructor explains every part of the plane, one step at a time.")
                    NavigationLink {
                        JobsView { flight = $0 }
                    } label: {
                        Text("Pilot Jobs").font(.title2.bold())
                    }
                    .accessibilityHint("Paid flights: carry passengers, cargo and mail between airports. You're a \(settings.career.rank.title) with \(Phrases.money(settings.career.money)).")
                    NavigationLink {
                        LessonsView { flight = $0 }
                    } label: {
                        Text("Flight School").font(.title2.bold())
                    }
                    .accessibilityHint("Short lessons: takeoff, turns, landing and your first cross-country flight.")
                    NavigationLink {
                        FlightPlanView { flight = $0 }
                    } label: {
                        Text("Plan a Flight").font(.title2)
                    }
                    .accessibilityHint("Pick a departure and a destination airport, or fly free.")
                } footer: {
                    Text(settings.tutorialDone ? "" : "Never flown a plane? Start with Your First Flight. The instructor explains everything as you go.")
                }
                Section {
                    NavigationLink("Mechanic") { MechanicView() }
                        .accessibilityHint("Your plane's condition, \(settings.career.conditionPercent) percent, and repairs.")
                    NavigationLink("Ground School: Parts of the Plane") { GroundSchoolView() }
                    NavigationLink("How to Fly") { HowToFlyView() }
                    NavigationLink("Logbook") { LogbookView() }
                    NavigationLink("Settings") { SettingsView() }
                    NavigationLink("Credits") { CreditsView() }
                }
            }
            .navigationTitle("Flight Sim")
        }
        .fullScreenCover(item: $flight) { request in
            FlightScreen(request: request, settings: settings) { flight = nil }
        }
    }
}

struct LessonsView: View {
    @EnvironmentObject private var settings: FlightSettings
    let start: (FlightRequest) -> Void

    var body: some View {
        List {
            ForEach(Lesson.all) { lesson in
                Button {
                    start(FlightRequest(title: lesson.title, start: lesson.start, goal: lesson.goal, lesson: lesson,
                                        briefing: lesson.briefing))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lesson \(lesson.id): \(lesson.title)").font(.headline)
                        if settings.logbook.lessonsPassed.contains(lesson.id) { Text("Passed").font(.subheadline) }
                    }
                }
                .accessibilityHint("Starts the lesson. The instructor explains what to do.")
            }
        }
        .navigationTitle("Flight School")
    }
}

struct FlightPlanView: View {
    let start: (FlightRequest) -> Void
    @State private var from = World.airports[0].id
    @State private var to = World.airports[1].id
    @State private var free = false

    var body: some View {
        Form {
            Section {
                Picker("Depart from", selection: $from) {
                    ForEach(World.airports) { Text($0.name).tag($0.id) }
                }
                Toggle("Free flight, no destination", isOn: $free)
                if !free {
                    Picker("Fly to", selection: $to) {
                        ForEach(World.airports.filter { $0.id != from }) { Text($0.name).tag($0.id) }
                    }
                }
            }
            if !free, let a = World.airport(from), let b = World.airport(to), a.id != b.id {
                Section {
                    Text("\(Units.distance(World.distance(fromX: a.x, y: a.y, to: b))), heading about \(Units.headingWords(World.bearing(fromX: a.x, y: a.y, to: b))). Land on \(b.runwayName).")
                }
            }
            Section {
                Button("Start Flight") { begin() }
                    .font(.title2.bold())
                    .disabled(!free && from == to)
            }
        }
        .navigationTitle("Plan a Flight")
        .onChange(of: from) { _, new in if to == new { to = World.airports.first { $0.id != new }!.id } }
    }

    private func begin() {
        guard let a = World.airport(from) else { return }
        if free {
            start(FlightRequest(title: "Free flight", start: .runway(a.id), goal: .freeFlight, lesson: nil,
                                briefing: "Free flight from \(a.name), \(a.runwayName). Fly anywhere and land at any airport. Three-finger double tap starts the engine. Three-finger tap tells you where the nearest airport is."))
        } else if let b = World.airport(to) {
            start(FlightRequest(title: "\(a.name) to \(b.name)", start: .runway(a.id), goal: .flyTo(b.id), lesson: nil,
                                briefing: "Flight from \(a.name) to \(b.name), \(Units.distance(World.distance(fromX: a.x, y: a.y, to: b))). You're lined up on \(a.runwayName). Three-finger double tap starts the engine, two-finger swipe up for full throttle. After takeoff, follow the beacon to \(b.name). Three-finger tap for directions."))
        }
    }
}
