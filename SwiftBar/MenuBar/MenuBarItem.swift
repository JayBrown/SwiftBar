import Cocoa
import Combine
import SwiftUI
import HotKey

class MenubarItem: NSObject {
    var plugin: Plugin?
    var executablePlugin: ExecutablePlugin? {
        return plugin?.executablePlugin
    }
    var barItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statusBarMenu = NSMenu(title: "SwiftBar Menu")
    let titleCylleInterval: Double = 5
    var contentUpdateCancellable: AnyCancellable? = nil
    var titleCycleCancellable: AnyCancellable? = nil
    let lastUpdatedItem = NSMenuItem(title: "Updating...", action: nil, keyEquivalent: "")
    let aboutItem = NSMenuItem(title: "About", action: #selector(about), keyEquivalent: "")
    let runInTerminalItem = NSMenuItem(title: "Run in Terminal...", action: #selector(runInTerminal), keyEquivalent: "")
    let disablePluginItem = NSMenuItem(title: "Disable Plugin", action: #selector(disablePlugin), keyEquivalent: "")
    let swiftBarItem = NSMenuItem(title: "SwiftBar", action: nil, keyEquivalent: "")
    var isDefault = false
    var isOpen = false
    var refreshOnClose = false
    var hotKeys: [HotKey] = []

    var titleLines: [String] = [] {
        didSet {
            currentTitleLineIndex = -1
            guard titleLines.count > 1 else {
                disableTitleCycle()
                return
            }
            enableTitleCycle()
        }
    }
    
    var currentTitleLineIndex: Int = -1

    var currentTitleLine: String {
        guard titleLines.indices.contains(currentTitleLineIndex) else {
            return titleLines.first ?? ""
        }
        return titleLines[currentTitleLineIndex]
    }

    var lastMenuItem: NSMenuItem? = nil

    var prevLevel = 0
    var prevItems = [NSMenuItem]()

    var titleCylleTimerPubliser: Timer.TimerPublisher {
        return Timer.TimerPublisher(interval: titleCylleInterval, runLoop: .main, mode: .default)
    }

    init(title: String, plugin: Plugin? = nil) {
        super.init()
        barItem.menu = statusBarMenu
        guard plugin != nil else {
            barItem.button?.title = title
            buildStandardMenu()
            return
        }
        self.plugin = plugin
        statusBarMenu.delegate = self
        updateMenu()
        contentUpdateCancellable = executablePlugin?.contentUpdatePublisher
            .sink {[weak self] _ in
                guard self?.isOpen == false else {
                    self?.refreshOnClose = true
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    self?.disableTitleCycle()
                    self?.updateMenu()
                }
            }
    }

    deinit {
        contentUpdateCancellable?.cancel()
        titleCycleCancellable?.cancel()
    }

    func enableTitleCycle() {
        titleCycleCancellable = titleCylleTimerPubliser
            .autoconnect()
            .receive(on: RunLoop.main)
            .sink(receiveValue: {[weak self] _ in
                self?.cycleThroughTitles()
            })
    }

    func disableTitleCycle() {
        titleCycleCancellable?.cancel()
    }

    func show() {
        barItem.isVisible = true
    }

    func hide() {
        barItem.isVisible = false
    }
}

extension MenubarItem: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true

        var params = MenuLineParameters(line: currentTitleLine)
        params.params["color"] = "white"
        barItem.button?.attributedTitle = atributedTitle(with: params).title

        guard let lastUpdated = executablePlugin?.lastUpdated else {return}
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeDate = formatter.localizedString(for: lastUpdated, relativeTo: Date()).capitalized
        lastUpdatedItem.title = "Updated \(relativeDate)"

        guard NSApp.currentEvent?.modifierFlags.contains(.option) == false else {
            [lastUpdatedItem,runInTerminalItem,disablePluginItem,aboutItem,swiftBarItem].forEach{$0.isHidden = false}
            return
        }
        lastUpdatedItem.isHidden = plugin?.metadata?.hideLastUpdated ?? false
        runInTerminalItem.isHidden = plugin?.metadata?.hideRunInTerminal ?? false
        disablePluginItem.isHidden = plugin?.metadata?.hideDisablePlugin ?? false
        aboutItem.isHidden = plugin?.metadata?.hideAbout ?? false
        swiftBarItem.isHidden = plugin?.metadata?.hideSwiftBar ?? false
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        setMenuTitle(title: currentTitleLine)

        //if plugin was refreshed when menu was opened refresh on menu close
        if refreshOnClose {
            refreshOnClose = false
            disableTitleCycle()
            updateMenu()
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if  let highlitedItem = menu.highlightedItem,
            highlitedItem.attributedTitle != nil,
            let params = highlitedItem.representedObject as? MenuLineParameters,
            params.color != nil {
            highlitedItem.attributedTitle = atributedTitle(with: params).title
        }

        if var params = item?.representedObject as? MenuLineParameters,
           item?.attributedTitle != nil,
           params.color != nil {
            params.params.removeValue(forKey: "color")
            item?.attributedTitle = atributedTitle(with: params).title
        }
    }
}

// Standard status bar menu
extension MenubarItem {
    func buildStandardMenu() {
        let firstLevel = (plugin == nil)
        let menu = firstLevel ? statusBarMenu:NSMenu(title: "Preferences")

        let refreshAllItem = NSMenuItem(title: "Refresh All", action: #selector(refreshAllPlugins), keyEquivalent: "r")
        let enableAllItem = NSMenuItem(title: "Enable All", action: #selector(enableAllPlugins), keyEquivalent: "")
        let disableAllItem = NSMenuItem(title: "Disable All", action: #selector(disableAllPlugins), keyEquivalent: "")
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        let openPluginFolderItem = NSMenuItem(title: "Open Plugin Folder...", action: #selector(openPluginFolder), keyEquivalent: "")
        let changePluginFolderItem = NSMenuItem(title: "Change Plugin Folder...", action: #selector(changePluginFolder), keyEquivalent: "")
        let getPluginsItem = NSMenuItem(title: "Get Plugins...", action: #selector(getPlugins), keyEquivalent: "")
        let sendFeedbackItem = NSMenuItem(title: "Send Feedback...", action: #selector(sendFeedback), keyEquivalent: "")
        let aboutSwiftbarItem = NSMenuItem(title: "About", action: #selector(aboutSwiftBar), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit SwiftBar", action: #selector(quit), keyEquivalent: "q")
        let showErrorItem = NSMenuItem(title: "Show Error", action: #selector(showError), keyEquivalent: "")
        [refreshAllItem,enableAllItem,disableAllItem,preferencesItem,openPluginFolderItem,changePluginFolderItem,getPluginsItem,quitItem,disablePluginItem,aboutItem,aboutSwiftbarItem,runInTerminalItem,showErrorItem,sendFeedbackItem].forEach{ item in
            item.target = self
            item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font:NSFont.menuBarFont(ofSize: 0)])
        }

        menu.addItem(refreshAllItem)
        menu.addItem(enableAllItem)
        menu.addItem(disableAllItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(openPluginFolderItem)
        menu.addItem(changePluginFolderItem)
        menu.addItem(getPluginsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(aboutSwiftbarItem)
        menu.addItem(preferencesItem)
        menu.addItem(sendFeedbackItem)
        menu.addItem(quitItem)

        if !firstLevel {
            statusBarMenu.addItem(NSMenuItem.separator())

            // put swiftbar menu as submenu
            swiftBarItem.attributedTitle = NSAttributedString(string: swiftBarItem.title, attributes: [.font:NSFont.menuBarFont(ofSize: 0)])
            swiftBarItem.submenu = menu
            swiftBarItem.image = Preferences.shared.swiftBarIconIsHidden ? nil:NSImage(named: "AppIcon")?.resizedCopy(w: 21, h: 21)
            statusBarMenu.addItem(swiftBarItem)

            // default plugin menu items
            statusBarMenu.addItem(NSMenuItem.separator())
            statusBarMenu.addItem(lastUpdatedItem)
            if plugin?.error != nil {
                statusBarMenu.addItem(showErrorItem)
            }
            statusBarMenu.addItem(runInTerminalItem)
            statusBarMenu.addItem(disablePluginItem)
            if plugin?.metadata?.isEmpty == false {
                statusBarMenu.addItem(aboutItem)
            }
        }
    }

    @objc func refreshAllPlugins() {
        delegate.pluginManager.refreshAllPlugins()
    }

    @objc func disableAllPlugins() {
        delegate.pluginManager.disableAllPlugins()
    }

    @objc func enableAllPlugins() {
        delegate.pluginManager.enableAllPlugins()
    }

    @objc func openPluginFolder() {
        App.openPluginFolder()
    }

    //TODO: Preferences should be shown as a standalone window.
    @objc func openPreferences() {
        App.openPreferences()
    }

    @objc func changePluginFolder() {
        App.changePluginFolder()
    }

    @objc func getPlugins() {
        App.getPlugins()
    }

    @objc func sendFeedback() {
        NSWorkspace.shared.open(URL(string: "https://github.com/swiftbar/SwiftBar/issues")!)
    }

    @objc func quit() {
        NSApp.terminate(self)
    }

    @objc func showError() {
        guard let plugin = plugin, plugin.error != nil else {return}
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PluginErrorView(plugin: plugin))
        popover.show(relativeTo: barItem.button!.bounds, of: barItem.button!, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    @objc func runInTerminal() {
        guard let scriptPath = plugin?.file else {return}
        App.runInTerminal(script: scriptPath.escaped(), env: [
            EnvironmentVariables.swiftPluginPath.rawValue:plugin?.file ?? "",
            EnvironmentVariables.osAppearance.rawValue: (App.isDarkTheme ? "Dark":"Light"),
        ])
    }

    @objc func disablePlugin() {
        guard let plugin = plugin else {return}
        delegate.pluginManager.disablePlugin(plugin: plugin)
    }

    @objc func about() {
        guard let pluginMetadata = plugin?.metadata else {return}
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: AboutPluginView(md: pluginMetadata))
        popover.show(relativeTo: barItem.button!.bounds, of: barItem.button!, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    @objc func aboutSwiftBar() {
        App.showAbout()
    }
}


extension MenubarItem {
    static func defaultBarItem() -> MenubarItem {
        let item = MenubarItem(title: "SwiftBar")
        item.isDefault = true
        return item
    }
}

//parse script output
extension MenubarItem {
    func splitScriptOutput(scriptOutput: String) -> (header: [String], body: [String]) {
        let lines = scriptOutput.components(separatedBy: CharacterSet.newlines).filter{!$0.isEmpty}
        guard let index = lines.firstIndex(where:{$0.hasPrefix("---")}) else {
            return (lines, [])
        }
        let header = Array(lines[...index].dropLast())
        let body = Array(lines[index...])
        
        return (header,body)
    }

    func addShortcut(shortcut: HotKey, action: @escaping ()-> Void) {
        shortcut.keyUpHandler = action
        hotKeys.append(shortcut)
    }

    func updateMenu() {
        statusBarMenu.removeAllItems()
        show()
        
        if executablePlugin?.lastState == .Failed {
            titleLines = ["⚠️"]
            barItem.button?.title = "⚠️"
            buildStandardMenu()
            return
        }
        
        guard let scriptOutput = plugin?.content,
              (!scriptOutput.isEmpty || plugin?.lastState == .Loading)
        else {
            hide()
            return
        }
        
        let parts = splitScriptOutput(scriptOutput: scriptOutput)
        titleLines =  parts.header
        updateMenuTitle(titleLines: parts.header)
        if let title = titleLines.first, let kc = MenuLineParameters(line: title).shortcut {
            addShortcut(shortcut: HotKey(keyCombo: kc)) { [weak self] in
                self?.barItem.button?.performClick(nil)
            }
        }

        if !parts.body.isEmpty {
            statusBarMenu.addItem(NSMenuItem.separator())
        }

        //prevItems.append(statusBarMenu.items.last)
        parts.body.forEach { line in
            addMenuItem(from: line)
        }
        buildStandardMenu()
    }

    func addMenuItem(from line: String) {
        if line == "---" {
            statusBarMenu.addItem(NSMenuItem.separator())
            return
        }
        var workingLine = line
        var submenu: NSMenu? = nil
        var currentLevel = 0

        while workingLine.hasPrefix("--") {
            workingLine = String(workingLine.dropFirst(2))
            currentLevel += 1
            if workingLine == "---" {
                break
            }
        }

        if prevLevel >= currentLevel, prevItems.count > 0 {
            var cnt = prevLevel - currentLevel
            while cnt >= 0 {
                if !prevItems.isEmpty {
                    prevItems.removeFirst()
                }
                cnt = cnt - 1
            }
        }
        if currentLevel > 0 {
            let item = prevItems.first
            if item?.submenu == nil {
                item?.submenu = NSMenu(title: "")
            }
            submenu = item?.submenu
        }
        
        if let item = workingLine == "---" ? NSMenuItem.separator():buildMenuItem(params: MenuLineParameters(line: workingLine)) {
            item.target = self
            (submenu ?? statusBarMenu)?.addItem(item)
            lastMenuItem = item
            prevLevel = currentLevel
            prevItems.insert(item, at: 0)

            if let kc = MenuLineParameters(line: line).shortcut {
                addShortcut(shortcut: HotKey(keyCombo: kc)) {
                    guard let action = item.action else {return}
                    NSApp.sendAction(action, to: item.target, from: item)
                }
            }
        }
    }

    func updateMenuTitle(titleLines: [String]) {
        setMenuTitle(title: titleLines.first ?? "⚠️")
        guard titleLines.count > 1 else {return}

        titleLines.forEach{ line in
            addMenuItem(from: line)
        }
    }

    func setMenuTitle(title: String) {
        barItem.button?.attributedTitle = NSAttributedString()
        barItem.button?.image = nil

        let params = MenuLineParameters(line: title)
        if let image = params.image {
            barItem.button?.image = image
            barItem.button?.imagePosition = .imageLeft
        }
        barItem.button?.attributedTitle = atributedTitle(with: params).title
    }

    func cycleThroughTitles() {
        currentTitleLineIndex += 1
        if !titleLines.indices.contains(currentTitleLineIndex) {
            currentTitleLineIndex = 0
        }
        setMenuTitle(title: titleLines[currentTitleLineIndex])
    }

    func atributedTitle(with params: MenuLineParameters) -> (title: NSAttributedString, tooltip: String) {
        var title = params.trim ? params.title.trimmingCharacters(in: .whitespaces):params.title
        if params.emojize && !params.symbolize {
            title = title.emojify()
        }
        let fullTitle = title
        if let length = params.length, length < title.count {
            title = String(title.prefix(length)).appending("...")
        }
        title = title.replacingOccurrences(of: "\\n", with: "\n")

        let fontSize = params.size ?? 0
        let color = params.color ?? NSColor.labelColor
        let font = NSFont(name: params.font ?? "", size: fontSize) ??
            NSFont.menuBarFont(ofSize: fontSize)

        let style = NSMutableParagraphStyle()
        style.alignment = .left
        
        var attributedTitle = NSMutableAttributedString(string: title)
        
        if params.symbolize && !params.ansi {
            attributedTitle = title.symbolize(font: font)
        }
        if params.ansi {
            attributedTitle = title.colorizedWithANSIColor()
        }
        if !params.ansi {
            attributedTitle.addAttributes([.foregroundColor:color],
                                          range: NSRange(0..<attributedTitle.length))
        }
        
        attributedTitle.addAttributes([.font:font,.paragraphStyle:style],
            
                                      range: NSRange(0..<attributedTitle.length))
        return (attributedTitle, fullTitle)
    }

    func buildMenuItem(params: MenuLineParameters) -> NSMenuItem? {
        guard params.dropdown else {return nil}

        let item = NSMenuItem(title: params.title,
                              action: params.hasAction ? #selector(perfomMenutItemAction):nil,
                          keyEquivalent: "")
        item.representedObject = params
        let title = atributedTitle(with: params)
        item.attributedTitle = title.title

        item.toolTip = params.tooltip
        
        if let length = params.length, length < title.title.string.count {
            item.toolTip = title.tooltip
        }

        if params.alternate {
            item.isAlternate = true
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags.option
        }

        if let image = params.image {
            item.image = image
        }

        if params.checked {
            item.state = .on
        }

        return item
    }

    @objc func perfomMenutItemAction(_ sender: NSMenuItem) {
        guard let params = sender.representedObject as? MenuLineParameters else {return}

        if let href = params.href, let url = URL(string: href) {
            NSWorkspace.shared.open(url)
            return
        }

        if let bash = params.bash {
            let script = "\(bash.escaped()) \(params.bashParams.joined(separator: " "))"
            App.runInTerminal(script: script, runInBackground: !params.terminal, env: [
                                EnvironmentVariables.swiftPluginPath.rawValue:plugin?.file ?? "",
                                EnvironmentVariables.osAppearance.rawValue: (App.isDarkTheme ? "Dark":"Light")]) { [weak self] in
                if params.refresh {
                    self?.plugin?.refresh()
                }
            }
            return
        }

        if params.refresh {
            plugin?.refresh()
        }
    }
}
