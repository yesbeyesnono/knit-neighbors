// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapacitorMetaEvents",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapacitorMetaEvents",
            targets: ["MetaEventsPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk.git", exact: "19.0.0")
    ],
    targets: [
        .target(
            name: "MetaEventsPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .product(name: "FacebookCore", package: "facebook-ios-sdk")
            ],
            path: "ios/Sources/MetaEventsPlugin")
    ]
)
