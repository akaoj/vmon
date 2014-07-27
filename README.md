vMON
====

A simple yet powerful monitoring for your server.

This tool has been built to allow a monitoring system to monitor the health of a machine in real-time. vMON is NOT designed to give a history of the machine health. It is only designed to give the state of a machine at a given moment.

The core of the vMON process is based on probes. Each probe is a very lightweight script that has a unique aim. For example, you may have a probe which will monitor the load average, another one which is designed to monitor the disk usage, the health of given services (like Apache or SSH), ...

vMON is seperated in 2 daemons:
* vmon-scheduler: this daemon is designed to run the probes at every given DELAY. If the probe has not finished running after TIMEOUT seconds, it will be killed (be careful: if DELAY is shorter than TIMEOUT, two or more identical probes may run in parallel)
* vmon-responder: this daemon will listen on a given port and send back the server's health on every sollicitation

# Statuses #

* these statuses can be returned by the probe:
    * 0     :   OK          (all is good)
    * 1     :   INFO        (all is good but something is worth being noticed)
    * 2     :   WARNING     (maybe not everything is good, but there is no need to be alarmed by now)
    * 3     :   ALERT       (well, now it's time to raise some alarms!)
    * 4     :   CRITICAL    (everything is fucked up and you're going to be fucked up as well if you don't handle this right now!)
* these statuses are set by VMON:
    * 5     :   TIMEOUT     (the probe has timed out, which means you have no way to know if the monitored service is healthy or not)
    * 6     :   DIED        (the probe died, this is not normal at all)
    * 7     :   INVALID     (the probe sent back an invalid status)
    * 8     :   OUTDATED    (the result of the probe is outdated - the out-of-date time is 3 times the DELAY; which means we accept 2 failures of the probe before sending a status 7 - note that if you have an OUTDATED value, it is very likely that vmon-scheduler is not running at all)
    * 9     :   MISSING     (the result file is missing)
    * 10    :   UNKNOWN     (what the hell happened?!)

A probe is any script that can be run by a shell (which means that it has to start with a shebang).

Every probe has to send back some data through STDOUT:
* the first line has to be one of the above statuses
* the following lines will be the details which will be included in the result file

If a probe send back some data through STDERR, all this data will be appended to its logfile

# Responder #

When sollicited, the responder will send back to the caller JSON-encoded data (one probe per line).
This JSON will represent a hash containing:
* probe     :   the probe name
* status    :   the status of this probe
* details   :   some additional details, if the probe sent back details
