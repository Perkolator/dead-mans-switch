## Dead Man's Switch

A script for unmounting inactive encrypted shares automatically on Synology NAS devices. Meant to be run from DSM 6/7 Task Scheduler.

Tested to work with DSM versions:
- 6.2.2-24922-4 (2019-11-05) ==> 6.2.4-25556 Update 7 (2023-05-02)

  > Version branches 7.0.x and 7.1.x have not been tested but should work ok.
- 7.2-64570 Update 1 (2023-06-19) ==> 7.2-64570 Update 3 (2023-08-03)
- 7.2.1-69057 (2023-09-26) ==> 7.2.1-69057 Update 5 (2024-04-08)
- 7.2.2-72803 (2024-08-26) ==> 7.2.2-72806 Update 4 (2025-07-24)
- 7.3-81180 (2025-10-08) ==> 7.3.1-86003 (2025-10-28)

> [!NOTE]
> DSM 7.3 will be the last upgradable version for my DS218+ device, so I can't test this script for newer DSM version branches. Since my device is still working fine, I have no plans to upgrade to a newer model in the near future. Sorry. Unless somebody wants to donate. :)


## Download

Latest release can be found from the [releases page](https://github.com/Perkolator/dead-mans-switch/releases) and full changelog [here](https://github.com/Perkolator/dead-mans-switch/blob/master/CHANGELOG.md).


## Help

### Usage

`/bin/bash <full path>/dead_mans_switch.bash [OPTION]...`

**Example**: `/bin/bash /volume1/share/folder/dead_mans_switch.bash -d 3 --email`


### Options

If none of the options are used, the script unmounts an encrypted share after 2 days of inactivity, only logs unmount messages and no emails will be sent.

Option | Description
:----- |:-----------
`-d NUMBER` <br />or <br />`--days NUMBER` | Unmount after number of days of inactivity. <br />Default value 2.
`-s`  <br />or <br /> `--strict` | Unmount ALL if even one of the mounted encrypted shares <br />is found inactive (or has never been accessed, or returns <br />an error or an invalid time value from a database query), <br />regardless of when other shares have been last accessed.
`-l NUMBER` <br />or <br />`--log NUMBER` | Logging: <br />0) None <br />1) Unmount events (default) <br />2) Full
`-e` <br />or <br />`--email` | Email log. Empty unmount logs will not be sent. <br />Note! Script exits with an error code for this to work.
`-h` <br />or <br />`--help` | Display help text.


### Required settings

- Email notification service from Synology "Control Panel -> Notification" needs to be enabled for the email log sending feature to work properly.

- "Save output results" needs to be enabled from Synology "Control Panel -> Task Scheduler -> Settings" for the logging to work.

- "Send run details by email" and "Send run details only when the script terminates abnormally" needs to be enabled from the task settings.

- Script file needs executable rights and task should be run with "root" user.


## Notes

### How does this script work?

Synology creates "accessed" database entries for shares that are connected to from some device, for example when mounting/connecting to shares at boot time, or when coming out of a sleep state. These database entries are used by this script to detect inactivity of the shares.

The precision of detecting inactivity isn't that great because Synology creates these database entries only when it detects "new" connections to the shares. For example, if a device is left running for many days with an "active" connection to a share, Synology won't create a new "accessed" database entry for that share and this script would close the share when the "days" option condition is met. Therefore at least one device that connects to the shares have to be, for example, shutdown, or put to sleep, regularly within the allowed inactivity period set with the "days" option in order for this script to work properly.

However, if some device on your network, or remotely, automatically connects to encrypted shares in a way that creates new "accessed" database entries, for example automatically mounts/connects to shares for some tasks and then unmounts/disconnects regularly within the allowed inactivity period set with the "days" option, this script obviously won't work properly.

In DSM 7, unmounting even one of the encrypted shares creates new "accessed" database entries for all still mounted shares that have active connections to them, for example, if a device is left running with mounted shares.

Version 2.x of this script fixes problems this creates, except one problem because it's difficult to deduce which "accessed" entry from the database would be valid for the purposes of this script. If a new "accessed" database entry is created for a share when unmounting some other share, in other words, when not all shares have the same last "accessed" database entries, this obviously delays the unmounting of the share. However, in this situation, this script **WILL** eventually unmount all shares, it just takes, in overall, double amount of time of what the "days" option is set to. To mitigate this hindrance, a new "strict" option was created and the default value of the "days" option was changed from 3 to 2.


### Miscellaneous

Save the script file and Task Scheduler output results to a normal, unencrypted share. For example, create a new share called "System".

Scheduling a task to run the script once or twice a day should be enough to give reasonable precision and functionality.

At first, and also after Synology DSM update, it's wise to run the script with full logging and email options to see that all works as expected.

Any detected errors are always emailed, whether the email option is used or not.

