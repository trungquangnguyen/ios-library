/*
Copyright 2009-2015 Urban Airship Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

import AirshipKit
import UIKit

class PushSettingsViewController: UITableViewController {

    @IBOutlet var pushEnabledCell: UITableViewCell!
    @IBOutlet var channelIDCell: UITableViewCell!
    @IBOutlet var namedUserCell: UITableViewCell!
    @IBOutlet var aliasCell: UITableViewCell!
    @IBOutlet var tagsCell: UITableViewCell!
    @IBOutlet var locationEnabledCell: UITableViewCell!
    @IBOutlet var getLocationCell: UITableViewCell!

    @IBOutlet var pushEnabledSwitch: UISwitch!
    @IBOutlet var locationEnabledSwitch: UISwitch!
    @IBOutlet var analyticsSwitch: UISwitch!

    @IBOutlet var pushSettingsLabel: UILabel!
    @IBOutlet var pushSettingsSubtitleLabel: UILabel!
    @IBOutlet var locationEnabledLabel: UILabel!
    @IBOutlet var locationEnabledSubtitleLabel: UILabel!
    @IBOutlet var channelIDSubtitleLabel: UILabel!
    @IBOutlet var namedUserSubtitleLabel: UILabel!
    @IBOutlet var aliasSubtitleLabel: UILabel!
    @IBOutlet var tagsSubtitleLabel: UILabel!

    @IBAction func switchValueChanged(sender: UISwitch) {

        if (pushEnabledSwitch.on) {
            UAirship.push().userPushNotificationsEnabled = true
        }

        UALocationService.setAirshipLocationServiceEnabled(true)
        UALocationService.setAirshipLocationServiceEnabled(false)
        UAirship.shared().analytics.enabled = analyticsSwitch.on
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NSNotificationCenter.defaultCenter().addObserver(
            self,
            selector: "channelIDUpdated",
            name: "channelIDUpdated",
            object: nil);

        // Initialize switches
        pushEnabledSwitch.on = UAirship.push().userPushNotificationsEnabled
        locationEnabledSwitch.on = UALocationService.airshipLocationServiceEnabled()
        analyticsSwitch.on = UAirship.shared().analytics.enabled

        // add observer to didBecomeActive to update upon retrun from system settings screen
        NSNotificationCenter.defaultCenter().addObserver(
            self,
            selector: "didBecomeActive",
            name: UIApplicationDidBecomeActiveNotification,
            object: nil)

        locationEnabledLabel.text = NSLocalizedString("UA_Location_Enabled", tableName: "UAPushUI", comment: "Location Enabled label")
        locationEnabledSubtitleLabel.text = NSLocalizedString("UA_Location_Enabled_Detail", tableName: "UAPushUI", comment: "Enable GPS and WIFI Based Location detail label")

        getLocationCell.textLabel!.text = NSLocalizedString("UA_Get_Location", tableName: "UAPushUI", comment: "Get location label")
    }

    // this is necessary to update the view when returning from the system settings screen
    func didBecomeActive () {
        refreshView()
    }

    override func viewWillAppear(animated: Bool) {
        refreshView()
    }

    func refreshView() {

        channelIDSubtitleLabel?.text = UAirship.push().channelID
        
        aliasSubtitleLabel?.text = UAirship.push().alias == nil ? NSLocalizedString("None", tableName: "UAPushUI", comment: "None") : UAirship.push().alias

        namedUserSubtitleLabel?.text = UAirship.push().namedUser.identifier == nil ? NSLocalizedString("None", tableName: "UAPushUI", comment: "None") : UAirship.push().namedUser.identifier

        if (UAirship.push().tags.count > 0) {
            self.tagsSubtitleLabel?.text = UAirship.push().tags.joinWithSeparator(", ")
        } else {
            self.tagsSubtitleLabel?.text = NSLocalizedString("None", tableName: "UAPushUI", comment: "None")

        }

        // push cannot be deactivated, so remove switch and link to system settings.
        if UAirship.push().userPushNotificationsEnabled {
            pushSettingsLabel.text = NSLocalizedString("UA_Push_Settings_Title", tableName: "UAPushUI", comment: "System Push Settings Label")

            pushSettingsSubtitleLabel.text = pushTypeString()
            pushEnabledSwitch?.hidden = true
            pushEnabledCell.selectionStyle = .Default
        }

    }

    func pushTypeString () -> String {

        let types = UIApplication.sharedApplication().currentUserNotificationSettings()?.types
        var typeArray: [String] = []

        if (types!.contains(UIUserNotificationType.Alert)) {
            typeArray.append(NSLocalizedString("UA_Notification_Type_Alerts", tableName: "UAPushUI", comment: "Alerts"))
        }
        if (types!.contains(UIUserNotificationType.Badge)){
            typeArray.append(NSLocalizedString("UA_Notification_Type_Badges", tableName: "UAPushUI", comment: "Badges"))
        }
        if (types!.contains(UIUserNotificationType.Sound)) {
            typeArray.append(NSLocalizedString("UA_Notification_Type_Sounds", tableName: "UAPushUI", comment: "Sounds"))
        }
        if (types! == UIUserNotificationType.None) {
            return NSLocalizedString("UA_Push_Settings_Link_Disabled_Title", tableName: "UAPushUI", comment: "Pushes Currently Disabled")
        }

        return typeArray.joinWithSeparator(", ")
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)

        switch (indexPath.section, indexPath.row) {
            case (tableView.indexPathForCell(pushEnabledCell)!.section, tableView.indexPathForCell(pushEnabledCell)!.row) :
                if UAirship.push().userPushNotificationsEnabled {
                    UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
                }
                break
            case (tableView.indexPathForCell(channelIDCell)!.section, tableView.indexPathForCell(channelIDCell)!.row) :
                UIPasteboard.generalPasteboard().string = channelIDSubtitleLabel?.text
                break
            case (tableView.indexPathForCell(namedUserCell)!.section, tableView.indexPathForCell(namedUserCell)!.row) :
                UIPasteboard.generalPasteboard().string = namedUserSubtitleLabel?.text
                break
            default:
                break
        }
    }
    
    func channelIDUpdated () {
        refreshView()
    }
}




