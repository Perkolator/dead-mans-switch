## Dead Man's Switch

A script for unmounting inactive encrypted shares automatically on Synology NAS devices. Meant to be run from Synology DSM Task Scheduler.

Tested to work with Synology DSM version 6.2.2-24922-4 (2019-11-05).


## Download

Latest release can be found from the [releases page](https://github.com/Perkolator/dead-mans-switch/releases).


## Help


### Usage

`bash <full path>/dead_mans_switch.bash [OPTION]...`

**Example**: `bash <full path>/dead_mans_switch.bash -d 2 --email`


### Options

All of these are optional. For example, if none of the options are used, the script unmounts an encrypted share after 3 days of inactivity, only logs unmount messages and no emails will be sent.

Option | Description
:----- |:-----------
`-d NUMBER` <br />or <br />`--days NUMBER` | Unmount after number of days of inactivity. <br />Default value 3.
`-l NUMBER` <br />or <br />`--log NUMBER` | Log script output: <br />0 = No logging <br />1 = Unmount logging (Default) <br />2 = Full logging
`-e` <br />or <br />`--email` | Email log. Empty unmount logs will not be sent. <br />Note! Script exits with an error code for this to work.


### Required settings

- Email notification service from Synology "Control Panel -> Notification" needs to be enabled for the email log sending feature to work properly.

- "Save output results" needs to be turned on from Synology "Control Panel -> Task Scheduler -> Settings" for the logging to work.

- "Send run details by email" and "Send run details only when the script terminates abnormally" needs to be turned on from the task settings.

- Script file needs executable rights and task should be run with "root" user.


## Notes

"Inactivity" means no user connections to shares. The precision of detecting inactivity isn't that great because Synology doesn't log every connection to a share. It's safe to assume at least one logged connection to a share per day if the user is actively using the share. Scheduling a task to run the script once or twice a day should be enough to give reasonable precision and functionality.

At first, and also after Synology DSM update, it's wise to run the script with full logging and email options for a while to see that all works as expected.

Any detected errors are always emailed, whether the email option is used or not.

If some machine on your network, or remotely, automatically connects to an encrypted share, this script obviously won't work properly.
