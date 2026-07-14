// The platform-view architecture is adapted from adaptive_platform_ui:
// https://github.com/berkaycatak/adaptive_platform_ui
// Copyright (c) 2025 Berkay Catak. Licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Flutter
import UIKit

final class PiliNativeSegmentedControlFactory: NSObject,
  FlutterPlatformViewFactory
{
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    PiliNativeSegmentedControlPlatformView(
      frame: frame,
      viewId: viewId,
      args: args,
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class PiliReselectTapGestureRecognizer: UITapGestureRecognizer {
  weak var segmentedControl: UISegmentedControl?
  private(set) var selectionAtTrackingStart = UISegmentedControl.noSegment

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    selectionAtTrackingStart =
      segmentedControl?.selectedSegmentIndex ?? UISegmentedControl.noSegment
    super.touchesBegan(touches, with: event)
  }
}

final class PiliNativeSegmentedControlPlatformView: NSObject,
  FlutterPlatformView
{
  private let container: UIView
  private let segmentedControl = UISegmentedControl()
  private let channel: FlutterMethodChannel
  private lazy var reselectRecognizer = PiliReselectTapGestureRecognizer(
    target: self,
    action: #selector(tapped)
  )

  init(
    frame: CGRect,
    viewId: Int64,
    args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    container = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "pili_native_segmented_control_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    container.backgroundColor = .clear
    container.isOpaque = false
    configure(args)
    segmentedControl.translatesAutoresizingMaskIntoConstraints = false
    segmentedControl.addTarget(
      self,
      action: #selector(valueChanged),
      for: .valueChanged
    )
    reselectRecognizer.segmentedControl = segmentedControl
    reselectRecognizer.cancelsTouchesInView = false
    segmentedControl.addGestureRecognizer(reselectRecognizer)

    container.addSubview(segmentedControl)
    NSLayoutConstraint.activate([
      segmentedControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      segmentedControl.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      segmentedControl.leadingAnchor.constraint(
        greaterThanOrEqualTo: container.leadingAnchor
      ),
      segmentedControl.trailingAnchor.constraint(
        lessThanOrEqualTo: container.trailingAnchor
      ),
      segmentedControl.topAnchor.constraint(
        greaterThanOrEqualTo: container.topAnchor
      ),
      segmentedControl.bottomAnchor.constraint(
        lessThanOrEqualTo: container.bottomAnchor
      ),
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setSelectedIndex" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.setSelectedIndex(call.arguments)
      result(nil)
    }
  }

  deinit {
    segmentedControl.removeTarget(
      self,
      action: #selector(valueChanged),
      for: .valueChanged
    )
    segmentedControl.removeGestureRecognizer(reselectRecognizer)
    reselectRecognizer.segmentedControl = nil
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    container
  }

  private func configure(_ args: Any?) {
    guard
      let arguments = args as? [String: Any],
      let labels = arguments["labels"] as? [String],
      !labels.isEmpty
    else {
      NSLog("PiliNativeSegmentedControl: expected at least one label")
      return
    }

    for (index, label) in labels.enumerated() {
      segmentedControl.insertSegment(
        withTitle: label,
        at: index,
        animated: false
      )
    }

    let selectedIndex =
      (arguments["selectedIndex"] as? NSNumber)?.intValue ?? 0
    selectSegment(at: selectedIndex)
  }

  private func setSelectedIndex(_ args: Any?) {
    guard
      let arguments = args as? [String: Any],
      let index = (arguments["index"] as? NSNumber)?.intValue
    else { return }
    selectSegment(at: index)
  }

  private func selectSegment(at index: Int) {
    guard (0..<segmentedControl.numberOfSegments).contains(index) else { return }
    segmentedControl.selectedSegmentIndex = index
  }

  @objc private func valueChanged() {
    sendValueChanged(segmentedControl.selectedSegmentIndex)
  }

  @objc private func tapped() {
    guard
      segmentedControl.selectedSegmentIndex == reselectRecognizer.selectionAtTrackingStart
    else { return }
    sendValueChanged(segmentedControl.selectedSegmentIndex)
  }

  private func sendValueChanged(_ index: Int) {
    guard (0..<segmentedControl.numberOfSegments).contains(index) else { return }
    channel.invokeMethod("valueChanged", arguments: ["index": index])
  }
}
