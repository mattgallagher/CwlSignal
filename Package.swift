// swift-tools-version:4.0
import PackageDescription

let package = Package(
   name: "CwlSignal",
   products: [.library(name: "CwlSignal", type: .dynamic, targets: ["CwlSignal"])],
	dependencies: [.package(url: "/Users/matt/Projects/CwlUtils", .revision("84ca7170e4e4b1f429905022695efcac13e5657f"))],
	targets: [
		.target(
			name: "CwlSignal",
			dependencies: [
				.product(name: "CwlUtils")
			]
		)
	]
)
