//
//  main.swift
//  CwlConcat
//
//  Created by Matt Gallagher on 2017/06/24.
//  Copyright © 2017 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
//  SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
//  IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

import Cocoa

func env(_ key: String) -> String? { return ProcessInfo.processInfo.environment[key] }
extension FileHandle: TextOutputStream {
	public func write(_ string: String) { string.data(using: .utf8).map { write($0) } }
	static var err = FileHandle.standardError
}
class GetLineIterator: Sequence, IteratorProtocol {
	let file: UnsafeMutablePointer<FILE>
	init?(_ path: String) {
		guard let file = fopen(path, "r") else { return nil }
		self.file = file
	}
	func next() -> String? {
		var line: UnsafeMutablePointer<Int8>? = nil
		var linecap: Int = 0
		if getline(&line, &linecap, file) > 0, let l = line {
			defer { free(line) }
			return String(cString: l)
		}
		return nil
	}
	deinit { fclose(file) }
}

struct Concat {
	enum Include {
		case file(String)
		case text(String)
	}
	
	enum ProcessingError: Error {
		case fileNotFound(String)
		case couldntOpenFile(String)
		case cantCreateOutputFile(String)
		case unknownAuthorship(String)
		case unknownFlag(String)
		case missingEnvironment(String)
		case mustStartWithName
		case needEvenParams
	}
	
	var includes: [Include] = []
	var excludes: Set<String> = []
	var name: String = ""
	
	static func appendFile(_ filePath: String, output: FileHandle, isInternal: Bool) throws {
		print("Appending file \(filePath)", to: &FileHandle.err)
		
		let publicAndOpenPattern = try! NSRegularExpression(pattern: "(^|\t|[^,] )(public |open )", options: [])
		let authorPattern = try! NSRegularExpression(pattern: "^//  Copyright © .... Matt Gallagher.*\\. All rights reserved\\.$", options: [])
		
		guard let lineIterator = GetLineIterator(filePath) else { throw ProcessingError.couldntOpenFile(filePath) }
		var initialHeaderBlock = true
		var lineCount = 0
		for line in lineIterator {
			lineCount += 1
			if initialHeaderBlock {
				if line.hasPrefix("//") {
					if lineCount == 6 {
						if authorPattern.firstMatch(in: line, range: NSMakeRange(0, line.count)) == nil {
							throw ProcessingError.unknownAuthorship(filePath)
						}
					}
					continue
				}
				initialHeaderBlock = false
			}
			let processedLine: String
			if isInternal {
				processedLine = publicAndOpenPattern.stringByReplacingMatches(in:line, range: NSMakeRange(0, line.count), withTemplate: "$1")
			} else {
				processedLine = line
			}
			output.write(processedLine)
		}
	}
	
	func process(srcDir: String, buildDir: String, framework: String, index: Int, count: Int, isInternal: Bool) throws {
		let access = isInternal ? "internal" : "public"
		let purpose = isInternal
			? "direct inclusion in projects instead of library inclusion"
			: "exposing from libraries or use in Swift Playgrounds"
		let message = """
			//
			//  This file is part of a concatenation of the \(framework) framework with \(access)
			//  interfaces for \(purpose)).
			//  For details, visit: https://github.com/mattgallagher/\(framework)
			//\n
			"""
		
		let destination = URL(fileURLWithPath: buildDir).appendingPathComponent("Concat_\(access)")
		let outputUrl = destination.appendingPathComponent(name)
		
		try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
		guard FileManager.default.createFile(atPath: outputUrl.path, contents: nil) else {
			throw ProcessingError.cantCreateOutputFile(outputUrl.path)
		}
		let output = try FileHandle(forWritingTo: outputUrl)

		var preprocessed = [Include]()
		var files = [String]()
		for include in includes {
			switch include {
			case .file(let file):
				preprocessed.append(.file(file))
				files.append(URL(fileURLWithPath: file).lastPathComponent)
			case .text(let text):
				preprocessed.append(.text(text))
			}
		}
		
		print("Starting output to file \(outputUrl.path)", to: &FileHandle.err)
		
		output.write(message)
		output.write("""
			//  Copyright © 2015-2018 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
			//
			//  Permission to use, copy, modify, and/or distribute this software for any
			//  purpose with or without fee is hereby granted, provided that the above
			//  copyright notice and this permission notice appear in all copies.
			//
			//  THE SOFTWARE IS PROVIDED \"AS IS\" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
			//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
			//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
			//  SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
			//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
			//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
			//  IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
			//
			//  This file was generated by the CwlConcat tool on \(Date()) from the following files:\n
			""")
		for file in files {
			output.write("//   \(file)\n")
		}
		
		for include in preprocessed {
			switch include {
			case .file(let file):
				try Concat.appendFile(file, output: output, isInternal: isInternal)
				print(file)
				print(buildDir)
			case .text(let text):
				output.write(text)
				output.write("\n")
			}
		}
	}
	
