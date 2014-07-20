vmon
====

A simple yet powerful monitoring for your server.



Each probe will be run every DELAY seconds. If the probe has not finished running after TIMEOUT seconds, it will be killed.

# Statuses #

* these statuses can be returned by the probe:
    * 0   :   OK          (all is good)
    * 1   :   INFO        (all is good but something is worth being noticed)
    * 2   :   WARNING     (maybe not everything is good, but there is no need to be alarmed by now)
    * 3   :   ALERT       (well, now it's time to raise some alarms!)
    * 4   :   CRITICAL    (everything is fucked up and you're going to be fucked up as well if you don't handle this right now!)
* these statuses are set by VMON:
    * 5   :   TIMEOUT     (the probe has timed out, which means you have no way to know if the monitored service is healthy or not)
    * 6   :   DIED        (the probe died)
    * 7   :   OUTDATED    (the result of the probe is outdated - the out-of-date time is 3 times the DELAY; which means we accept 2 failures of the probe before sending a status 7)
    * 8   :   INVALID     (the probe sent back an invalid status)
    * 10  :   UNKNONW     (what the hell happened?!)

A probe is any script that can be run by a shell (which means that it has to start with a shebang).

Every probe has to send back some data through STDOUT:
* the first line has to be one of the above statuses
* the following lines will be the details which will be included in the result file

If a probe send back some data through STDERR, all this data will be appended to its logfile
