//
//  Swiftfall+BulkData.swift
//  CardService
//
//  Created by Josh Birnholz on 6/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import ReerJSON
import zlib

extension JSONDecoder.DateDecodingStrategy {
	static let iso8601withFractionalSeconds: Self = .formatted({
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .iso8601)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
		return formatter
	}())
}

/// Scryfall bulk data, served as gzipped JSONL (one JSON object per line).
/// See https://scryfall.com/docs/api/bulk-data
extension Swiftfall {

	public static func getBulkData() throws -> BulkDataList {
		let call = "\(Source.scryfall.url)bulk-data/"

		var bulkdata: Result<BulkDataList>?

		let semaphore = DispatchSemaphore(value: 0)

		parseResource(call: call, dateDecodingStrategy: .iso8601withFractionalSeconds) {
			(newbulkdata: Result<BulkDataList>) in
			bulkdata = newbulkdata
			semaphore.signal()
		}

		semaphore.wait()

		guard let bulkdata else { throw BulkDataError.noResponse }
		return try bulkdata.promote()
	}

	public struct BulkDataList: Decodable {
		public let hasMore: Bool?
		public let data: [BulkData]

		public func first(_ type: BulkData.BulkDataType) -> BulkData? {
			data.first { $0.kind == type }
		}
	}

	public struct BulkData: Decodable {
		public enum BulkDataType: String {
			case oracleCards = "oracle_cards"
			case uniqueArtwork = "unique_artwork"
			case defaultCards = "default_cards"
			case allCards = "all_cards"
			case rulings = "rulings"
			case artTags = "art_tags"
			case oracleTags = "oracle_tags"
		}

		/// A unique ID for this bulk item.
		public let id: UUID
		/// The Scryfall API URI for this file.
		public let uri: URL
		/// A computer-readable string for the kind of bulk item. Kept as a raw string so
		/// that new types Scryfall adds don't break decoding of the whole list.
		public let type: String
		/// A human-readable name for this file.
		public let name: String
		/// A human-readable description for this file.
		public let description: String
		/// The URI that hosts this bulk file (gzipped JSONL) for fetching.
		public let jsonlDownloadUri: URL
		/// The time when this file was last updated.
		public let updatedAt: Date
		/// The size of this file in integer bytes.
		public let compressedSize: Int?

		public var kind: BulkDataType? { BulkDataType(rawValue: type) }
		
		/// The stages of loading a bulk data file, in order.
		public enum Stage {
			case downloading
			case decompressing
			case decoding
		}
		
		/// Called periodically with the current stage and how far through it loading is, from 0 to 1.
		/// May be called on any thread.
		public typealias ProgressHandler = (_ stage: Stage, _ fractionCompleted: Double) -> Void

		/// Downloads this bulk file, then decodes each card and passes it to `handler`, one at a time.
		/// Lines that fail to decode are logged and skipped. Returns the number of cards decoded.
		@discardableResult
		public func forEachCard(progress: ProgressHandler? = nil, _ handler: (Card) throws -> Void) throws -> Int {
			let decoder = ReerJSONDecoder()
			decoder.keyDecodingStrategy = .convertFromSnakeCase
			decoder.dateDecodingStrategy = .formatted({ let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; return df }())
			return try forEachRecord(decoder: decoder, progress: progress, handler)
		}

		/// Downloads this bulk file, then decodes each ruling and passes it to `handler`, one at a time.
		/// Lines that fail to decode are logged and skipped. Returns the number of rulings decoded.
		@discardableResult
		public func forEachRuling(progress: ProgressHandler? = nil, _ handler: (Ruling) throws -> Void) throws -> Int {
			let decoder = ReerJSONDecoder()
			decoder.keyDecodingStrategy = .convertFromSnakeCase
			return try forEachRecord(decoder: decoder, progress: progress, handler)
		}

