// swift-tools-version:4.0
import PackageDescription

let package = Package(
	name: "CwlSignal",
	products: [.library(name: "CwlSignal", targets: ["CwlSignal"])],
	dependencies: [
		.package(url: "/Users/matt/Projects/CwlUtils", .revision("94bf0e1ca0a194601caeb89a971323cfa73de3a2")),
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

