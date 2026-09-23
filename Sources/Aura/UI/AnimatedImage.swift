import AppKit
import SwiftUI

/// Remote image that also plays animated GIF / WebP / APNG (AsyncImage only shows the first frame).
struct AnimatedRemoteImage: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var loadedURL: URL?
        var task: URLSessionDataTask?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.canDrawSubviewsIntoLayer = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        context.coordinator.task?.cancel()
        let task = HTTP.session.dataTask(with: url) { data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { view.image = image }
        }
        context.coordinator.task = task
        task.resume()
    }
}
