import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
#elseif os(iOS)
import UIKit
public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
#endif

/// Small cross-platform helpers so the editor and style layers read the same on both OSes.
enum Platform {
    static var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #elseif os(iOS)
        return UIDevice.current.name
        #else
        return "Device"
        #endif
    }
}