		private func forEachRecord<T: Decodable>(decoder: ReerJSONDecoder, progress: ProgressHandler?, _ handler: (T) throws -> Void) throws -> Int {
			print("Downloading \(type) from \(jsonlDownloadUri)")
			let fileURL = try downloadJSONLFile(progress: progress)
			// The uncompressed file is large and only needed for this import.
			defer { try? FileManager.default.removeItem(at: fileURL) }

			var decodedCount = 0
			var lineNumber = 0
			var failureCount = 0
			progress?(.decoding, 0)
			try BulkDataReader.forEachJSONLine(inFileAt: fileURL, progress: { progress?(.decoding, $0) }) { line in
				defer { lineNumber += 1 }
				let record: T
				do {
					record = try decoder.decode(T.self, from: line)
				} catch {
					failureCount += 1
					print("Error decoding \(type) line \(lineNumber): \(error)")
					return
				}
				decodedCount += 1
				try handler(record)
			}

			// An empty or entirely undecodable file means the import shouldn't be treated as successful.
			guard decodedCount > 0 else { throw BulkDataError.noRecordsDecoded(type: type, failures: failureCount) }
			if failureCount > 0 {
				print("Skipped \(failureCount) undecodable \(type) lines")
			}
			return decodedCount
		}

		/// Downloads the gzipped JSONL file, decompresses it into the caches directory,
		/// and returns its URL. Blocks the calling thread until finished.
		public func downloadJSONLFile(progress: ProgressHandler? = nil) throws -> URL {
			let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
			let destURL = cachesURL.appendingPathComponent(type + ".jsonl")
			let downloadedURL = cachesURL.appendingPathComponent(type + ".jsonl.download")
			defer { try? FileManager.default.removeItem(at: downloadedURL) }

			var downloadError: Error?
			let semaphore = DispatchSemaphore(value: 0)

			let task = URLSession.shared.downloadTask(with: jsonlDownloadUri) { tempURL, response, error in
				defer { semaphore.signal() }
				do {
					if let error { throw error }
					guard let tempURL else { throw BulkDataError.noResponse }
					if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
						throw BulkDataError.badStatus(http.statusCode)
					}
					// The temp file is deleted when this handler returns, so move it now.
					try? FileManager.default.removeItem(at: downloadedURL)
					try FileManager.default.moveItem(at: tempURL, to: downloadedURL)
				} catch {
					downloadError = error
				}
			}
			// Content-Length isn't always sent, so fall back to the size Scryfall reports.
			let fallbackSize = Int64(compressedSize ?? 0)
			let observation = task.progress.observe(\.completedUnitCount) { [weak task] _, _ in
				guard let task, let progress else { return }
				let expected = task.countOfBytesExpectedToReceive > 0 ? task.countOfBytesExpectedToReceive : fallbackSize
				guard expected > 0 else { return }
				progress(.downloading, min(1, Double(task.countOfBytesReceived) / Double(expected)))
			}
			progress?(.downloading, 0)
			task.resume()
			semaphore.wait()
			observation.invalidate()

			if let downloadError { throw downloadError }

			// Scryfall serves stored .gz files, but check the magic number in case the
			// body arrives already decompressed (e.g. transparent Content-Encoding).
			// Either path only publishes to `destURL` once the full file is ready.
			if BulkDataReader.isGzip(downloadedURL) {
				progress?(.decompressing, 0)
				try BulkDataReader.streamingGunzip(from: downloadedURL, to: destURL, progress: { progress?(.decompressing, $0) })
			} else {
				try BulkDataReader.moveIntoPlace(from: downloadedURL, to: destURL)
			}
			return destURL
		}
	}

	public enum BulkDataError: LocalizedError {
		case noResponse
		case badStatus(Int)
		case noRecordsDecoded(type: String, failures: Int)

		public var errorDescription: String? {
			switch self {
			case .noResponse:
				return "No response was received from Scryfall."
			case .badStatus(let code):
				return "The bulk data download failed with HTTP status \(code)."
			case .noRecordsDecoded(let type, let failures):
				return "No \(type) records could be decoded from the bulk data file (\(failures) lines failed)."
			}
		}
	}

}

// MARK: - File helpers

private enum BulkDataReader {

