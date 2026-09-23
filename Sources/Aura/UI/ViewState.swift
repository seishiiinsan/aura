import SwiftUI

/// Alias of SwiftUI's `State` property wrapper.
///
/// Recent SDKs also declare a `@State` *macro* whose plugin only ships with Xcode;
/// going through an alias keeps the project buildable with the Command Line Tools alone.
typealias ViewState<Value> = SwiftUI.State<Value>
