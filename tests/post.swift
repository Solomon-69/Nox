import Foundation
DistributedNotificationCenter.default().postNotificationName(.init(CommandLine.arguments[1]), object: CommandLine.arguments[2], userInfo: nil, deliverImmediately: true)