	/// Reads a JSONL file line-by-line using buffered 1 MB chunk reads, invoking
	/// `handler` with each non-empty line's raw bytes, keeping peak memory bounded
	/// to roughly one chunk plus one line.
	static func forEachJSONLine(inFileAt url: URL, progress: ((Double) -> Void)? = nil, _ handler: (Data) throws -> Void) throws {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		
		let fileSize = fileSize(of: url)
		var bytesRead: Int64 = 0

		let chunkSize = 1 << 20 // 1 MB
		let newline = UInt8(ascii: "\n")
		var remainder = Data()

		while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
			bytesRead += Int64(chunk.count)
			try autoreleasepool {
				// Keep slices inside the lifetime of this read buffer rather than carrying
				// Data slices (with nonzero start indices and shared storage) across reads.
				try chunk.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
					var lineStart = 0
					for offset in bytes.indices where bytes[offset] == newline {
						let count = offset - lineStart
						if remainder.isEmpty {
							if count > 0 {
								try handler(Data(bytes: bytes.baseAddress!.advanced(by: lineStart), count: count))
							}
						} else {
							remainder.append(contentsOf: bytes.bindMemory(to: UInt8.self)[lineStart..<offset])
							try handler(remainder)
							remainder = Data()
						}
						lineStart = offset + 1
					}
					if lineStart < bytes.count {
						remainder.append(contentsOf: bytes.bindMemory(to: UInt8.self)[lineStart..<bytes.count])
					}
				}
			}
			if fileSize > 0 { progress?(min(1, Double(bytesRead) / Double(fileSize))) }
		}
		// A final line with no trailing newline.
		if !remainder.isEmpty { try handler(remainder) }
	}

	static func fileSize(of url: URL) -> Int64 {
		let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
		return size ?? 0
	}
	
	static func isGzip(_ url: URL) -> Bool {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
		defer { try? handle.close() }
		return (try? handle.read(upToCount: 2)) == Data([0x1f, 0x8b])
	}

	/// Publishes `sourceURL` to `destURL`, replacing any existing file.
	static func moveIntoPlace(from sourceURL: URL, to destURL: URL) throws {
		if FileManager.default.fileExists(atPath: destURL.path) {
			_ = try FileManager.default.replaceItemAt(destURL, withItemAt: sourceURL)
		} else {
			try FileManager.default.moveItem(at: sourceURL, to: destURL)
		}
	}

	enum GunzipError: Error {
		case initFailed
		case inflate(Int32)
		/// The compressed stream ended without a gzip trailer, so the output is truncated.
		case truncated
	}

	static func streamingGunzip(from sourceURL: URL, to destURL: URL, progress: ((Double) -> Void)? = nil) throws {
		let input = try FileHandle(forReadingFrom: sourceURL)
		defer { try? input.close() }
		
		let sourceSize = fileSize(of: sourceURL)
		var bytesRead: Int64 = 0

		// Inflate into a sibling temp file and only move it into place on a clean
		// Z_STREAM_END, so a truncated or corrupt stream never leaves a partial file.
		let tempURL = destURL.appendingPathExtension("inflating")
		try? FileManager.default.removeItem(at: tempURL)
		guard FileManager.default.createFile(atPath: tempURL.path, contents: nil) else {
			throw GunzipError.initFailed
		}
		let output = try FileHandle(forWritingTo: tempURL)
		var published = false
		defer {
			try? output.close()
			if !published { try? FileManager.default.removeItem(at: tempURL) }
		}

		var strm = z_stream()
		// 47 = 15 (max window bits) + 32 (auto-detect gzip/zlib header).
		guard inflateInit2_(&strm, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
			throw GunzipError.initFailed
		}
		defer { inflateEnd(&strm) }

		let chunk = 256 * 1024
		var outBuf = [UInt8](repeating: 0, count: chunk)
		var sawStreamEnd = false

		while case let inData = input.readData(ofLength: chunk), !inData.isEmpty {
			bytesRead += Int64(inData.count)
			if sourceSize > 0 { progress?(min(1, Double(bytesRead) / Double(sourceSize))) }
			var status = Z_OK
			try inData.withUnsafeBytes { raw in
				strm.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: UInt8.self).baseAddress)
				strm.avail_in = uInt(inData.count)
				repeat {
					try outBuf.withUnsafeMutableBufferPointer { out in
						strm.next_out = out.baseAddress
						strm.avail_out = uInt(out.count)
						status = inflate(&strm, Z_NO_FLUSH)
						let produced = out.count - Int(strm.avail_out)
						if produced > 0 {
							try output.write(contentsOf: Data(bytes: out.baseAddress!, count: produced))
						}
					}
				} while strm.avail_out == 0 && status == Z_OK
			}
			if status == Z_STREAM_END { sawStreamEnd = true; break }
			guard status == Z_OK || status == Z_BUF_ERROR else { throw GunzipError.inflate(status) }
		}

		guard sawStreamEnd else { throw GunzipError.truncated }

		try output.close()
		try moveIntoPlace(from: tempURL, to: destURL)
		published = true
	}
}
