// swift-tools-version:4.0
import PackageDescription

let package = Package(
	name: "CwlSignal",
	products: [.library(name: "CwlSignal", targets: ["CwlSignal"])],
	dependencies: [
		.package(url: "/Users/matt/Projects/CwlUtils", .revision("367287056a44cae7bcd1d852d4a817c6722cc0a0")),
	],
	targets: [
		.target(name: "CwlSignal", exclude: [
			"CwlSignal.h",
			"Info.plist",
		]),
		.testTarget(name: "CwlSignalTests", dependencies: ["CwlSignal"], exclude: [
			"Info.plist"
		]),
	]
)

