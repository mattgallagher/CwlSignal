// swift-tools-version:5.0
import PackageDescription

let package = Package(
   name: "CwlSignal",
   products: [
   	.library(name: "CwlSignal", targets: ["CwlSignal"])
	],
	dependencies: [
		.package(url: "file:///Users/matt/Projects/CwlUtils", .branch("master")),
		.package(url: "file:///Users/matt/Projects/CwlPreconditionTesting", .branch("master"))
	],
	targets: [
		.target(
			name: "CwlSignal",
			dependencies: [
				.product(name: "CwlUtils")
			]
		),
		.testTarget(
			name: "CwlSignalTests",
			dependencies: [
				.target(name: "CwlSignal"),
				.product(name: "CwlPreconditionTesting")
			]
		)
	]
)
