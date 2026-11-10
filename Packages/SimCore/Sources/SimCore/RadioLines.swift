import Foundation

/// Everything said on the radio by recorded voices. The `id` is the recording's file name (App/Sounds/voice_<id>.wav);
/// the text is shown as a caption, and spoken by the game's own voice if the recording is missing.
public struct RadioLine: Equatable, Sendable {
    public enum Speaker: String, Sendable { case dispatcher, dj, bigMike, smoothRider }

    public let id: String
    public let speaker: Speaker
    public let text: String

    public var fileName: String { "voice_" + id }

    /// "Dispatch: ..." / "Big Mike on the CB: ..." for captions and the spoken fallback.
    public var caption: String {
        switch speaker {
        case .dispatcher: return "Dispatch: " + text
        case .dj: return "Radio: " + text
        case .bigMike: return "Big Mike on the CB: " + text
        case .smoothRider: return "Smooth Rider on the CB: " + text
        }
    }

    /// Goes through the CB radio (crackle, narrow sound) rather than the truck's music radio.
    public var overCB: Bool { speaker != .dj }

    init(_ id: String, _ speaker: Speaker, _ text: String) { self.id = id; self.speaker = speaker; self.text = text }
}

public enum RadioLines {
    public static let dispatchStart: [RadioLine] = [
        RadioLine("dispatch_start_1", .dispatcher, "Dispatch to driver, come in. Your load is ready and the road is clear. Drive safe out there."),
        RadioLine("dispatch_start_2", .dispatcher, "Morning, driver! Dispatch here. Paperwork's done, cargo's loaded. Go get 'em."),
        RadioLine("dispatch_start_3", .dispatcher, "Dispatch here. Another day, another delivery. Holler if you need anything. Well, you can't actually holler at me, but you know what I mean."),
    ]
    public static let dispatchStorm = RadioLine("dispatch_storm", .dispatcher, "Dispatch to driver, heads up. There's a big storm rolling in. Roads are slick, so take the curves slow and give yourself extra room to brake.")
    public static let dispatchLate = RadioLine("dispatch_late", .dispatcher, "Dispatch to driver. The client's calling about that load. No pressure. Okay, a little pressure.")
    public static let dispatchJokes: [RadioLine] = [
        RadioLine("dispatch_joke_1", .dispatcher, "Dispatch here, just checking in. The boss says if you're early, there's donuts. I may have already eaten them."),
        RadioLine("dispatch_joke_2", .dispatcher, "Driver, quick question from the office. Does that truck radio play anything besides country? Asking for a friend."),
    ]

    public static func storyBriefing(_ m: StoryMission) -> RadioLine { RadioLine("story_\(m.id)_brief", .dispatcher, m.briefing) }
    public static func storySuccess(_ m: StoryMission) -> RadioLine { RadioLine("story_\(m.id)_done", .dispatcher, m.success) }

    public static let dj: [RadioLine] = [
        RadioLine("dj_1", .dj, "You're listening to Big Rig Radio, keeping the wheels turning all night long. Here's another one for the road."),
        RadioLine("dj_2", .dj, "Big Rig Radio! Shout out to everybody hauling cattle out of Bayview. Moo if you can hear me."),
        RadioLine("dj_3", .dj, "That was a good one. Stay in your lane, check your mirrors, and keep it rolling with Big Rig Radio."),
        RadioLine("dj_4", .dj, "Quick traffic report: the toll booths on Interstate 40 are open, so slow down and keep five dollars handy. Now, back to the music."),
    ]
    public static func djWeather(_ w: Weather) -> RadioLine {
        switch w {
        case .clear: return RadioLine("dj_weather_clear", .dj, "Weather report: clear skies across the whole map. Perfect trucking weather. Enjoy it.")
        case .rain: return RadioLine("dj_weather_rain", .dj, "Weather report: rain moving through, and the roads are wet. Ease off the gas, folks.")
        case .storm: return RadioLine("dj_weather_storm", .dj, "Weather report: a storm is hitting hard. Thunder, lightning, the works. Slow down and stay safe out there.")
        case .snow: return RadioLine("dj_weather_snow", .dj, "Weather report: snow across the map, and the roads are icy. Chains on if you've got them, and take it slow.")
        }
    }

    public static let cb: [RadioLine] = [
        RadioLine("cb_1", .bigMike, "Breaker breaker, this is Big Mike heading east on the interstate. There's a police car by the toll booth, so keep it legal, folks."),
        RadioLine("cb_2", .bigMike, "Anybody out there? I've got a load of chickens back here and they will not stop talking."),
        RadioLine("cb_3", .bigMike, "Big Mike here. Watch out for deer on the mountain road. Almost hit one the size of my truck."),
        RadioLine("cb_4", .bigMike, "Big Mike again. Just rolled past the steel mill in Ironton. Smells like hot metal and money."),
        RadioLine("cb_5", .smoothRider, "Copy that, Big Mike. This is Smooth Rider. Coffee's fresh at the Central Junction truck stop."),
        RadioLine("cb_6", .smoothRider, "Smooth Rider here. Construction zone up ahead, only one lane open. Take it slow."),
        RadioLine("cb_7", .smoothRider, "Hey, whoever's blasting that train horn out on the country road, that's the best thing I've heard all week."),
        RadioLine("cb_8", .smoothRider, "Smooth Rider, signing off. Ten four, good buddy. Keep the shiny side up."),
    ]

    /// Every line, for the recordings.
    public static var all: [RadioLine] {
        var lines: [RadioLine] = dispatchStart
        lines.append(dispatchStorm)
        lines.append(dispatchLate)
        lines += dispatchJokes
        for m in StoryMission.all { lines += [storyBriefing(m), storySuccess(m)] }
        lines += dj
        for w in Weather.allCases { lines.append(djWeather(w)) }
        lines += cb
        return lines
    }
}
