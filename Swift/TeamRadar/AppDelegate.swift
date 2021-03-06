/*
Copyright 2016 IslandJohn and the TeamRadar Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied
See the License for the specific language governing permissions and
limitations under the License.
*/

import Cocoa
import Foundation

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSSeguePerforming, NSUserNotificationCenterDelegate {
    
    @IBOutlet weak var statusItemMenu: NSMenu!
    @IBOutlet weak var statusItemMenuConnectItem: NSMenuItem!
    @IBOutlet weak var statusItemMenuStateItem: NSMenuItem!
    @IBOutlet weak var segueConnectMenuItem: NSMenuItem!

    var statusItem: NSStatusItem? = nil
    var goTask: NSTask? = nil
    
    var teamRadarParser = TeamRadarParser()
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSVariableStatusItemLength)
            
        statusItem?.title = statusItemMenu.title
        statusItem?.highlightMode = true
        statusItem?.menu = statusItemMenu        
    }

    func shouldPerformSegueWithIdentifier(identifier: String, sender: AnyObject?) -> Bool {
        return true
    }
    
    func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
        let vc = segue.destinationController as! ViewController
        
        vc.prefSaveButtonTitle = segue.identifier!
        if (segue.identifier == "Connect") {
            vc.prefSaveButtonMenuItem = statusItemMenuConnectItem
        }
        else {
            vc.prefSaveButtonMenuItem = nil            
        }
    }
    
    func eventTaskOutput(note: NSNotification) {
        let fh = note.object as! NSFileHandle
        
        let data = fh.availableData
        if data.length > 0 {
            if let str = NSString(data: data, encoding: NSUTF8StringEncoding) {
                let lines = str.componentsSeparatedByString("\n")
                
                if(lines.count > 0) {
                    for (_,line) in lines.enumerate() {
                        let json = self.teamRadarParser.extractJSONFromLine(line)
                        
                        guard json != "" else { continue }
                        
                        let jsonDict = self.teamRadarParser.convertJSONStringToDictionary(json)
                        
                        guard let jDict = jsonDict else { continue }
                        guard jDict is NSDictionary else { continue }
                        
                        if let content = jDict["Content"] where content != nil {
                            showNotification(content as! String)
                        }
                    }
                }
            }
        }
        
        fh.waitForDataInBackgroundAndNotify()
    }
    
    func eventTaskError(note: NSNotification) {
        let fh = note.object as! NSFileHandle
        
        fh.waitForDataInBackgroundAndNotify()
    }
    
    func eventTaskTerminate() {
        connectAction(statusItemMenuConnectItem)
    }
    
    @IBAction func connectAction(sender: AnyObject) {
        let menuitem = sender as? NSMenuItem
        
        if let url = Settings.get(SettingsKey.URL) where url != "", let user = Settings.get(SettingsKey.USER) where user != "", let password = Settings.get(SettingsKey.PASSWORD) where password != ""  {
            if (goTask == nil) {
                goTask = NSTask()
                    
                goTask!.launchPath = NSBundle.mainBundle().pathForResource("teamradar", ofType: nil)
                goTask?.arguments = [url, user, password]
                goTask!.standardInput = NSPipe()
                goTask!.standardOutput = NSPipe()
                goTask!.standardError = NSPipe()
                goTask?.terminationHandler = {(task: NSTask) -> Void in
                    self.eventTaskTerminate()
                }
                    
                NSNotificationCenter.defaultCenter().addObserver(self, selector: "eventTaskOutput:", name: NSFileHandleDataAvailableNotification, object: goTask!.standardOutput?.fileHandleForReading)
                NSNotificationCenter.defaultCenter().addObserver(self, selector: "eventTaskError:", name: NSFileHandleDataAvailableNotification, object: goTask!.standardError?.fileHandleForReading)
                    
                goTask!.standardOutput?.fileHandleForReading.waitForDataInBackgroundAndNotify()
                goTask!.standardError?.fileHandleForReading.waitForDataInBackgroundAndNotify()
                
                goTask?.launch()
                
                menuitem?.title = "Disconnect"
                statusItemMenuStateItem.title = "No rooms."
            } else {
                if (goTask!.running) { // trigger termination, but don't clean up yet
                    goTask?.terminate()
                }
                else { // this is being called from the terminate event, so clean up
                    goTask = nil
                    menuitem?.title = "Connect..."
                    statusItemMenuStateItem.title = "Not connected."
                }
            }
        } else {
            // some hackery to show the preferences dialog via a segue if things are not set up
            segueConnectMenuItem.menu?.performActionForItemAtIndex((segueConnectMenuItem.menu?.indexOfItem(segueConnectMenuItem))!)
        }
    }
    
    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }

    // MARK: - Core Data stack

    lazy var applicationDocumentsDirectory: NSURL = {
        // The directory the application uses to store the Core Data store file. This code uses a directory named "com.islandjohn.TeamRadar" in the user's Application Support directory.
        let urls = NSFileManager.defaultManager().URLsForDirectory(.ApplicationSupportDirectory, inDomains: .UserDomainMask)
        let appSupportURL = urls[urls.count - 1]
        return appSupportURL.URLByAppendingPathComponent("com.islandjohn.TeamRadar")
    }()

    lazy var managedObjectModel: NSManagedObjectModel = {
        // The managed object model for the application. This property is not optional. It is a fatal error for the application not to be able to find and load its model.
        let modelURL = NSBundle.mainBundle().URLForResource("TeamRadar", withExtension: "momd")!
        return NSManagedObjectModel(contentsOfURL: modelURL)!
    }()

    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
        // The persistent store coordinator for the application. This implementation creates and returns a coordinator, having added the store for the application to it. (The directory for the store is created, if necessary.) This property is optional since there are legitimate error conditions that could cause the creation of the store to fail.
        let fileManager = NSFileManager.defaultManager()
        var failError: NSError? = nil
        var shouldFail = false
        var failureReason = "There was an error creating or loading the application's saved data."

        // Make sure the application files directory is there
        do {
            let properties = try self.applicationDocumentsDirectory.resourceValuesForKeys([NSURLIsDirectoryKey])
            if !properties[NSURLIsDirectoryKey]!.boolValue {
                failureReason = "Expected a folder to store application data, found a file \(self.applicationDocumentsDirectory.path)."
                shouldFail = true
            }
        } catch  {
            let nserror = error as NSError
            if nserror.code == NSFileReadNoSuchFileError {
                do {
                    try fileManager.createDirectoryAtPath(self.applicationDocumentsDirectory.path!, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    failError = nserror
                }
            } else {
                failError = nserror
            }
        }
        
        // Create the coordinator and store
        var coordinator: NSPersistentStoreCoordinator? = nil
        if failError == nil {
            coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
            let url = self.applicationDocumentsDirectory.URLByAppendingPathComponent("CocoaAppCD.storedata")
            do {
                try coordinator!.addPersistentStoreWithType(NSXMLStoreType, configuration: nil, URL: url, options: nil)
            } catch {
                failError = error as NSError
            }
        }
        
        if shouldFail || (failError != nil) {
            // Report any error we got.
            var dict = [String: AnyObject]()
            dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data"
            dict[NSLocalizedFailureReasonErrorKey] = failureReason
            if failError != nil {
                dict[NSUnderlyingErrorKey] = failError
            }
            let error = NSError(domain: "YOUR_ERROR_DOMAIN", code: 9999, userInfo: dict)
            NSApplication.sharedApplication().presentError(error)
            abort()
        } else {
            return coordinator!
        }
    }()

    lazy var managedObjectContext: NSManagedObjectContext = {
        // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.) This property is optional since there are legitimate error conditions that could cause the creation of the context to fail.
        let coordinator = self.persistentStoreCoordinator
        var managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
        return managedObjectContext
    }()

    // MARK: - Core Data Saving and Undo support

    @IBAction func saveAction(sender: AnyObject!) {
        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        if !managedObjectContext.commitEditing() {
            NSLog("\(NSStringFromClass(self.dynamicType)) unable to commit editing before saving")
        }
        if managedObjectContext.hasChanges {
            do {
                try managedObjectContext.save()
            } catch {
                let nserror = error as NSError
                NSApplication.sharedApplication().presentError(nserror)
            }
        }
    }

    func windowWillReturnUndoManager(window: NSWindow) -> NSUndoManager? {
        // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
        return managedObjectContext.undoManager
    }

    func applicationShouldTerminate(sender: NSApplication) -> NSApplicationTerminateReply {
        // Save changes in the application's managed object context before the application terminates.
        
        if !managedObjectContext.commitEditing() {
            NSLog("\(NSStringFromClass(self.dynamicType)) unable to commit editing to terminate")
            return .TerminateCancel
        }
        
        if !managedObjectContext.hasChanges {
            return .TerminateNow
        }
        
        do {
            try managedObjectContext.save()
        } catch {
            let nserror = error as NSError
            // Customize this code block to include application-specific recovery steps.
            let result = sender.presentError(nserror)
            if (result) {
                return .TerminateCancel
            }
            
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info");
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButtonWithTitle(quitButton)
            alert.addButtonWithTitle(cancelButton)
            
            let answer = alert.runModal()
            if answer == NSAlertFirstButtonReturn {
                return .TerminateCancel
            }
        }
        // If we got here, it is time to quit.
        return .TerminateNow
    }
    
    func showNotification(content:String) -> Void {
        let unc = NSUserNotificationCenter.defaultUserNotificationCenter()
        unc.delegate = self
        let notification = NSUserNotification()
        notification.title = "TeamRadar"
        notification.informativeText = content
        unc.deliverNotification(notification)
    }
    
    func userNotificationCenter(center: NSUserNotificationCenter, shouldPresentNotification notification: NSUserNotification) -> Bool {
        return true
    }

}

