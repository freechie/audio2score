//
//  TranscriptLoader.swift
//  Audio2Score
//
//  Created by richie on 7/8/26.
//

import Foundation

enum TranscriptionLoader {
    static func loadDemo(from bundle: Bundle = .main) throws -> TranscriptionResult {
        guard let url = Bundle.main.url(
            forResource: "transcription.example",
            withExtension: "json"
        ) else {
            throw LoaderError.missingDemoJSON
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try decoder.decode(TranscriptionResult.self, from: data)
    }
    enum LoaderError: Error {
        case missingDemoJSON
    }
}
