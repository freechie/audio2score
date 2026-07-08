//
//  ContentView.swift
//  Audio2Score
//
//  Created by richie on 7/8/26.
//

import SwiftUI

struct ContentView: View {
    private let transcription: TranscriptionResult?

    init() {
        transcription = try? TranscriptionLoader.loadDemo()
    }

    var body: some View {
        VStack(spacing: 12) {
            if let transcription {
                Text("Audio2Score")
                    .font(.title)
                    .bold()
                Text("Engine: \(transcription.engine)")
                Text("Key: \(transcription.keyGuess)")
                Text("Tempo: \(transcription.tempoBpm, specifier: "%.0f") BPM")
                Text("Notes: \(transcription.noteEvents.count)")
            } else {
                Text("Failed to load demo transcription")
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
