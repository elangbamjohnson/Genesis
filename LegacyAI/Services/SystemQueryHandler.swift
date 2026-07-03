//
//  SystemQueryHandler.swift
//  Genesis
//
//  Created by Johnson Elangbam on 03/07/26.
//

import Foundation

/// Produces the real, verifiable answer for time/date questions, read
/// directly from the device clock. Intent detection (recognizing that a
/// question IS a time/date question, however it's phrased) is handled
/// upstream by MemoryRouterService — this type only ever answers, never
/// decides, since the actual time must come from the system clock, not
/// from anything the model generates. Phrasing is varied by picking
/// randomly from a set of natural templates, but the time/date value
/// itself is always the real, computed one — never touched by the LLM.
enum SystemQueryHandler {

    static func currentTimeAnswer() -> String {
        let time = formattedTime()
        let date = formattedDate()
        return timeTemplates.randomElement()?(time, date) ?? "Right now it's \(time), on \(date)."
    }

    static func currentDateAnswer() -> String {
        let date = formattedDate()
        return dateTemplates.randomElement()?(date) ?? "Today is \(date)."
    }

    private static let timeTemplates: [(String, String) -> String] = [
        { time, date in "Right now it's \(time), on \(date)." },
        { time, date in "It's \(time) at the moment — \(date)." },
        { time, date in "Looks like it's \(time) right now, \(date)." },
        { time, date in "Just checked — it's \(time) on \(date)." },
        { time, date in "\(time) right now, on \(date)." },
        { time, date in "The clock says \(time), \(date)." }
    ]

    private static let dateTemplates: [(String) -> String] = [
        { date in "Today is \(date)." },
        { date in "It's \(date) today." },
        { date in "Looks like today's \(date)." },
        { date in "Checked the calendar — it's \(date)." }
    ]

    private static func formattedTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    private static func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
