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

final class PiliNativeGlassTabBarFactory: NSObject, FlutterPlatformViewFactory {
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
    PiliNativeGlassTabBarPlatformView(
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

final class PiliNativeGlassTabBarPlatformView: NSObject,
  FlutterPlatformView,
  UITabBarDelegate
{
  private let container: UIView
  private let tabBar = UITabBar(frame: .zero)
  private let channel: FlutterMethodChannel
  private var selectedContentIndex = 0

  init(
    frame: CGRect,
    viewId: Int64,
    args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    container = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "pili_native_glass_tab_bar_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    tabBar.delegate = self
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: container.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    configureItems(args)
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
    tabBar.delegate = nil
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    container
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard let index = tabBar.items?.firstIndex(of: item) else { return }
    if index == 3 {
      let contentIndex = selectedContentIndex
      DispatchQueue.main.async { [weak self] in
        self?.selectItem(at: contentIndex)
        self?.channel.invokeMethod("searchTapped", arguments: nil)
      }
      return
    }
    selectedContentIndex = index
    channel.invokeMethod("valueChanged", arguments: ["index": index])
  }

  private func configureItems(_ args: Any?) {
    guard
      let arguments = args as? [String: Any],
      let itemArguments = arguments["items"] as? [[String: Any]],
      itemArguments.count == 3
    else {
      NSLog("PiliNativeGlassTabBar: expected exactly three tab items")
      return
    }

    let items = itemArguments.enumerated().map { index, arguments in
      let label = arguments["label"] as? String
      let symbol = arguments["symbol"] as? String ?? ""
      let selectedSymbol = arguments["selectedSymbol"] as? String ?? ""
      let item = UITabBarItem(
        title: label,
        image: systemImage(named: symbol),
        selectedImage: systemImage(named: selectedSymbol)
      )
      item.tag = index
      return item
    }
    let searchItem = UITabBarItem(tabBarSystemItem: .search, tag: 3)
    searchItem.title = arguments["searchLabel"] as? String
    tabBar.items = items + [searchItem]

    let selectedIndex = (arguments["selectedIndex"] as? NSNumber)?.intValue ?? 0
    selectItem(at: selectedIndex)
  }

  private func setSelectedIndex(_ args: Any?) {
    guard let arguments = args as? [String: Any],
          let index = (arguments["index"] as? NSNumber)?.intValue
    else { return }
    selectItem(at: index)
  }

  private func selectItem(at index: Int) {
    guard let items = tabBar.items, (0..<3).contains(index) else { return }
    selectedContentIndex = index
    tabBar.selectedItem = items[index]
  }

  private func systemImage(named name: String) -> UIImage? {
    if let image = UIImage(systemName: name) {
      return image.withRenderingMode(.alwaysTemplate)
    }

    let fallbackName: String?
    switch name {
    case "home": fallbackName = "house"
    case "home.fill": fallbackName = "house.fill"
    default: fallbackName = nil
    }

    guard let fallbackName,
          let image = UIImage(systemName: fallbackName)
    else {
      NSLog("PiliNativeGlassTabBar: SF Symbol '%@' is unavailable", name)
      return nil
    }
    NSLog(
      "PiliNativeGlassTabBar: SF Symbol '%@' is unavailable; temporarily using '%@'",
      name,
      fallbackName
    )
    return image.withRenderingMode(.alwaysTemplate)
  }
}
