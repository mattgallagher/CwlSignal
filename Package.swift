// swift-tools-version:4.0
import PackageDescription

let package = Package(
   name: "CwlSignal",
   products: [
   	.library(name: "CwlSignal", type: .dynamic, targets: ["CwlSignal"])
	],
	dependencies: [
		.package(url: "https://github.com/mattgallagher/CwlUtils.git", .revision("7377fa8f3907d290994365e08b93cba69bf644de"))
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
				.product(name: "CwlUtils")
			]
		)
	]
)
