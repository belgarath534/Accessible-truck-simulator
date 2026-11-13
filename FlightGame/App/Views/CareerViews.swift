import FlightCore
import SwiftUI

/// The job board: paid flights from the airport your plane is at.
struct JobsView: View {
    @EnvironmentObject private var settings: FlightSettings
    let start: (FlightRequest) -> Void

    private var career: PilotCareer { settings.career }

    var body: some View {
        List {
            Section {
                Text("\(career.rank.title). \(Phrases.money(career.money)) in the bank.")
                    .font(.headline)
                if let next = career.rank.next {
                    let left = next.flightsNeeded - career.flightsDone
                    Text("\(left) more paid flight\(left == 1 ? "" : "s") to \(next.title), which unlocks \(unlocks(next)).")
                }
                Text("Your plane is at \(career.locationName), in \(career.conditionPercent) percent condition.")
            }
            if career.canFlyJobs {
                Section {
                    ForEach(career.board) { job in
                        Button {
                            start(request(for: job))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(label(job.kind)): \(job.load)").font(.headline)
                                Text("To \(job.toName), \(Units.distance(job.distance)). Pays \(Phrases.money(job.pay)).")
                                if job.kind.carriesPeople { Text("Fly smoothly: happy passengers tip.").font(.subheadline) }
                            }
                        }
                        .accessibilityHint("Starts the flight from \(job.fromName).")
                    }
                } header: {
                    Text("Flights from \(career.locationName)")
                } footer: {
                    Text("You're paid for landing at the destination. A soft landing pays a bonus. Crashes pay nothing and damage the plane.")
                }
            } else {
                Section {
                    Text(career.mechanicReport)
                    NavigationLink("Go to the Mechanic") { MechanicView() }
                }
            }
        }
        .navigationTitle("Pilot Jobs")
    }

    private func label(_ kind: JobKind) -> String {
        switch kind {
        case .mail: return "Mail"
        case .cargo: return "Cargo"
        case .passengers: return "Passengers"
        case .medical: return "Medical"
        case .vip: return "V I P"
        }
    }

    private func unlocks(_ rank: PilotRank) -> String {
        switch rank {
        case .student: return "mail and cargo"
        case .privatePilot: return "passenger flights"
        case .commercial: return "medical flights"
        case .captain: return "V I P flights"
        }
    }

    private func request(for job: FlightJob) -> FlightRequest {
        let from = World.airport(job.from) ?? World.airports[0]
        let to = World.airport(job.to) ?? World.airports[1]
        var text = "\(label(job.kind)) flight. \(job.load) to \(to.name), \(Units.distance(job.distance)), heading about \(Units.headingWords(World.bearing(fromX: from.x, y: from.y, to: to))). Pays \(Phrases.money(job.pay))."
        if job.kind.carriesPeople { text += " Your passengers are aboard: gentle turns, and easy on the climbs and descents." }
        if settings.career.powerFactor < 1 { text += " The engine is worn, so the takeoff will be longer." }
        text += " You're lined up on \(from.runwayName). Start the engine when you're ready."
        var r = FlightRequest(title: "\(job.load) to \(to.name)", start: .runway(job.from), goal: .flyTo(job.to), lesson: nil, briefing: text)
        r.job = job
        return r
    }
}

/// The mechanic: the plane's condition and repairs.
struct MechanicView: View {
    @EnvironmentObject private var settings: FlightSettings
    @State private var message: String?

    private var career: PilotCareer { settings.career }

    var body: some View {
        List {
            Section {
                Text("Condition: \(career.conditionPercent) percent.").font(.headline)
                Text(career.mechanicReport)
                if career.powerFactor < 1 {
                    Text("Engine power: \(Int((career.powerFactor * 100).rounded())) percent.")
                }
            }
            Section {
                if career.repairCost > 0 {
                    Button("Full Repair: \(Phrases.money(career.repairCost))") { repair() }
                        .font(.title3.bold())
                    Text("You have \(Phrases.money(career.money)).")
                } else {
                    Text("Nothing to fix.")
                }
                if let message { Text(message) }
            } footer: {
                Text("Every flight wears the plane a little. Firm and hard landings wear it more, and a crash does real damage. A worn engine makes less power. Lessons and the tutorial use the flight school's plane, so they never wear yours.")
            }
        }
        .navigationTitle("Mechanic")
    }

    private func repair() {
        if settings.repairPlane() {
            message = "Repaired. Your plane is as good as new."
        } else if settings.emergencyRepair() {
            message = "You can't afford a full repair, so the mechanic patched the plane up for free. It's safe to fly jobs again."
        } else {
            message = "You need \(Phrases.money(career.repairCost)) for a full repair. Fly some jobs first."
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