	static func processAllFromCommandLine() throws {
		guard let buildDir = env("BUILT_PRODUCTS_DIR") else { throw ProcessingError.missingEnvironment("BUILT_PRODUCTS_DIR") }
		guard let srcDir = env("SRCROOT") else { throw ProcessingError.missingEnvironment("SRCROOT") }
		guard let startIndex = ProcessInfo.processInfo.arguments.index(where: { $0 == "-f" }),
			ProcessInfo.processInfo.arguments.count >= startIndex + 6 else {
				throw ProcessingError.mustStartWithName
		}
		let framework = ProcessInfo.processInfo.arguments[startIndex + 1]
		
		var outputs = [Concat]()
		
		guard (ProcessInfo.processInfo.arguments.count - startIndex - 2) % 2 == 0 else {
			throw ProcessingError.needEvenParams
		}
		for i in stride(from: startIndex + 2, to: ProcessInfo.processInfo.arguments.count - 1, by: 2) {
			let flag = ProcessInfo.processInfo.arguments[i]
			let value = ProcessInfo.processInfo.arguments[i + 1]
			var isDir: ObjCBool = false
			switch flag {
			case "-n":
				outputs.append(Concat())
				outputs[outputs.count - 1].name = value
			case _ where outputs.count == 0: throw ProcessingError.mustStartWithName
			case "-x":
				var url = URL(fileURLWithPath: value)
				url.resolveSymlinksInPath()
				outputs[outputs.count - 1].excludes.insert(url.path)
			case "-i":
				guard FileManager.default.fileExists(atPath: value, isDirectory: &isDir) else {
					throw ProcessingError.fileNotFound(value)
				}
				if isDir.boolValue {
					guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: value), includingPropertiesForKeys: nil) else {
						throw ProcessingError.fileNotFound(value)
					}
					for file in enumerator {
						let fileUrl = file as! URL
						if outputs[outputs.count - 1].excludes.contains(fileUrl.path) {
							if !fileUrl.isFileURL {
								enumerator.skipDescendants()
							}
							continue
						}
						if fileUrl.pathExtension != "swift" { continue }
						outputs[outputs.count - 1].includes.append(.file(fileUrl.path))
					}
				} else {
					outputs[outputs.count - 1].includes.append(.file(value))
				}
			case "-t": outputs[outputs.count - 1].includes.append(.text(value))
			default: throw ProcessingError.unknownFlag(flag)
			}
		}
		
		for (index, o) in outputs.enumerated() {
			try o.process(srcDir: srcDir, buildDir: buildDir, framework: framework, index: index, count: outputs.count, isInternal: true)
			try o.process(srcDir: srcDir, buildDir: buildDir, framework: framework, index: index, count: outputs.count, isInternal: false)
		}
	}
}

do {
	print("Command line:\n\(ProcessInfo.processInfo.arguments)\n", to: &FileHandle.err)
	
	try Concat.processAllFromCommandLine()
} catch {
	print("Failed: \(error)", to: &FileHandle.err)
	exit(1)
}
