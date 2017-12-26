// swift-tools-version:4.0
import PackageDescription

let package = Package(
   name: "CwlSignal",
   products: [.library(name: "CwlSignal", type: .dynamic, targets: ["CwlSignal"])],
	dependencies: [.package(url: "https://github.com/mattgallagher/CwlUtils.git", .revision("21fa87616a3aed2a79c64e6fd7d4837093d160bd"))],
	targets: [
		.target(
			name: "CwlSignal",
			dependencies: [
				.product(name: "CwlUtils")
			]
		)
	]
)
