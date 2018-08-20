# mqttwarn

To _warn_, _alert_, or _notify_.

![Definition by Google](assets/google-definition.jpg)

This program subscribes to any number of MQTT topics (which may include wildcards) and publishes received payloads to one or more notification services, including support for notifying more than one distinct service for the same message.

![definition by Google](assets/mqttwarn.png)

Notifications are transmitted to the appropriate service via plugins. We provide plugins for the list of services [below](#supported-notification-services), and you can easily add your own.

I've written an introductory post, explaining [what mqttwarn can be used for](http://jpmens.net/2014/04/03/how-do-your-servers-talk-to-you/). For example, you may wish to notify via e-mail and to Pushover of an alarm published as text to the MQTT topic `home/monitoring/+`.

  * [Getting started](#getting-started)
    + [Requirements](#requirements)
    + [Installation](#installation)
    + [Configuration](#configuration)
  * [Supported Notification Services](#supported-notification-services)
    + [Configuration of service plugins](#configuration-of-service-plugins)
    + [Creating Custom Service Plugins](#creating-custom-service-plugins)
  * [Transformation](#transformation)
  * [Advanced features](#advanced-features)
    + [JSON output serialization](#json-output-serialization)
    + [Transformation data](#transformation-data)
    + [Using functions to replace incoming payloads](#using-functions-to-replace-incoming-payloads)
    + [Incorporating topic names into transformation data](#incorporating-topic-names-into-transformation-data)
    + [Merging more data](#merging-more-data)
    + [Accessing Nested JSON Nodes](#accessing-nested-json-nodes)
    + [Using transformation data in other contexts](#using-transformation-data-in-other-contexts)
    + [Filtering notifications](#filtering-notifications)
    + [Templates](#templates)
    + [Periodic tasks](#periodic-tasks)
  * [Running with Docker](#running-with-docker)
    + [Run the Image](#run-the-image)
    + [Build the image](#build-the-image)
    + [Deploy the Image (Administrators Only)](#deploy-the-image-administrators-only)
  * [Examples](#examples)
    + [Low battery notifications](#low-battery-notifications)
    + [Producing JSON](#producing-json)
  * [Notes](#notes)
  * [Press](#press)
  
      
  ## Getting started
  
  ### Requirements
  
  You'll need at least the following components:
  
  * Python 2.x (tested with 2.6 and 2.7)
  * An MQTT broker (e.g. [Mosquitto](http://mosquitto.org))
  * The Paho Python module: `pip install paho-mqtt`
  
  ### Installation
  
  1. Clone this repository into a fresh directory.
  2. Copy `mqttwarn.ini.sample` to `mqttwarn.ini` and edit to your taste
  3. Install the prerequisite Python modules for the services you want to use
  4. Launch `mqttwarn.py`
  
  I recommend you use [Supervisor](http://jpmens.net/2014/02/13/in-my-toolbox-supervisord/) for running this.
  
  Alternatively, a systemd-based installation using a Python virtualenv might be handy,
  see [systemd unit configuration file for mqttwarn](https://github.com/jpmens/mqttwarn/blob/master/etc/mqttwarn.service)
  for step-by-step instructions about doing this.
  
  ### Configuration
  
  I recommend you start off with the following simple configuration which will log messages received on the MQTT topic `test/+` to a file. Create the following configuration file:
  
  ```ini
  [defaults]
  hostname  = 'localhost'
  port      = 1883
  
  ; name the service providers you will be using.
  launch	 = file, log
  
  [config:file]
  append_newline = True
  targets = {
      'mylog'     : ['/tmp/mqtt.log']
      }
  
  [config:log]
  targets = {
      'info'   : [ 'info' ]
    }
  
  [test/+]
  targets = file:mylog, log:info
  ```
  
  **Note**: the closing brace `}` of the `targets` dict must be indented; this is an artifact of ConfigParser.
  
  Launch `mqttwarn.py` and keep an eye on its log file (`mqttwarn.log` by default). Publish two messages to the subscribed topic, using
  
  ```
  mosquitto_pub -t test/1 -m "Hello"
  mosquitto_pub -t test/name -m '{ "name" : "Jane" }'
  ```
  
  and our output file `/tmp/mqtt.log` should contain the payload of both messages:
  
  ```shell
  Hello
  { "name" : "Jane" }
  ```
  
  Both payloads where copied verbatim to the target.
  
  Stop _mqttwarn_, and add the following line to the `[test/+]` section:
  
  ```ini
  format  = -->{name}<--
  ```
  
  What we are configuring _mqttwarn_ to do here, is to try and decode the incoming JSON payload and format the output in such a way as that the JSON `name` element is copied to the output (surrounded with a bit of sugar to illustrate the fact that we can output whatever text we want).
  
  If you repeat the publish of the second message, you should see the following in your output file `/tmp/mqtt.log`:
  
  ```
  -->Jane<--
  ```
  
  #### The `[defaults]` section
  
  Most of the options in the configuration file have sensible defaults, and/or ought to be self-explanatory:
  
  ```ini
  [defaults]
  hostname     = 'localhost'         ; default
  port         = 1883
  username     = None
  password     = None
  clientid     = 'mqttwarn'
  lwt          = 'clients/mqttwarn'  ; lwt payload is '0' or '1'
  skipretained = True
  cleansession = False
  
  ; logging
  logformat = '%(asctime)-15s %(levelname)-5s [%(module)s] %(message)s'
  logfile   = 'mqttwarn.log'
  
  ; one of: CRITICAL, DEBUG, ERROR, INFO, WARN
  loglevel     = DEBUG
  
  ; path to file containing self-defined functions for formatmap, alldata, and datamap
  functions = 'myfuncs.py'
  
  ; name the service providers you will be using.
  launch   = file, log, osxnotify, mysql, smtp
  
  ; the directory to which we should cd after startup (default: ".")
  ; the cd is performed before loading service plugins, so it should
  ; contain a `services/' directory with the required service plugins.
  directory = /tmp/
  
  
  ; optional: TLS parameters. (Don't forget to set the port number for
  ; TLS (probably 8883).
  ; You will need to set at least `ca_certs' if you want TLS support
  ; ca_certs: path to the Certificate Authority certificate file (concatenated
  ;           PEM file)
  ; tls_version: currently either 'tlsv1' or 'sslv3'
  ; tls_insecure: True or False (False is default): Do or do not verify
  ;               broker's certificate CN
  ; certfile: path to PEM encode client certificate file
  ; keyfile: path to PEM encode client private key file
  ca_certs = '/path/to/ca-certs.pem'
  certfile = '/path/to/client.crt'
  keyfile = '/path/to/client.key'
  tls_version = 'tlsv1'
  tls_insecure = False
  
  ```
  
  ###### `functions`
  
  The `functions` option specifies the path to a Python file containing functions you use in formatting or filtering data (see below). The `.py` extension to the path name you configure here must be specified.
  
  ###### `launch`
  
  In the `launch` option you specify which _services_ (of those available in the `services/` directory of _mqttwarn_ or using the `module` option, see the following paragraphs) you want to be able to use in target definitions.
  
  #### The `[config:xxx]` sections
  
  Sections called `[config:xxx]` configure settings for a service _xxx_. Each of these sections
  has a mandatory option called `targets`, which is a dictionary of target names, each
  pointing to an array of "addresses". Address formats depend on the particular service.
  
  A service section may have an option called `module`, which refers to the name
  of the actual service module to use. A service called `filetruncate` - and
  referenced as such in the `launch` option -
  may have `module = file`, in which case the service works like a regular `file`
  service, with its own distinct set of service options. It is thus possible to
  have several different service configurations for the same underlying service,
  with different configurations, e.g. one for files that should have notifications
  appended, and one for files that should get truncated before writes.
  
  As an example for `module` consider this INI file in which we want two services of type log. We actually _launch_ an `xxxlog` (which doesn't physically exist), but due to the `module=log` setting in its configuration it is instantiated:
  
  ```ini
  [defaults]
  hostname  = 'localhost'  ; default
  port      = 1883
  
  launch	 = log, xxxlog
  
  [config:log]
  targets = {
      'debug'  : [ 'debug' ],
    }
  
  [config:xxxlog]
  # Note how the xxxlog is instantiated from log and both must be launched
  module = log
  targets = {
      'debug'  : [ 'debug' ],
    }
  
  
  [topic/1]
  targets = log:debug, xxxlog:debug
  ```
  
  #### The `[failover]` section
  
  There is a special section (optional) for defining a target (or targets) for internal error conditions. Currently there is only one error handled by this logic, broker disconnection.
  
  This allows you to setup a target for receiving errors generated within _mqttwarn_. The message is handled like any other with an error code passed as the `topic` and the error details as the `message`. You can use formatting and transformations as well as filters, just like any other _topic_.
  
  Below is an example which will log any failover events to an error log, and display them on all XBMC targets:
  
  ```ini
  [failover]
  targets  = log:error, xbmc
  title    = mqttwarn
  ```
  
  #### The `[__topic__]` sections
  
  All sections not called `[defaults]` or `[config:xxx]` are treated as MQTT topics
  to subscribe to. _mqttwarn_ handles each message received on this subscription
  by handing it off to one or more service targets.
  
  Section names must be unique and must specify the name of the topic to be processed. If the section block does not have a `topic` option,
  then the section name will be used.

  Consider the following example:
  
  ```ini
  [icinga/+/+]
  targets = log:info, file:f01, mysql:nagios
  
  [my/special]
  targets = mysql:m1, log:info

  [my/other/special]
  topic = another/topic
  targets = log:debug
  ```
  
  MQTT messages received at `icinga/+/+` will be directed to the three specified targets, whereas messages received
  at `my/special` will be stored in a `mysql` target and will be logged at level "INFO".  Messages received
  at `another/topic` (not at `my/other/special`) will be logged at level "DEBUG".
  
  When a message is received at a topic with more than one matching section it will be
  directed to the targets in all matching sections.  For consistency, it's a good practice
  to explicitly provide `topic` options to all such sections.
  
  Targets can be also defined as a dictionary containing the pairs of topic and targets. In that case message matching the section can be dispatched in more flexible ways to selected targets. Consider the following example:
  
  ```ini
  [#]
  targets = {
      '/#': 'file:0',
      '/test/#': 'file:1',
      '/test/out/#': 'file:2',
      '/test/out/+': 'file:3',
      '/test/out/+/+': 'file:4',
      '/test/out/+/state': 'file:5',
      '/test/out/FL_power_consumption/state': [ 'file:6', 'file:7' ],
      '/test/out/BR_ambient_power_sensor/state': 'file:8',
    }
  ```
  
  With the message dispatching configuration the message is dispatched to the targets matching the most specific topic. If the message is received at `/test/out/FL_power_consumption/state` it will be directed to `file:6` and `file:7` targets only. Message received at `/test/out/AR_lamp/state` will be directed to `file:5`, but received at `/test/out/AR_lamp/command` will go to `file:4`.
  The dispatcher mechanism is always trying to find the most specific match.
  It allows to define the wide topic with default targets while some more specific topic can be handled differently. It gives additional flexibility in a message routing.
  
  Each of these sections has a number of optional (`O`) or mandatory (`M`)
  options:
  
  | Option        |  M/O   | Description                                    |
  | ------------- | :----: | ---------------------------------------------- |
  | `targets`     |   M    | service targets for this SUB                   |
  | `topic`       |   O    | topic to subscribe to (overrides section name) |
  | `filter`      |   O    | function name to suppress this msg             |
  | `datamap`     |   O    | function name parse topic name to dict         |
  | `alldata`     |   O    | function to merge topic, and payload with more |
  | `format`      |   O    | function or string format for output           |
  | `priority`    |   O    | used by certain targets (see below). May be func()  |
  | `title`       |   O    | used by certain targets (see below). May be func()  |
  | `image`       |   O    | used by certain targets (see below). May be func()  |
  | `template`    |   O    | use Jinja2 template instead of `format`        |
  | `qos`         |   O    | MQTT QoS for subscription (dflt: 0)            |


## Supported Notification Services
_mqttwarn_ supports a number of services (listed alphabetically below):

* [amqp](#amqp)
* [apns](#apns)
* [asterisk](#asterisk)
* [autoremote](#autoremote)
* [carbon](#carbon)
* [celery](#celery)
* [dbus](#dbus)
* [dnsupdate](#dnsupdate)
* [emoncms](#emoncms)
* [execute](#execute)
* [facebook messenger](#fbchat)
* [file](#file)
* [freeswitch](#freeswitch)
* [gss](#gss)
* [gss2](#gss2)
* [hangbot](#hangbot)
* [hipchat](#hipchat)
* [http](#http)
* [icinga2](#icinga2)
* [ifttt](#ifttt)
* [influxdb](#influxdb)
* [instapush](#instapush)
* [ionic](#ionic)
* [iothub](#iothub)
* [irccat](#irccat)
* [linuxnotify](#linuxnotify)
* [log](#log)
* mastodon (see [tootpaste](#tootpaste))
* [mattermost](#mattermost)
* [mqtt](#mqtt)
* [mqttpub](#mqttpub)
* [mysql](#mysql)
* [mysql_dynamic](#mysql_dynamic)
* [mysql_remap](#mysql_remap)
* [mythtv](#mythtv)
* [nma](#nma)
* [nntp](#nntp)
* [nsca](#nsca)
* [osxnotify](#osxnotify)
* [osxsay](#osxsay)
* [pastebinpub](#pastebinpub)
* [pipe](#pipe)
* [postgres](#postgres)
* [prowl](#prowl)
* [pushalot](#pushalot)
* [pushbullet](#pushbullet)
* [pushover](#pushover)
* [pushsafer](#pushsafer)
* [redispub](#redispub)
* [rrdtool](#rrdtool)
* [serial](#serial)
* [slack](#slack)
* [sqlite](#sqlite)
* [sqlite_json2cols](#sqlite_json2cols)
* [sqlite_timestamp](#sqlite_timestamp)
* [smtp](#smtp)
* [ssh](#ssh)
* [syslog](#syslog)
* [telegram](#telegram)
* [thingspeak](#thingspeak)
* [tootpaste](#tootpaste)
* [twilio](#twilio)
* [twitter](#twitter)
* [websocket](#websocket)
* [xbmc](#xbmc)
* [xmpp](#xmpp)
* [xively](#xively)
* [zabbix](#zabbix)




### Configuration of service plugins

Service plugins are configured in the main `mqttwarn.ini` file. Each service has a mandatory _section_ named `[config:xxx]`, where `xxx` is the name of the service. This section _may_ have some settings which are required for a particular service, and all services have an rarely used option called `module` (see [The config:xxx sections](#the-configxxx-sections)) and one mandatory option called `targets`. This defines individual "service points" for a particular service, e.g. different paths for the `file` service, distinct database tables for `mysql`, etc.

We term the array for each target an "address list" for the particular service. These may be path names (in the case of the `file` service), topic names (for outgoing `mqtt` publishes), hostname/port number combinations for `xbmc`, etc.

### `amqp`

The `amqp` service basically implements an MQTT to AMQP gateway which is a little bit
overkill as, say, RabbitMQ already has a pretty versatile MQTT plugin. The that as it
may, the configuration is as follows:

```ini
[config:amqp]
uri     =  'amqp://user:password@localhost:5672/'
    'test01'     : [ 'name_of_exchange',    'routing_key' ],
    }
```

The exchange specified in the target configuration must exist prior to using this
target.

Requires: [Puka](https://github.com/majek/puka/) (`pip install puka`)

### `apns`

The `apns` service interacts with the Apple Push Notification Service (APNS) and
is a bit special (and one of _mqttwarn_'s more complex services) in as much as
it requires an X.509 certificate and a key which are typically available to
developers only.

The following discussion assumes one of these payloads published via MQTT:

```json
{"alert": "Vehicle moved" }
```

```json
{"alert": "Vehicle moved", "custom" : { "tid": "C2" }}
```

In both cases, the message which will be displayed in the notification of the iOS
device is "Vehicle moved". The second example depends on the app which receives
the notification. This custom data is per/app. This example app uses the custom
data to show a button:

![APNS notification](assets/apns.png)

This is the configuration we'll discuss.

```ini
[defaults]
hostname  = 'localhost'
port      = 1883
functions = 'myfuncs'

launch	 = apns

[config:apns]
targets = {
                 # path to cert in PEM format   # key in PEM format
    'prod'     : ['/path/to/prod.crt',          '/path/to/prod.key'],
    }

[test/token/+]
targets = apns
alldata = apnsdata()
format  = {alert}
```

Certificate and Key files are in PEM format, and the key file must *not* be
password-protected. (The PKCS#12 file you get as a developer can be extracted thusly:

```
openssl pkcs12 -in apns-CTRL.p12 -nocerts -nodes | openssl rsa > prod.key
openssl pkcs12 -in apns-CTRL.p12 -clcerts -nokeys  > xxxx
```

then copy/paste from `xxxx` the sandbox or production certificate into `prod.crt`.)

The _myfuncs_ function `apnsdata()` extracts the last part of the topic into
`apns_token`, the hex token for the target device, which is required within the
`apns` service.

```python
def apnsdata(topic, data, srv=None):
    return dict(apns_token = topic.split('/')[-1])
```

A publish to topic `test/token/380757b117f15a46dff2bd0be1d57929c34124dacb28d346dedb14d3464325e5`
would thus emit the APNS notification to the specified device.


Requires [PyAPNs](https://github.com/djacobs/PyAPNs)

### `autoremote`

The `autoremote` service forwards messages from desired topics to autoremote clients.
```ini

[config:autoremote]
targets = {
	'conv2' : [ 'ApiKey', 'Password', 'Target', 'Group', 'TTL' ]
  }

[autoremote/user]
targets = autoremote:conv2
```

Any messages published to autoremote/user would be sent the autoremote client
designated to the ApiKey provided. The "sender" variable of autoremote is equal to
the topic address.

https://joaoapps.com/autoremote/

### `carbon`

The `carbon` service sends a metric to a Carbon-enabled server over TCP.

```ini
[config:carbon]
targets = {
        'c1' : [ '172.16.153.110', 2003 ],
  }

[c/#]
targets = carbon:c1
```

In this configuration, all messages published to `c/#` would be forwarded to
the Carbon server at the specified IP address and TCP port number.

The topic name is translated into a Carbon _metric_ name by replacing slashes
by periods. A timestamp is appended to the message automatically.

For example, publishing this:

```
mosquitto_pub -t c/temp/arduino -m 12
```

would result in the value `12` being used as the value for the Carbon metric
`c.temp.arduino`. The published payload may contain up to three white-space-separated
parts.

1. The carbon metric name, dot-separated (e.g. `room.temperature`) If this is omitted, the MQTT topic name will be used as described above.
2. The integer value for the metric
3. An integer timestamp (UNIX epoch time) which defaults to "now".

In other words, the following payloads are valid:

```
15					just the value (metric name will be MQTT topic)
room.living 15				metric name and value
room.living 15 1405014635		metric name, value, and timestamp
```

### `celery`

The `celery` service sends messages to celery which celery workers can consume.

```ini
[config:celery]
broker_url = 'redis://localhost:6379/5'
app_name = 'celery'
celery_serializer = 'json'
targets = {
   'hello': [
      {
        'task': 'myapp.hello',
        'message_format': 'json'
        }
      ],
  }

[hello/#]
targets = celery:hello
```
Broker URL can be any broker supported by celery. Celery serializer is usually json or pickle. Json is recommended for security.
Targets are selected by task name. Message_format can be either "json" or "text". If it is json, the message will be sent as a json payload rather than a string.
In this configuration, all messages that match hello/ will be sent to the celery task "myapp.hello". The first argument of the celery task will be the message from mqtt.


### `dbus`

The `dbus` service send a message over the dbus to the user's desktop (only
tested with Gnome3).

```ini
[config:dbus]
targets = {
    'warn' : [ 'Warning' ],
    'note' : [ 'Note' ]
    }
```

Requires:
* Python [dbus](http://www.freedesktop.org/wiki/Software/DBusBindings/#Python) bindings

### `dnsupdate`

The `dnsupdate` service updates an authoritative DNS server via RFC 2136 DNS Updates.
Consider the following configuration:

```ini
[config:dnsupdate]
dns_nameserver = '127.0.0.2'
dns_keyname= 'mqttwarn-auth'
dns_keyblob= 'kQNwTJ ... evi2DqP5UA=='
targets = {
   #target             DNS-Zone      DNS domain              TTL,  type
   'temp'         :  [ 'foo.aa.',     'temperature.foo.aa.', 300, 'TXT'   ],
   'addr'         :  [ 'foo.aa.',     'www.foo.aa.',         60,  'A'   ],
  }

[test/temp]
targets = log:info, dnsupdate:temp
format = Current temperature: {payload}C

[test/a]
targets = log:info, dnsupdate:addr
format = {payload}
```

`dns_nameserver` is the address of the authoritative server the update should be sent
to via a TCP update. `dns_keyname` and `dns_keyblob` are the TSIG key names and base64-representation of the key respectively. These can be created with either of:

```
ldns-keygen  -a hmac-sha256 -b 256 keyname
dnssec-keygen -n HOST -a HMAC-SHA256 -b 256 keyname
```

where _keyname_ is the name then added to `dns_keyname` (in this example: `mqttwarn-auth`).

Supposing a BIND DNS server configured to allow updates, you would then configure it
as follows:

```
key "mqttwarn-auth" {
  algorithm hmac-sha256;
  secret "kQNwTJ ... evi2DqP5UA==";
};

...
zone "foo.aa" in {
   type master;
   file "keytest/foo.aa";
   update-policy {
      grant mqttwarn-auth. zonesub ANY;
   };
};
```

For the `test/temp` topic, a pub and the resulting DNS query:

```
$ mosquitto_pub -t test/temp -m 42'
$ dig @127.0.0.2 +noall +answer temperature.foo.aa txt
temperature.foo.aa. 300 IN  TXT "Current temperature: 42C"
```

The `test/a` topic expects an address:

```
$ mosquitto_pub -t test/a -m 172.16.153.44
$ dig @127.0.0.2 +short www.foo.aa
172.16.153.44
```

Ensure you watch both mqttwarn's logfile as well as the log of your
authoritative name server which will show you what's going on:

```
client 127.0.0.2#52786/key mqttwarn-auth: view internal: updating zone 'foo.aa/IN': adding an RR at 'www.foo.aa' A 172.16.153.44
```

Requires:
* [dnspython](http://www.dnspython.org)

### `emoncms`

The `emoncms` service sends a numerical payload to an [EmonCMS](http://emoncms.org/) instance. [EmonCMS](http://emoncms.org/) is a powerful open-source web-app for processing, logging and visualising energy, temperature and other environmental data.

The web-app can run locally or you can upload your readings to their server for viewing and monitoring via your own login (note this is likely to become a paid service in the medium term). See http://emoncms.org for details on installing and configuring your own instance.

By specifying the node id and input name in the mqttwarn target (see the ini example below) you can split different feeds into different nodes, and give each one a human readable name to identify them in EmonCMS.

```ini
[config:emoncms]
url     = <url of emoncms server e.g. http://localhost/emoncms or http://emoncms.org/emoncms>
apikey  = <apikey generated by the emoncms server>
timeout = 5
targets = {
    'usage'  : [ 1, 'usage' ],  # [ <nodeid>, <name> ]
    'solar'  : [ 1, 'solar' ]
    }
```

### `execute`

The `execute` target launches the specified program and its arguments. It is similar
to `pipe` but it doesn't open a pipe to the program.
Example use cases are f.e. IoT buttons which publish a message when they are pushed
and the execute an external program. It is also a light version of [mqtt-launcher](https://github.com/jpmens/mqtt-launcher).

```ini
[config:execute]
targets = {
             # argv0 .....
   'touch' : [ 'touch', '/tmp/executed' ]
   }
```

To pass the published data (text) to the command, use `[TEXT]` which then gets replaced.
This can also be configured with the `text_replace` parameter.

Note, that for each message targeted to the `execute` service, a new process is
spawned (fork/exec), so it is quite "expensive".

### `fbchat`

Notification of one [Facebook](http://facebook.com) account requires an account.
For now, this is only done for messaging from one account to another.

Upon configuring this service's targets, make sure the three (3) elements of the
list are in the order specified!

```ini
[config:fbchat]
targets = {
  'janejol'   :  [ 'vvvvvvvvvvvvvvvvvvvvvv',                              # username sending message
                   'wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww',          # username's password (sending message)
                   'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'  # destination account (receiving message)
                  ]
   }
```

Requires:
* A Facebook account
* [python-fbchat](https://github.com/yakhira/fbchat)

### `file`

The `file` service can be used for logging incoming topics, archiving, etc. Each message is written to a path specified in the targets list. Note that files are opened for appending and then closed on each notification.

Supposing we wish to archive all incoming messages to the branch `arch/#` to a file `/data/arch`, we could configure the following:

```ini
[config:file]
append_newline = True
overwrite = False
targets = {
    'log-me'    : ['/data/arch']
   }
```

If `append_newline` is True, a newline character is unconditionally appended to the string written to the file. If `overwrite` is True, the file is opened for truncation upon writing (i.e. the file will contain the last message only).


### `freeswitch`

The `freeswitch` service will make a VOIP call to the number specified in your target and 'speak' the message using the TTS service you specify. Each target includes the gateway to use as well as the number/extension to call, so you can make internal calls direct to an extension, or call any external number using your external gateway.

In order to use this service you must enable the XML RPC API in Freeswitch - see instructions [here](http://wiki.freeswitch.org/wiki/Mod_xml_rpc).

You need to provide a TTS URL to perform the conversion of your message to an announcement. This can be an online service like VoiceRSS or the [Google Translate API](translate.google.com) (see example below). Or it could be a local TTS service you are using.

```ini
[config:freeswitch]
host      = 'localhost'
port      = 8050
username  = 'freeswitch'
password  = '<xml_rpc_password>'
ttsurl    = 'translate.google.com/translate_tts?'
ttsparams = { 'tl': 'en', 'ie': 'UTF-8', 'client': 'mqttwarn', 'q': '{payload}' }
targets   = {
    'mobile'    : ['sofia/gateway/domain/', '0123456789']
    }
```

Requires
* [Freeswitch](https://www.freeswitch.org/)
* Internet connection for Google Translate API

### `asterisk`

The `asterisk` service will make a VOIP conference between the number and the extension (in defined context). Also it sends the message as variable to the extension, so you can 'speak' to it. Configuration is similar as with the [freeswitch](#freeswitch) service, but in service uses [Asterisk Manager Interface (AMI)](https://wiki.asterisk.org/wiki/pages/viewpage.action?pageId=4817239).

The plugin author strongly recommends you use AMI only in trusted networks.

```ini
[config:asterisk]
host     = 'localhost'
port     = 5038
username = 'mqttwarn'
password = '<AMI password>'
extension = 2222
context = 'default'
targets  = {
    'user'    : ['SIP/avaya/', '0123456789']
          }
```

Requires

* [Asterisk](http://www.asterisk.org/) with configured AMI interface (manager.conf)
* pyst2 -  powerful Python abstraction of the various Asterisk APIs (pip install pyst2)

### `gss`

The `gss` service interacts directly with a Google Docs Spreadsheet. Each message can be written to a row in a selected worksheet.

Each target has two parameters:

1. The spreadsheet key. This is directly obtainable from the URL of the open sheet.
2. The worksheet id. By default the first sheets id is 'od6'

```ini
[config:gss]
username    = your.username@gmail.com
password    = yourpassword
targets     = {
               # spreadsheet_key                               # worksheet_id
    'test': [ 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',  'od6']
    }
```

Example:

```
mosquitto_pub -t nn/ohoh -m '{"username": "jan", "device":"phone", "lat": "-33.8746097", "lon": "18.6292892", "batt": "94"}'
```

turns into

![GSS](assets/gss.png)

Note: It is important that the top row into your blank spreadsheet has column headings that correspond the values that represent your dictionary keys.
If these column headers are not available, you will most likely see an error like this:

```
gdata.service.RequestError: {'status': 400, 'body': 'We&#39;re sorry, a server error occurred. Please wait a bit and try reloading your spreadsheet.', 'reason': 'Bad Request'}
```

Requires:
* [gdata-python-client](https://code.google.com/p/gdata-python-client/)


### `gss2`

The `gss2` service interacts directly with a Google Docs Spreadsheet. Each message can be written to a row in a selected worksheet.

Each target has two parameters:

1. The spreadsheet URL. You can copy the URL from your browser that shows the spreadsheet.
2. The worksheet name. Try "Sheet1".

```ini
[config:gss2]
client_secrets_filename = client_secrets.json
oauth2_code =
oauth2_storage_filename = oauth2.store
targets = {
    # spreadsheet_url                                          # worksheet_name
    'test': [ 'https://docs.google.com/spre...cdA-ik8uk/edit', 'Sheet1']
    # This target would be addressed as 'gss2:test'.
    }
```

Note: It is important that the top row into your blank spreadsheet has column headings that correspond the values that represent your dictionary keys. If these column headers are not available or different from the dictionary keys, the new rows will be empty.

Note: Google Spreadsheets initially consist of 100 or 1,000 empty rows. The new rows added by `gss2` will be *below*, so you might want to delete those empty rows.

Other than `gss`, `gss2` uses OAuth 2.0 authentication. It is a lot harder to get working - but it does actually work.

Here is an overview how the authentication with Google works:

1. You obtain a `client_secrets.json` file from Google Developers Console.
1. You reference that file in the `client_secrets_filename` field and restart mqttwarn.
1. You grab an URL from the logs and visit that in your web browser.
1. You copy the resulting code to `mqttwarn.ini`, field `oauth2_code`
   and restart mqttwarn.
1. `gss2` stores the eventual credentials in the file you specified in
   field `oauth2_storage_filename`.
1. Everyone lives happily ever after. I hope you reach this point without
   severe technology burnout.
1. Technically, you could remove the code from field `oauth2_code`,
   but it does not harm to leave it there.

Now to the details of this process:
The contents of the file `client_secrets_filename` needs to be obtained by you as described in the [Google Developers API Client Library for Python docs](https://developers.google.com/api-client-library/python/auth/installed-app) on OAuth 2.0 for an Installed Application.
Unfortunately, [Google prohibits](http://stackoverflow.com/a/28109307/217001) developers to publish their credentials as part of open source software. So you need to get the credentials yourself.

To get them:

1. Log in to the Google Developers website from
  [here](https://developers.google.com/).
1. Follow the instructions in section `Creating application credentials` from
  the [OAuth 2.0 for Installed Applications](https://developers.google.com/api-client-library/python/auth/installed-app#creatingcred) chapter.
  You are looking for an `OAuth client ID`.
1. In the [Credentials screen of the API manager](https://console.developers.google.com/apis/credentials)
  there is a download icon next to your new client ID. The downloaded
  file should be named something like `client_secret_664...json`.
1. Store that file near e.g. `mqttwarn.ini` and ensure the setting
  `client_secrets_filename` has the valid path name of it.

Then you start with the `gss2` service enabled and with the `client_secrets_filename` readable. Once an event is to be published, you will find an error in the logs with a URL that you need to visit with a web browser that is logged into your Google account. Google will offer you to accept access to
Google Docs/Drive. Once you accept, you get to copy a code that you need to paste into field `oauth2_code` and restart mqttwarn.

The file defined in `oauth2_storage_filename` needs to be missing or writable and will be created or overwritten. Once OAuth credentials have been established (using the `oauth2_code`), they are persisted in there.

Requires:
* [google-api-python-client](https://pypi.python.org/pypi/google-api-python-client/)
  (`pip install google-api-python-client`)
* [gspread](https://github.com/burnash/gspread)
  (`pip install gspread`)

### `hangbot`

The hangbot service allows messages to be forwarded to a Google Hangouts account using hangoutsbot api plugin.
https://github.com/hangoutsbot/hangoutsbot/wiki/API-Plugin

```ini
[config:hangbot]
targets = {
		 #URL		 #PORT	 #ApiKey	#Conversation ID
   'conv1'   : ['ServerAddress', 'Port', 'xxxxxxxxxxx', 'xxxxxxxxxxxxxxxxxxxx']
  }
```

### `hipchat`

The `hipchat` plugin posts messages to rooms of the hipchat.com service or self-hosted edition. The configuration of this service requires an API v2 token and RoomID (you can configure them on hipchat.com => Group Admin => Rooms => Tokens) only the Send Notification scope is required.


```ini
[config:hipchat]

#server = "hipchat.example.com"  # Optional, default is api.hipchat.com
timeout = 10 # Default 60 seconds

targets = {
                     #token         #roomid  #color #notify
  'room-ops'    : [ "yyyyyyyyyyyyy", "000", "red", True ],
  'room-dev'    : [ "xxxxxxxxxxxxx", "111", "green", False ]
  }
```

The available colors for the background of the message are: "yellow", "green", "red", "purple", "gray" or if you feel lucky "random"

The notify parameter (True or False) trigger a user notification (change the tab color, play a sound, notify mobile phones, etc).

![Hipchat](assets/hipchat.png)

### `http`

The `http` service allows GET and POST requests to an HTTP service.

Each target has five parameters:

1. The HTTP method (one of `get` or `post`)
2. The URL, which is transformed if possible (transformation errors are ignored)
3. `None` or a dict of parameters. Each individual parameter value is transformed.
4. `None` or a list of username/password e.g. `( 'username', 'password')`
5. `None` or True to force the transformation of the third parameter to a json object and to send the HTTP header `Content-Type` with a value of `application/json` when using `post`

```ini
[config:http]
timeout = 60

targets = {
                #method     #URL               # query params or None                              # list auth # Json
  'get1'    : [ "get",  "http://example.org?", { 'q': '{name}', 'isod' : '{_dtiso}', 'xx': 'yy' }, ('username', 'password') ],
  'post1'    : [ "post", "http://example.net", { 'q': '{name}', 'isod' : '{_dtiso}', 'xx': 'yy' }, None, True ]
  }
```

If you want to use the mqtt message content directly in the query parameters use `'{payload}'`

Note that transforms in parameters must be quoted strings:

* Wrong: `'q' : {name}`
* Correct: `'q' : '{name}'`

As a special case, if the quoted parameter starts with an `@` character (e.g.
`'@name'`, it will not be formatted via `.format()`; instead, `name` is taken
directly from the transformation data.


### `icinga2`

This service is for the REST API in [Icinga2](https://www.icinga.org/products/icinga-2/). Icinga2 is an open source monitoring solution.

Using this service JSON payloads can be sent to your Icinga2 server to indicate host/service states or passive check updates.

By default the service will POST a `process-check-result` to your Icinga2 server with the following payload;

```
payload  = {
    'service'       : 'host-name!service-name',
    'check_source'  : 'check-source',
    'exit_status'   : priority,
    'plugin_output' : message
    }
```

Where the `host-name`, `service-name` and `check-source` come from the service config (see below), the priority is the standard `mqttwarn` priority, either hard coded or derived via a _function_, and the message is the payload arriving on the MQTT topic.

NOTE: if `service-name` is None in the target config the payload will include `'host' : 'host-name'` instead of the `'service'` entry, and can be used for host checks.

However it is possible to create your own payload by adding a custom format function where you can specify a dict of key/value pairs and these will be used to update the payload sent to Icinga2.

For example we can add a custom function which returns;

```
def icinga2_format(data, srv):
    icinga2_payload = {
        'exit_status'  : 0,
        'plugin_output': "OK: my-service is publishing",
        'service'      : "host.com!my-service",
        }

    return json.dumps(icinga2_payload)
```

This allows you to manipulate the status, output and service name by parsing topic names and message payloads.

```ini
[config:icinga2]
host     = 'https://icingahost'
port     = 5665
username = 'api-username'
password = 'api-password'
cacert   = '<path-to-ca-cert>'
targets  = {
                        # host-name   service-name  check-source
    'host-check '    : [ 'host.com',  None,         'mqttwarn' ],
    'service-check ' : [ 'host.com',  'passive',    'mqttwarn' ],
    }
```

NOTE: `cacert` is optional but since `icinga2` is typically installed with a self-signed certificate specifying the `icinga2` ca-cert will stop a load of TLS certificate warnings when connecting to the REST API.

### `ifttt`

this service is for [ifttt maker applet](https://ifttt.com/maker_webhooks) to send the message as a payload in value1. For example, to get notifications on your mobile devices.

```ini
[config:ifttt]
targets = {
    'warnme'   : [ '<api key>', '<event webhook>' ]
  }
```

### `ionic`

This service is for [Ionic](http://ionicframework.com/). Ionic framework allows easy development of HTML5 hybrid mobile apps. This service can be used for pushing notifications to ionic hybrid apps (android, ios, ...). Please read following for more details on ionic:
[Ionic tutorial](http://ionicframework.com/getting-started/) and [Ionic push service](http://docs.ionic.io/docs/push-overview)

You will get Ionic appid and Ionic appsecret (private key) after registering with Ionic push service. And you will get device token(s) when app initiates push service interaction.

Using this service, *plain texts* can be sent to one or many ionic apps. And each app can in turn push to many devices. Following is the ini example:

```ini
[config:ionic]
targets = {
  'anyappalias' : [ '<ionic app id>', '<ionic app secret>', '<device token 1>', '<device token 2>', '<device token N>']
  }
```

![ionic](assets/ionic.png)

### `iothub`

This service is for [Microsoft Azure IoT Hub](https://azure.microsoft.com/en-us/services/iot-hub/).
The configuration requires a hostname for the IoT Hub, all other service configuration options are optional.
Each target defines which device to impersonate when sending the message.

```ini
[config:iothub]
hostname = '<name>.azure-devices.net'
# protocol = 'AMQP'/'MQTT'/'HTTP' # Optional, default is AMQP
# message_timeout = 10000 # Optional, default is not to expire
# timeout = 10 # Optional, for HTTP transport only
# minimum_polling_time = 9 # Optional, for HTTP transport only
targets = {
               # device id   # device key
    'test' : [ 'pi',         'uN...6w=' ]
  }
```

Note that the actual message delivery is done asynchronously, meaning that
successful processing is no guarantee for actual delivery. In the case of an
error occurring, an error message should eventually appear in the log.

Requires:
* [Microsoft Azure IoT device SDK for Python](https://github.com/Azure/azure-iot-sdks/tree/master/python/device)

### `influxdb`

This service provides a way for forwarding data to the time series database [InfluxDB](https://influxdata.com/) (v9+).

You will need to install an instance of InfluxDB (v9+) and create a new user. Then create a new database and give your user write permissions to that database.

You can then setup multiple *targets*, each of which is a different *measurement* in your InfluxDB database.

Each time a value is received for an InfluxDB target, the value is sent to the configured *measurement* with a *topic* tag matching the MQTT topic the data arrived on.

The topic name is normalised by replacing `/` with `_`. So a value arriving on `sensor/kitchen/temperature` would be published to InfluxDB with a tag of `topic=sensor_kitchen_temperature`.

This allows you to setup measurements with multiple time series streams, or have a separate measurement for each stream.

Following is an ini example, showing the various connection properties for the InfluxDB database, and some example target configs;

```ini
[config:influxdb]
host      = 'influxdbhost'
port      = 8086
username  = 'username'
password  = 'password'
database  = 'mqttwarn'
targets = {
                          # measurement
    'humidity'         : [ 'humidity' ],
    'temperature'      : [ 'temperature' ]
    }
```

### `instapush`

This service is for [Instapush](https://instapush.im), an app for
both IOS and Android, which provides free instant notifications.

You should first create an application and respective event following the [tutorial](https://instapush.im/home/start/).

Afterward you will find your Application ID and Application Secret in the "Basic Info" of your application.

Each _mqttwarn_ target corresponds to an event in your Instapush application.

The "trackers" in Instapush correspond to JSON values in the _mqttwarn_ `config:instapush` section or from the message payload. You can define as many trackers as you wish.

Consider the following event created in Instapush:

| Field          | Value                |
| -------------- | -------------------- |
| `Event title`  | alerts               |
| `Trackers`     | object, action       |
| `Push Message` | {object} just {action} |

To always send the same `object` and `action` tracker values, set them as constants in the event of the target:

```ini
[config:instapush]
appid = '12345abc123456'
appsecret = '1234567890abcd123456789abcdef123456789'
targets = {
             # event   # trackers
  'notify' : [ 'alerts', {"object":"door", "action":"opened/closed"}]
  }
```

![instapush](assets/instapush.png)

To send tracker values based on the message payload, leave out the tracker element of the target definition in the `config:instapush` section: If your target is a list with only 1 element, that element will be considered the "event" and the "trackers" will be taken from the mqtt payload, which must have all tracker fields present.

### `irccat`

The `irccat` target fires a message off to a listening [irccat](https://github.com/RJ/irccat/tree/master) which has a connection open on one or more IRC channels.

Each target has to be configured with the address, TCP port and channel name of the particular _irccat_ it should target.

```ini
[config:irccat]
targets = {
             # address     port   channel
   'chan1': [ '127.0.0.1', 12345, '#testchan1' ],
  }
```

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `priority`    |   O    | Colour: 0=black, 1=green, 2=red        |

The priority field can be used to indicate a message colour.

![irccat](assets/irccat.png)

### `linuxnotify`
The `linuxnotify` service is used to display notifications on a running desktop
environment (only tested with Gnome3).

```ini
[config:linuxnotify]
targets = {
    'warn' : [ 'Warning' ]
    }
```

![linuxnotify](assets/linuxnotify.png)

Requires:
* gobject-introspection Python bindings

### `log`

The `log` service allows us to use the logging system in use by _mqttwarn_
proper, i.e. messages directed at `log` will land in _mqttwarn_'s log file.

```ini
[config:log]
targets = {
    'info'   : [ 'info' ],
    'warn'   : [ 'warn' ],
    'crit'   : [ 'crit' ],
    'error'  : [ 'error' ]
  }
```

### `mattermost`

The `mattermost` service sends messages to a private [Mattermost](https://about.mattermost.com/) instance using _incoming Webhooks_.

Consider the following configuration:

* `hook_url` is the URL of the incoming Webhook
* `channel` is the name of the channel
* `username` (can be None)  specifies the user name as which mqttwarn will post if the Mattermost administrator has allowed override
* `icon_url` is the URL to an icon (can be None, and if not must be resolvable to Mattermost)

```ini
[config:mattermost]
targets = {
                 # hook_url, 	channel, 	username, 	icon_url
    'jpt'	: [ 'http://localhost:8065/hooks/s9x9x8xywjgw9x9x8xyqiujcyo',
    			'town-square',
			'mqttwarn-jpt',
			'http://192.168.1.130/~jpm/ninja.png' ],
    'vehicles'	: [ 'http://127.0.0.1:8065/hooks/a87x8we4wjgwfxmuh7j9x9x8xy',
    			'town-square',
			'owntracks',
			'http://example.org/owntracks.png' ],
  }

[osx/json]
targets = mattermost:jpt
format = I'll have a {fruit} if it costs {price}

[owntracks/+/+]
title = Owntracks position
targets = mattermost:vehicles
```

This will, with appropriate JSON paylods, produce the following posts in Mattermost.

![mattermost](assets/mattermost.png)

Note how this service attempts to format incoming JSON as a Markdown table.

### `mqtt`

The `mqtt` service fires off a publish on a topic, creating a new connection
to the configured broker for each message.

Consider the following configuration snippets:

```ini
[config:mqtt]
hostname =  'localhost'
port =  1883
qos =  0
retain =  False
username =  "jane"
password =  "secret"
targets = {
  'o1'    : [ 'out/food' ],
  'o2'    : [ 'out/fruit/{fruit}' ],
  'm2'	  : [ 'sometopic', 'specialmq.ini' ],
  }

[in/a1]
targets = mqtt:o1, mqtt:o2
format =  u'Since when does a {fruit} cost {price}?'
```

The `topicmap` specifies we should subscribe to `in/a1` and republish to two
MQTT targets. The second target (`mqtt:o2`) has a topic branch with a variable
in it which is to be interpolated (`{fruit}`).

These are the results for appropriate publishes:

```
$ mosquitto_pub -t 'in/a1' -m '{"fruit":"pineapple", "price": 131, "tst" : "1391779336"}'

in/a1 {"fruit":"pineapple", "price": 131, "tst" : "1391779336"}
out/food Since when does a pineapple cost 131?
out/fruit/pineapple Since when does a pineapple cost 131?


$ mosquitto_pub -t 'in/a1' -m 'temperature: 12'

in/a1 temperature: 12
out/food temperature: 12
out/fruit/{fruit} temperature: 12
```

In the first case, the JSON payload was decoded and the _fruit_ variable could be
interpolated into the topic name of the outgoing publish, whereas the latter shows
the outgoing topic branch without interpolated values, because they simply didn't
exist in the original incoming payload.

The optional second value in the topic map (`specialmq.ini` in the example above)
specifies the name of an INI-type file with parameters which override the basic
configuration of this service. Assume most of your MQTT targets go to `localhost`,
but you want one target to be configured to address a distinct MQTT broker. Create
an INI file with any name you desire and specify that as the optional second parameter:

```ini
[defaults]
hostname= 10.0.12.1
port= 1884
client_id = blub01
qos = 1
retain = False

[auth]
username = jjolie
password = seecret

[tls]
ca_certs = foobar.crt
;certfile = xxx.crt
;keyfile = xxx.key
tls_version = tlsv1
;ciphers = xxxxx xx
```

This shows the currently full configuration possible. Global values from the
`mqtt` service override those not specified here. Also, if you don't need
authentication (`auth`) or (`tls`) you may omit those sections. (The `defaults`
section must exist.)

### `mqttpub`

This service publishes a message to the broker _mqttwarn_ is connected to. (To
publish a message to a _different_ broker, see `mqtt`.)

Each target requires a topic name, the desired _qos_ and a _retain_ flag.

```ini
[config:mqttpub]
targets = {
                # topic            qos     retain
    'mout1'   : [ 'mout/1',         0,     False ],
    'special' : [ 'some/{device}',  0,     False ],
  }
```

If the outgoing topic name contains transformation strings (e.g. `out/some/{temp}`)
values are interpolated accordingly. Should this not be possible, e.g. because a
string isn't available in the _data_, the message is _not_ published.

### `mysql`

The MySQL plugin is one of the most complicated to set up. It requires the following configuration:

```ini
[config:mysql]
host  =  'localhost'
port  =  3306
user  =  'jane'
pass  =  'secret'
dbname  =  'test'
targets = {
          # tablename  #fallbackcolumn ('NOP' to disable)
 'm2'   : [ 'names',   'full'            ]
  }
```

Suppose we create the following table for the target specified above:

```
CREATE TABLE names (id INTEGER, name VARCHAR(25));
```

and publish this JSON payload:

```
mosquitto_pub -t my/2 -m '{ "name" : "Jane Jolie", "id" : 90, "number" : 17 }'
```

This will result in the two columns `id` and `name` being populated:

```mysql
+------+------------+
| id   | name       |
+------+------------+
|   90 | Jane Jolie |
+------+------------+
```

The target contains a so-called _fallback column_ into which _mqttwarn_ adds
the "rest of" the payload for all columns not targeted with JSON data unless that
is explicitly configured as `NOP` in the service in which case extra data is discarded.
I'll now add our fallback column to the schema:

```mysql
ALTER TABLE names ADD full TEXT;
```

Publishing the same payload again, will insert this row into the table:

```mysql
+------+------------+-----------------------------------------------------+
| id   | name       | full                                                |
+------+------------+-----------------------------------------------------+
|   90 | Jane Jolie | NULL                                                |
|   90 | Jane Jolie | { "name" : "Jane Jolie", "id" : 90, "number" : 17 } |
+------+------------+-----------------------------------------------------+
```

As you can imagine, if we add a `number` column to the table, it too will be
correctly populated with the value `17`.

The payload of messages which do not contain valid JSON will be coped verbatim
to the _fallback_ column:

```mysql
+------+------+-------------+--------+
| id   | name | full        | number |
+------+------+-------------+--------+
| NULL | NULL | I love MQTT |   NULL |
+------+------+-------------+--------+
```

You can add columns with the names of the built-in transformation types (e.g. `_dthhmmss`, see below)
to have those values stored automatically.

### `mysql_dynamic`

Similar to the MySQL plugin but tables and columns are created dynamically as needed. The name of the table is composed from the topic, replacing the dash separator with underscores. As an example, the topic ```device/laptop/tracks```results in the creation of a table named ```device_laptop_tracks```.

The message will be processed and each JSON field will be stored in a different column. The columns of each table (and the table itself) are created when the first message is published to the topic. The configuration allows to specify the fields to ignore. These will not be stored in the database.

As an example, by publishing this JSON payload:
```
mosquitto_pub -t my/2 -m '{ "name" : "Jane Jolie", "id" : 90, "number" : 17 }'
```

A table named ```my_2``` will be created on the fly with the following structure and content (the table name is derived from the MQTT topic, but slashes are replaced by underscores):

```mysql
+------+------------+--------+-------------------------------------------------------+
| id   | name       | number | payload                                               |
+------+------------+--------+-------------------------------------------------------+
|   90 | Jane Jolie | 17     | '{ "name" : "Jane Jolie", "id" : 90, "number" : 17 }' |
+------+------------+--------+-------------------------------------------------------+
```
Please note that by default, the information is always stored in a duplicated form: each field, and all fields together as sent. If you can use the field ignore capability (see below) to disable this behaviour. Actually, lots of other fields (created by mqttwarn) may be present. Adjust your configuration as required.

An index table, containing a timestamp and the name of the topic, will keep track of the latest update to the remaining tables. The name of the index table can be specified in the configuration, and must be created manually. The following statements create an index table named ```index_table_name``:

```
CREATE TABLE `index_table_name` (
  `topic` text NOT NULL,
  `ts` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY `topic` (`topic`(128))
);
```


This module requires the following configuration to be present in the configuration file:

```ini
[config:mysql_dynamic]
host  =  'localhost'
port  =  3306
user  =  'dbusername'
pass  =  'dbpassword'
dbname  =  'database'
index   =  'index_table_name'

targets = {
        # target to use: [ list of fields to ignore and not store ]
        'target_name' : ['field1', 'field2','field3' ]
    }
```

Requires:
* [MySQLDb](http://mysql-python.sourceforge.net/)

Limitations:

At this point, if the payload format changes, the tables are not modified and data may fail to be stored. Also, there is no fallback table or column like the case of the MySQL plugin.

### `mysql_remap`
This service was originally designed to transform and store [SonOff](https://www.itead.cc/sonoff-pow.html) telemetry messages into a MySQL database, where database doen't need to have columns with same name as values in the MQTT messages.

My new service (called mysql_remap) inserts new record into MySQL.
This is a generic service, however, I designed it to colelct telemetry data from my SonOff POW devices.
This service can add static values (like the source/meaning of the data; e.g. 'bojler_enabled') and can remap keys (e.g. current power consumption data comes as 'current' but stored in DB as 'value').

Example configuration:

In the below configuration 'test' is the name of the table, 'Time' is a key comes from the MQTT message what will be renamed to 'timestamp' when service insert the data intothe table. If a message key isn't named here it won't be inserted into the database even it is in the message.

'description' is a column name in the database table and 'heater_power' is a constant to make filtering possible later on by SQL querys. You can add zero or more from these.

```ini
[defaults]
hostname  = 'localhost'
port      = 1883
loglevel  = DEBUG

launch   = mysql_remap

#functions = 'funcs.py'

[config:mysql_remap]
host  =  'localhost'
port  =  3306
user  =  'root'
pass  =  '123'
dbname  =  'test'
targets = {
         't1'   : [ 'test',
                            {
                              'Time': 'timestamp',
                              'Power': 'value'
                            },
                            {
                              'description' : 'heater_power'
                            }
                  ]
         }

[tele/+/SENSOR]
targets = mysql_remap:t1
#alldata = powerBinFunc()
```

You can also do some further transformation on the message before insert it into the databse using by the two uncommented lines above and the below function (need to copy it into funcs.py).

This below example convert reveived data and time information itno unix timestam format and replace "ON" and "OFF" values to 1 and 0 numbers.

```
# -*- coding: utf-8 -*-
import time
import copy
import ast
from datetime import datetime

def powerBinFunc(topic, data, srv=None):
    # parse json payload (the message)
    payload = ast.literal_eval(data["payload"])

    # Override default time format
    dt = datetime.strptime(payload["Time"], '%Y-%m-%dT%H:%M:%S')
    ts = time.mktime(dt.timetuple())
    ret = dict( payload = dict( Time = ts ))

    # Check power state key
    if "POWER" in payload:
        if payload["POWER"] == "ON":
            ret["POWER_BIN"] = 1
        else:
            ret["POWER_BIN"] = 0

    return ret

# vim: tabstop=4 expandtab
```


Example MQTT message:

```
17:08:45 MQT: tele/bojler/SENSOR = {"Time":"2018-04-15T17:08:45","ENERGY":{"Total":320.144,"Yesterday":5.105,"Today":1.881,"Period":0,"Power":17.15,"Factor":0.07,"Voltage":234,"Current":0.128}}
```

Example MySQL records:

```
+------------+-----------+----------------+
| timestamp  | value     | description    |
+------------+-----------+----------------+
| 1523804925 |  17.15000 | heater_power   |
+------------+-----------+----------------+
```

### `mythtv`

This service allows for on-screen notification pop-ups on [MythTV](http://www.mythtv.org/) instances. Each target requires
the address and port of the MythTV backend instance (&lt;hostname&gt;:&lt;port&gt;), and a broadcast address.

```ini
[config:mythtv]
timeout = 10  # duration of notification
targets = {
                          # host:port,            broadcast address
    'all'               :  [ '192.168.1.40:6544', '192.168.1.255'],
    'frontend_bedroom'  :  [ '192.168.1.40:6544', '192.168.1.74' ]
    }
```

| Topic option  |  M/O   | Description                           |
| ------------- | :----: | --------------------------------------|
| `title`       |   O    | notification title (dflt: `mqttwarn`) |
| `image`       |   O    | notification image URL                |


### `nma`

The `nma` service uses [NMA (Notify My Android)](http://www.notifymyandroid.com)
to delivery notifications from _mqttwarn_ to your Android device.

```ini
[config:nma]
targets = {
                 # api key                                            app         event
  'myapp'    : [ 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', "Nagios",  "Phone call" ]
  }
```

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `priority`    |   O    | priority. (dflt: 0)                    |

![NMA](assets/nma.jpg)

Requires:

* A [Notify My Android(NMA)](http://www.notifymyandroid.com) account
* [pynma](https://github.com/uskr/pynma). You don't have to install this -- just copy `pynma.py` to the _mqttwarn_ directory.

### `nntp`

The `nntp` target is used to post articles to an NNTP news server on a particular newsgroup.

```ini
[config:nntp]
server  = t1.prox
port    = 119
; username = "jane@example.com"
; password = "secret"
targets = {
    #              from_hdr                       newsgroup
    'aa'     : [ 'Me and I <jj@example.com>',    'jp.aa' ],
  }
```

Each target's configuration includes the value given to the `From:` header as well as
a single newsgroup to which the article is posted.

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `title`       |   O    | The post's subject (dflt: `mqttwarn`)  |

Example:

```
mosquitto_pub -t nn/ohoh -m '{"name":"Jane Jolie","number":47, "id":91}'
```

turns into

```
Path: t1.prox!t1.prox!not-for-mail
Content-Type: text/plain; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
From: Me and I <jj@example.com>
Subject: Hi there Jane Jolie
Newsgroups: jp.aa
Date: Wed, 26 Mar 2014 22:41:25 -0000
User-Agent: mqttwarn
Lines: 1
Message-ID: <5332caf6$0$20197$41d98655@t1.prox>

Jane Jolie: 47 => 13:41

```

### `nsca`

The `nsca` target is used to submit passive Nagios/Icinga checks to an NSCA daemon.

Consider the following Icinga service description which configures a passive service:

```
define service{
        use                    generic-service
        host_name              localhost
        service_description    Current temp via MQTT
        active_checks_enabled  0
        passive_checks_enabled 1
        check_freshness         0
        check_command          check_dummy!1
        }
```

with the following target definition in `mqttwarn.py`

```ini
[config:nsca]
nsca_host = '172.16.153.112'
targets = {
   #              Nagios host_name,     Nagios service_description,
   'temp'    :  [ 'localhost',          'Current temp via MQTT' ],
  }

[arduino/temp]
targets = nsca:temp
; OK = 0, WARNING = 1, CRITICAL = 2, UNKNOWN = 3
priority = check_temperature()
format = Current temperature: {temp}C
```

Also, consider the following PUB via MQTT:

```
mosquitto_pub -t arduino/temp -m '{"temp": 20}'
```

Using a transformation function for _priority_ to decide on the status to
be sent to Nagios/Icinga, we obtain the following:

![Icinga](assets/icinga.jpg)


| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `priority`    |   O    | Nagios/Icinga status. (dflt: 0)        |

The transformation function I've defined as follows:

```python
def check_temperature(data):
    '''Calculate Nagios/Icinga warning status'''
    OK = 0
    WARNING = 1
    CRITICAL = 2
    UNKNOWN = 3
    if type(data) == dict:
        if 'temp' in data:
            temp = int(data['temp'])
            if temp < 20:
                return OK
            if temp < 25:
                return WARNING
            return CRITICAL

    return UNKNOWN
```

Requires:
* [pynsca](https://github.com/djmitche/pynsca), but you don't have to install that; it suffices if you drop `pynsca.py` alongside `mqttwarn.py` (i.e. in the same directory)

### `osxnotify`

* Requires Mac ;-) and [pync](https://github.com/setem/pync) which uses the binary [terminal-notifier](https://github.com/alloy/terminal-notifier) created by Eloy Durán. Note: upon first launch, `pync` will download and extract `https://github.com/downloads/alloy/terminal-notifier/terminal-notifier_1.6.1.zip` into a directory `vendor/`.

| Topic option  |  M/O   | Description                                     |
| ------------- | :----: | ----------------------------------------------- |
| `title`       |   O    | application title (dflt: topic name)            |

If `url` is defined in `items.data`, its value is passed to the notification, so that the URL is opened in the system's default Web browser when the notification is clicked. (The notification itself has no visual indication that such is possible.)

![osxnotify](assets/osxnotify.jpg)

### `osxsay`

The `osxsay` target alerts you on your Mac (warning: requires a Mac :-) with a spoken voice.
It pipes the message (which is hopefully text only) to the _say(1)_ utility. You can configure
any number of different targets, each with a different voice (See `say -v ?` for a list of allowed
voice names.)

```ini
[config:osxsay]
targets = {
                 # voice (see say(1) or `say -v ?`)
    'victoria' : [ 'Victoria' ],
    'alex'     : [ 'Alex' ],
  }
```

```ini
[say/warn]
targets = osxsay:victoria
```


```ini
[say/alert]
targets = osxsay:alex
```

* Note: this requires your speakers be enabled and can be a pain for co-workers or family members, and we can't show you a screen shot...

### `pastebinpub`

The `pastebinpub` service is publishing messages to [Pastebin](http://pastebin.com).

Note: Be careful what you post on this target, it could be public. If you are
not a paying customer of Pastebin you are limited to 25 unlisted and
10 private pastes.

```ini
[config:pastebinpub]
targets = {
    'warn' : [ 'api_dev_key',  # API dev key
               'username',  # Username
               'password',  # Password
                1,  # Privacy level
               '1H'  # Expire
            ]
    }
```

![pastebin](assets/pastebin.png)

Requires:
* An account at [Pastebin](http://pastebin.com)
* Python bindings for the [Pastebin API](https://github.com/Morrolan/PastebinAPI)
  You don't have to install this -- simply copy `pastebin.py` to the _mqttwarn_ directory.
  `curl -O https://raw.githubusercontent.com/Morrolan/PastebinAPI/master/pastebin.py`

### `pipe`

The `pipe` target launches the specified program and its arguments and pipes the
(possibly formatted) message to the program's _stdin_. If the message doesn't have
a trailing newline (`\n`), _mqttwarn_ appends one.

```ini
[config:pipe]
targets = {
             # argv0 .....
   'wc'    : [ 'wc',   '-l' ]
   }
```

Note, that for each message targeted to the `pipe` service, a new process is
spawned (fork/exec), so it is quite "expensive".

### `postgres`

The `postgres` plugin behaves virtually identically to the [MySQL](#mysql) plugin above. It is configured in the same way:

```ini
[config:postgres]
host  =  'localhost'
port  =  5432
user  =  'jane'
pass  =  'secret'
dbname  =  'test'
targets = {
          # tablename  # fallbackcolumn  # schema
 'pg'   : [ 'names',   'message',	 'schema' ]
  }
```

Suppose we create the following table for the target specified above:

```
CREATE TABLE names (id INTEGER, name CHARACTER VARYING(128));
```

and publish this JSON payload:

```
mosquitto_pub -t pg/1 -m '{ "name" : "Jane Jolie", "id" : 90, "number" : 17 }'
```

This will result in the two columns `id` and `name` being populated:

```postgres
+------+------------+
| id   | name       |
+------+------------+
|   90 | Jane Jolie |
+------+------------+
```

Exactly as in the `MySQL` plugin, a _fallback column_ can be defined into which _mqttwarn_ adds
the "rest of" the payload for all columns not targeted with JSON data. Lets now
add our fallback column to the schema:

```postgres
ALTER TABLE names ADD message TEXT;
```

Publishing the same payload again, will insert this row into the table:

```postgres
+------+------------+-----------------------------------------------------+
| id   | name       | message                                             |
+------+------------+-----------------------------------------------------+
|   90 | Jane Jolie | NULL                                                |
|   90 | Jane Jolie | { "name" : "Jane Jolie", "id" : 90, "number" : 17 } |
+------+------------+-----------------------------------------------------+
```

As you can imagine, if we add a `number` column to the table, it too will be
correctly populated with the value `17`.

The payload of messages which do not contain valid JSON will be coped verbatim
to the _fallback_ column:

```postgres
+------+------+-------------+--------+
| id   | name | message     | number |
+------+------+-------------+--------+
| NULL | NULL | I love MQTT |   NULL |
+------+------+-------------+--------+
```

You can add columns with the names of the built-in transformation types (e.g. `_dthhmmss`, see below)
to have those values stored automatically.

### `prowl`

This service is for [Prowl](http://www.prowlapp.com). Each target requires
an application key and an application name.

```ini
[config:prowl]
targets = {
                    # application key                           # app name
    'pjpm'    :  [ 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', 'SuperAPP' ]
    }
```

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `title`       |   O    | application title (dflt: `mqttwarn`)   |
| `priority`    |   O    | priority. (dflt: 0)                    |


![Prowl](assets/prowl.jpg)

Requires:
* [prowlpy](https://github.com/jacobb/prowlpy)

### `pushalot`
This service is for [pushalot](http://www.pushalot.com), which is a notifier app for Windows Phone and Windows8.

It requires an Authorization token, which you can generate after creating an account at [pushalot.com](http://www.pushalot.com) We can then use that to configure the target definition:

```ini
[config:pushalot]
targets = {
                   # Authorization token
    'info'     : ['xxxxxxxxxxxxxxxxxxxxxxx'],
    'warn'     : ['xxxxxxxxxxxxxxxxxxxxxxx']
    }
````

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `title`       |   O    | application title (dflt: `mqttwarn`)   |

![Pushalot](assets/pushalot.png)

Requires:
* a [pushalot](http://www.pushalot.com) account with Authorization token


### `pushbullet`

This service is for [PushBullet](https://www.pushbullet.com), an app for
Android along with an extension for Chrome, which allows notes, links,
pictures, addresses and files to be sent between devices.

You can get your API key from [here](https://www.pushbullet.com/account) after
signing up for a PushBullet account. You will also need the device ID to push
the notifications to. To obtain this you need  to follow the instructions at
[pyPushBullet](https://github.com/Azelphur/pyPushBullet) and run
``./pushbullet_cmd.py YOUR_API_KEY_HERE getdevices``.

```ini
[config:pushbullet]
targets = {
                   # API KEY                  device ID,    recipient_type
    'warnme'   : [ 'xxxxxxxxxxxxxxxxxxxxxxx', 'yyyyyy',     'tttt' ]
    }
```

where the optional _recipient_type_ could be one of `device_iden` (default), `email`, `channel` or `client`.

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `title`       |   O    | application title (dflt: `mqttwarn`)   |

![Pushbullet](assets/pushbullet.jpg)

Requires:
* a [Pushbullet](https://www.pushbullet.com) account with API key
* [pyPushBullet](https://github.com/Azelphur/pyPushBullet). You don't have to install this -- simply copy `pushbullet.py` to the _mqttwarn_ directory.

### `pushover`

This service is for [Pushover](https://pushover.net), an app for iOS and Android.
In order to receive pushover notifications you need what is called a _user key_
and one or more _application keys_ which you configure in the targets definition:

```ini
[config:pushover]
callback = None
targets = {
    'nagios'     : ['userkey1', 'appkey1', 'sound1'],
    'alerts'     : ['userkey2', 'appkey2'],
    'tracking'   : ['userkey1', 'appkey2', 'sound3'],
    'extraphone' : ['userkey2', 'appkey3']
    }
```

This defines four targets (`nagios`, `alerts`, etc.) which are directed to the
configured _user key_ and _app key_ combinations. This in turn enables you to
notify, say, one or more of your devices as well as one for your spouse. As you
can see in the example, you can even specify an optional sound to be played for
the individual users. For a list of available sounds see the [Pushover API List](https://pushover.net/api#sounds).

NOTE: `callback` is an optional URL for pushover to [ack messages](https://pushover.net/api#receipt).

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `title`       |   O    | application title (dflt: pushover dflt) |
| `priority`    |   O    | priority. (dflt: pushover setting)     |

The pushover service will accept a payload with either a simple text message, or a json payload which contains
a `message` and either an `imageurl` or `imagebase64` encoded image.

The following payloads are valid;

```
Simple text message
```

```json
{
    "message": "Message only, with no image"
}
```

```json
 {
    "message": "Message with base64 encoded image",
    "imagebase64": "<base64 encoded image>"
 }
```

```json
 {
    "message": "Message with image downloaded from URL",
    "imageurl": "<image url>"
 }
```

![pushover on iOS](assets/pushover.png)

Requires:
* a [pushover.net](https://pushover.net/) account

### `pushsafer`

This service is for [Pushsafer](https://www.pushsafer.com), an app for iOS, Android and Windows 10.
In order to receive pushsafer notifications you need what is called a _private or alias key_:

```ini
[config:pushsafer]
targets = {
    'nagios'     : ['privatekey', 'Device ID', 'Icon', 'Sound', 'Vibration', 'URL', 'Url Title', 'Time2Live'],
    'tracking'   : ['aliaskey1'],
    'extraphone' : ['aliaskey2', '', '', '', '', '', '', '60'],
	'warnme'     : ['aliaskey3', '', '', '', '', '', '', '60']
    }
```

This defines targets (`nagios`, `alerts`, etc.) which are directed to the
configured _private or alias key_ combinations. This in turn enables you to
notify, say, one or more of your devices as well as one for your spouse.
For a list of available icons, sounds and other params see the
[Pushsafer API](https://www.pushsafer.com/en/pushapi).

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `title`       |   O    | application title (dflt: pushsafer dflt) |

![pushsafer on iOS](assets/pushsafer.jpg)

Requires:
* a [pushsafer.com](https://www.pushsafer.com/) account

### `redispub`

The `redispub` plugin publishes to a Redis channel.

```ini
[config:redispub]
host  =  'localhost'
port  =  6379
targets = {
    'r1'      : [ 'channel-1' ]
    }
```

Requires:
* d[redis-py](https://github.com/andymccurdy/redis-py)

### `rrdtool`

The `rrdtool` plugin updates a round robin database created by [rrdtool](http://oss.oetiker.ch/rrdtool/) with the message payload.

```ini
[config:rrdtool]
targets = {
    'living-temp'  : ['/tmp/living-temp.rrd',  '--template', 'temp'],
    'kitchen-temp' : ['/tmp/kitchen-temp.rrd', '--template', 'temp']
    }
```

[rrdpython's API](http://oss.oetiker.ch/rrdtool/prog/rrdpython.en.html) expects strings and/or list of strings as parameters to the functions. Thus a list for a target simply contains the command line arguments for `rrdtool update`. The plugin will embed the message as final argument `N:<message>`, if the message is an integer number. Otherwise, it will break up the message into single words and append this list to the list supplied by the target. This leaves it to your descretion _where_ to put arguments and even - with the right data mapping and extraction in place - allows for something like

```ini
[config:rrdtool]
targets = {
        'battsensor': [ ],
        }
...
[datalog-battery-log]
topic = datalog/sensors/batt/+
targets = log:info,rrdtool:battsensor
datamap = ...
format = /srv/rrd/sensors/{sensor_id}.rrd -t batt {ts}:{batt}
```

Requires the rrdtool bindings available with `pip install rrdtool`.

### `serial`

The `serial` plugin sends out received messages to the serial port. Message payload can be binary data, string or json.

```ini
[config:serial]
append_newline = False
targets = {
    'serialport1'  : ['/dev/ttyUSB0',  '115200'],
    'some-device' : ['socket://192.168.1.100:2323', '9600']
    }
```
First parameter in target config can be a portname or an [url handler](https://pythonhosted.org/pyserial/url_handlers.html).
Second parameter is the baudrate for the port.
If `append_newline` is True, a newline character is unconditionally appended to the string written to the serialport.

Requires the pyserial bindings available with `pip install pyserial`.

### `slack`

The `slack` plugin posts messages to channels in or users of the [slack.com](http://slack.com) service. The configuration of this service requires an API token obtaininable there.

```ini
[config:slack]
token = 'xxxx-1234567890-1234567890-1234567890-1234a1'
targets = {
                #   [token,] #channel/@user, username, icon, [as_user]
   'jpmens'     : [ '@jpmens',   "Alerter",   ':door:'          ],
   'general'    : [ '#general',  "mqttwarn",  ':syringe:'       ],
   'test'       : [ '#test',     "BotUser",   ':unused:',  True ],
   'second-acc' : [ 'xxxx-9999999-9999999-99999999', '#general', "test", ':house:' ],
  }
```

The service level `token` is optional, but if missing each target must have a `token` defined.

Each target defines the name of an existing channel (`#channelname`) or a user (`@username`) to be
addressed, the name of the sending user as well as an [emoji icon](http://www.emoji-cheat-sheet.com) to use.

Optionally, a target can define the message to get posted as a user, per
[Slack Authorship documentation](https://api.slack.com/methods/chat.postMessage#authorship).
Note that posting as a user in a channel is only possible, if the user has
joined the channel.

![Slack](assets/slack.png)

This plugin requires [Python slacker](https://github.com/os/slacker).

### `sqlite`

The `sqlite` plugin creates a table in the database file specified in the targets,
and creates a schema with a single column called `payload` of type `TEXT`. _mqttwarn_
commits messages routed to such a target immediately.

```ini
[config:sqlite]
targets = {
                   #path        #tablename
  'demotable' : [ '/tmp/m.db',  'mqttwarn'  ]
  }
```

### `sqlite_json2cols`

The `sqlite_json2cols` plugin creates a table in the database file specified in the targets
and creates a schema based on the JSON payload.
It will create a column for each JSON entry and rudimentary try to determine its datatype on creation (Float or Char).

As an example, publishing this JSON payload:

```
mosquitto_pub -t test/hello -m '{ "name" : "Thor", "Father" : 'Odin', "Age" : 30 }'
```

A table as stated in the configuration will be created on the fly with the following structure and content:

```
+------+--------+------+
| name | Father | Age  |
+------+--------+------+
| Thor | Odin   | 30.0 |
+------+--------+------+
```
No table is created if the table name already exists.

 _mqttwarn_
commits messages routed to such a target immediately.

```ini
[config:sqlite_json2cols]
targets = {
                   #path        #tablename
  'demotable' : [ '/tmp/m.db',  'mqttwarn'  ]
  }
```

### `sqlite_timestamp`

The `sqlite_timestamp` plugin works just like the 'sqlite' plugin, but it creates 3 columns: id, payload and timestamp.
The id is the table index and the timestamp is the insertion date and time in seconds.

```ini
[config:sqlite_timestamp]
targets = {
                   #path        #tablename
  'demotable' : [ '/tmp/m.db',  'mqttwarn'  ]
  }
```

### `smtp`

The `smtp` service basically implements an MQTT to SMTP gateway which needs
configuration.

```ini
[config:smtp]
server  =  'localhost:25'
sender  =  "MQTTwarn <jpm@localhost>"
username  =  None
password  =  None
starttls  =  False
# Optional send msg as html or only plain text
htmlmsg   =  False
targets = {
    'localj'     : [ 'jpm@localhost' ],
    'special'    : [ 'ben@gmail', 'suzie@example.net' ]
    }
```

Targets may contain more than one recipient, in which case all specified
recipients get the message.

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `title`       |   O    | e-mail subject. (dflt: `mqttwarn notification`) |

### `ssh`

The `ssh` service can run commands over ssh.
If both user and password are defined in the config, they will be used to connect to the host.
If both user and password are *not* defined in the config, the service will parse the user's
ssh config file to see which key (IdentityFile) to use; it will also look for User and Port
in this file.

If using a key, only the host is *required*.

The output is ignored for now.

Note: using this module lets you specify a username and a password which can be used to login to the target system. As such, your `mqttwarn.ini` configuration file should be well protected from prying eyes! (This applies generally, for other target specifications with credentials as well.)

```ini
[config:ssh]
host  = '192.168.1.1'
port  = 22
user  = 'username'
pass  = 'password'
targets = {
		's01'    : [ 'command with one substitution %s' ],
		's02'    : [ 'command with two substitutions %s__%s' ]
    }

[ssh/+]
format = {args}
targets = ssh:s01

[dualssh/+]
format = {args}
targets = ssh:s02
```

Targets may contain ONE command.

`mosquitto_pub -t dualssh/test -m '{ "args" : ["test","test2"] }'`


### `syslog`

The `syslog` service transfers MQTT messages to a local syslog server.

```ini
[config:syslog]
targets = {
              # facility    option
    'user'   : ['user',     'pid'],
    'kernel' : ['kernel',   'pid']
    }
```

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `title`       |   O    | application title (dflt: `mqttwarn`)   |
| `priority`    |   O    | log level (dflt: -1)                   |

Where `priority` can be between -2 and 5 and maps to `syslog` levels by;

| Priority | Syslog Log Level |
| -------- | ---------------- |
| -2       | LOG_DEBUG        |
| -1       | LOG_INFO         |
| 0        | LOG_NOTICE       |
| 1        | LOG_WARNING      |
| 2        | LOG_ERR          |
| 3        | LOG_CRIT         |
| 4        | LOG_ALERT        |
| 5        | LOG_EMERG        |

```
Apr 22 12:42:42 mqttest019 mqttwarn[9484]: Disk utilization: 94%
```

### `telegram`

This is to send messages as a Bot to a [Telegram](https://telegram.org) chat. First set up a Bot and obtain its authentication token which you add to _mqttwarn_'s configuration. You'll also need to start a chat with this bot so it's able to communicate with particular user.

Optionally you can specify `parse_mode` which will be used during message sending. Please, check [docs](https://core.telegram.org/bots/api#formatting-options) for additional information.

If you have the `chatId` you can specify the telegram service to use the chatId directly. Warning, this will need to be the case for all the targets in this notifier!

Quickest way to get the `chatid` is by visiting this URL (insert your api key): https://api.telegram.org/botYOUR_API_TOKEN/getUpdates and getting the id from the "from" section.

Configure the `telegram` service WITHOUT chatId:

```ini
[config:telegram]
timeout = 60
parse_mode = 'Markdown'
token = 'mmmmmmmmm:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
targets = {
   #        First Name or @username or #chat_id
   'j01' : [ 'First Name' ],
   'j02' : [ '@username' ],
   'j03' : [ '#chat_id' ]
}
```
Configure the `telegram` service WITH chatid:
```ini
[config:telegram]
timeout = 60
parse_mode = 'Markdown'
token = 'mmmmmmmmm:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
use_chat_id = True
targets = {
    #       chatId (in quotes)
    'j01' : ['123456789']
}
```

Possible issue:

* If First name or @username was specified as target, plugin will call [getUpdates](https://core.telegram.org/bots/api#getupdates) to get `chat_id` but this call returns only last 100 messages; if _you_ haven't spoken to your Bot recently it may well be possible we can't find the _chat-id_ associated with _you_. If chat_id is known, it can be set as target using `#` sign.

![Telegram](assets/telegram.png)

### `thingspeak`

The `thingspeak` service publishes data to thingspeak.com using the thingspeak API.

```ini
[config:thingspeak]
targets = {
                   #API WRITE KEY       field      optional builddata=true/false
    'field1'   : [ 'XXYYZZXXYYZZXXYY', 'field1' , 'true' ],
    'field2'   : [ 'XXYYZZXXYYZZXXYY', 'field2' ],
    'composite': [ 'XXYYZZXXYYZZXXYY', [ 'temp', 'hum' ] ]
  }
```
Using `builddata=true` you can build an update with multiple fields in one update. Using this function no direct update is performed. Only with the next update without builddata=true all entries are sent (e.g. when multiple sensors are updating different topics, then you can do the build the data and submit when the last sensor is sending the data).

Supply an ordered list of message data field names to extract several values from a single message (e.g. `{ "temp": 10, "hum": 77 }`). Values will be assigned to field1, field2, etc in order.

Note: Use the field as per the example (lower case, `'field1'` with the last digit being the field number).

### `tootpaste`

The `tootpaste` service is for posting to the [Mastodon social network](https://mastodon.social/about).

```ini
[config:tootpaste]
targets = {
             # clientcreds, usercreds, base_url
    'uno'  : [ 'a.client',  'a.user', 'https://masto.io' ],
  }
```

The specified `clientcreds` and `usercreds` are paths to files created with the service, as follows:

```
python services/tootpaste.py 'https://masto.io' 'jane@example.org' 'xafa5280890' warnme su03-a.client su03-a.user
```

The arguments, in order:

1. base URL (e.g. `https://mastodon.social`)
2. your e-mail address
3. the password corresponding to the e-mail address
4. the client name (name of the posting program)
5. the clientcreds file
6. the usercreds file.

The two last files are created and should be protected from prying eyes.

![tootpaste (Mastodon)](assets/tootpaste.png)

`tootpaste` requires a `pip install Mastodon.py` ([Mastodon.py](https://github.com/halcy/Mastodon.py)).

### `twilio`

```ini
[config:twilio]
targets = {
             # Account SID            Auth Token            from              to
   'hola'  : [ 'ACXXXXXXXXXXXXXXXXX', 'YYYYYYYYYYYYYYYYYY', "+15105551234",  "+12125551234" ]
   }
```

![Twilio test](assets/twillio.jpg)

Requires:
 * a Twilio account
 * [twilio-python](https://github.com/twilio/twilio-python)

### `twitter`

Notification of one or more [Twitter](http://twitter.com) accounts requires setting
up an application at [apps.twitter.com](https://apps.twitter.com). For each Twitter
account, you need four (4) bits which are named as shown below.

Upon configuring this service's targets, make sure the four (4) elements of the
list are in the order specified!

```ini
[config:twitter]
targets = {
  'janejol'   :  [ 'vvvvvvvvvvvvvvvvvvvvvv',                              # consumer_key
                   'wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww',          # consumer_secret
                   'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',  # access_token_key
                   'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'           # access_token_secret
                  ]
   }
```

![a tweet](assets/twitter.jpg)

Requires:
* A Twitter account
* app keys for Twitter, from [apps.twitter.com](https://apps.twitter.com)
* [python-twitter](https://github.com/bear/python-twitter)

### `websocket`

The websocket service can be used to send data to a websocket server defined by its uri. `ws://` or `wss://` schemas
are supported.

```ini
[config:websocket]
targets = {
        # targetid        : [ 'wsuri']
        'wssserver' : [ 'ws://localhost/ws' ],
} 
```

Requires:
* [websocket-client](https://pypi.python.org/pypi/websocket-client/) - pip install websocket-client

### `xbmc`

This service allows for on-screen notification pop-ups on [XBMC](http://xbmc.org/) instances. Each target requires
the address and port of the XBMC instance (<hostname>:<port>), and an optional username and password if authentication is required.

```ini
[config:xbmc]
targets = {
                          # host:port,           [user], [password]
    'living_with_auth' :  [ '192.168.1.40:8080', 'xbmc', 'xbmc' ],
    'bedroom_no_auth'  :  [ '192.168.1.41:8080' ]
    }
```

| Topic option  |  M/O   | Description                            |
| ------------- | :----: | -------------------------------------- |
| `title`       |   O    | notification title                     |
| `image`       |   O    | notification image URL  ([example](https://github.com/jpmens/mqttwarn/issues/53#issuecomment-39691429))|

### `xmpp`

The `xmpp` service sends notification to one or more [XMPP](http://en.wikipedia.org/wiki/XMPP)
(Jabber) recipients.

```ini
[config:xmpp]
sender = 'mqttwarn@jabber.server'
password = 'Password for sender'
targets = {
    'admin' : [ 'admin1@jabber.server', 'admin2@jabber.server' ]
    }
```

Targets may contain more than one recipient, in which case all specified
recipients get the message.

Requires:
* XMPP (Jabber) accounts (at least one for the sender and one for the recipient)
* [xmpppy](http://xmpppy.sourceforge.net)

### `xively`

The `xively` service can send a subset of your data to [Xively](http://xively.com) per defined feedid.

```ini
[config:xively]
apikey = '1234567890abcdefghiklmnopqrstuvwxyz'
targets = {
        # feedid        : [ 'datastream1', 'datastream2']
        '1234567' : [ 'temperature', 'waterlevel' ],
        '7654321' : [ 'dataItemA' ]
  }
```

Publishing the following JSON message will add a datapoint to the `temperature` and
`waterlevel` channel of your xively feed 1234567 (`humidity` will be ignored,
as it's not defined in the xively
configuration above):

```
mosquitto_pub -t "osx/json" -m '{"temperature":15,"waterlevel":100,"humidity":35}'
```


Requires:
* [Xively](http://xively.com) account with an already existing Feed
* [xively-python](https://github.com/xively/xively-python) - pip install xively-python

### `zabbix`

The `zabbix` service serves two purposes:

1. it can create a [Zabbix] host on-the-fly via Low-level Discovery (LLD)
2. it can send an item/value pair to a [Zabbix] trapper

![Zabbix](assets/zabbix.png)

To create an appropriate discovery host, in Zabbix:
- Configuration->Hosts->Create host (`mqttwarn01`)
- Configuration->Discovery->Create discovery rule
  - Name: `MQTTwarn` (any suitable name)
  - Type: `Zabbix trapper`
  - Key: `mqtt.discovery` (this must match the configured `discovery_key`, which defaults to `mqtt.discovery`)
  - Allowed hosts: `192.168.1.130,127.0.0.1` (example)

The target and topic configuration look like this:

```ini
[config:zabbix]
host = "mqttwarn01"  # an existing host configured in Zabbix
discovery_key = "mqtt.discovery"
targets = {
            # Trapper address   port
    't1'  : [ '172.16.153.110', 10051 ],
  }

[zabbix/clients/+]
alldata = ZabbixData()
targets = zabbix:t1

[zabbix/item/#]
alldata = ZabbixData()
targets = zabbix:t1
```

A transformation function in `alldata` is required to extract the client's name
from the topic, and for #1, to define a "host alive" item key in [Zabbix].

```python
# If the topic begins with zabbix/clients we have a host going up or down
# e.g. "zabbix/clients/jog03" -> "jog03"
#   extract client name (3rd part of topic)
#   set status key (e.g. 'host.up') to publish 1/0 on it (e.g during LWT)
#
# if the topic starts with zabbix/item we have an item/value for the host
# e.g. "zabbix/item/jog03/time.stamp" -> "jog03"
#   extract client name (3rd part of topic)
#

def ZabbixData(topic, data, srv=None):
    client = 'unknown'
    key = None
    status_key = None

    parts = topic.split('/')

    ''' What we call 'client' is in fact a "Zabbix Host", i.e. the name of a
        host configured with items; it it not the name/address of the machine on
        which Zabbix server runs. So, in the UI: Configuration -> Create host '''

    client = parts[2]

    if topic.startswith('zabbix/clients/'):
        status_key = 'host.up'

    ''' This "key" is actually an LLD item which we've pre-created in the Zabbix
        UI. Configuration->Hosts->Discovery->Item prototypes->Create item prototype
	   Name: MW client $1
	   Type: Zabbix trapper
	   Key: mqttwarn.id[{#MQTTHOST}]
	   Type: text (can be any suitable type)

	Publishing a value with
	$ mosquitto_pub -t zabbix/item/mqttwarn01/mqttwarn.id[m02] -m 'stormy'
	will mean that we'll use the client "mqttwarn01" (see previously) and
	the item named "mqttwarn.id[m02]" which is the name of a previously
	discovered item.
    '''

    if topic.startswith('zabbix/item/'):
        key = parts[3]

    return dict(client=client, key=key, status_key=status_key)
```

### Creating Custom Service Plugins

Creating new plugins is rather easy, and I recommend you take the `file` plugin
and start from that.

Plugins are invoked with two arguments (`srv` and `item`). `srv` is an object
with some helper functions, and `item` a dict which contains information on the message
which is to be handled by the plugin. `item` contains the following elements:

```python
item = {
    'service'       : 'string',       # name of handling service (`twitter`, `file`, ..)
    'target'        : 'string',       # name of target (`o1`, `janejol`) in service
    'addrs'         : <list>,         # list of addresses from SERVICE_targets
    'config'        : dict,           # None or dict from SERVICE_config {}
    'topic'         : 'string',       # incoming topic branch name
    'payload'       : <payload>       # raw message payload
    'message'       : 'string',       # formatted message (if no format string then = payload)
    'data'          : None,           # dict with transformation data
    'title'         : 'mqttwarn',     # possible title from title{}
    'priority'      : 0,              # possible priority from priority{}
}
```

## Transformation

In addition to passing the payload received via MQTT to a service, _mqttwarn_ allows you do do the following:

* Transform payloads on a per/topic basis. For example, you know you'll be receiving JSON, but you want to warn with a nicely formatted message.
* For certain services, you can change the _title_ (or _subject_) of the outgoing message.
* For certain services, you can change the _priority_ of the outgoing message.

Consider the following JSON payload published to the MQTT broker:

```shell
mosquitto_pub -t 'osx/json' -m '{"fruit":"banana", "price": 63, "tst" : "1391779336"}'
```

Using `format` we can configure _mqttwarn_ to transform that JSON into a different outgoing message which is the text that is actually notified. Part of said `format` looks like this in the configuration file, and basically specifies that messages published to `osx/json` should be transformed as on the right-hand side.

```ini
format = "I'll have a {fruit} if it costs {price}"
```

(Embedded `"\n"` are converted to newlines on output.)

The result is:

![OSX notifier](assets/osxnotify.jpg)

You associate MQTT topic branches to applications in the configuration file (copy `mqttwarn.ini.sample` to `mqttwarn.ini` for use). In other words, you can accomplish, say, following mappings:

* PUBs to `owntracks/jane/iphone` should be notified via Pushover to John's phone
* PUBs to `openhab/temperature` should be Tweeted
* PUBs to `home/monitoring/alert/+` should notify Twitter, Mail, and Prowl

See details in the config sample for how to configure this script.
The path to the configuration file (which must be valid Python) is obtained from the `MQTTWARNINI` environment variable which defaults to `mqttwarn.ini` in the current directory.



## Advanced features

### JSON output serialization

When receiving JSON data like `{"data": {"humidity": 62.18}}`, you might
want to extract values using the `format` mechanism before forwarding
it to other data sinks, like

```ini
format = "{data}"
```

However, the outcome will be the string-serialized form of the Python
representation: `{u'humidity': 62.18}`, which could not be what you
want if your data sink is expecting JSON format again.

To achieve this, you should use appropriate type coercion before
formatting, like

```ini
format = "{data!j}"
```

This will serialize the formatted data to JSON format appropriately,
so the outcome will be `{"humidity": 62.18}`.


### Transformation data

_mqttwarn_ can transform an incoming message before passing it to a plugin service.
On each message, _mqttwarn_ attempts to decode the incoming payload from JSON. If
this is possible, a dict with _transformation data_ is made available to the
service plugins as `item.data`.

This transformation data is initially set up with some built-in values, in addition
to those decoded from the incoming JSON payload. The following built-in variables
are defined in `item.data`:

```python
{
  'topic'         : topic name
  'payload'       : topic payload
  '_dtepoch'      : epoch time                  # 1392628581
  '_dtiso'        : ISO date (UTC)              # 2014-02-17T10:38:43.910691Z
  '_dthhmm'       : timestamp HH:MM (local)     # 10:16
  '_dthhmmss'     : timestamp HH:MM:SS (local)  # 10:16:21
}
```

Any of these values can be used in `format` to create custom outgoing
messages.

```ini
format = I'll have a {fruit} if it costs {price} at {_dthhmm}
```


### Using functions to replace incoming payloads

Consider the following configuration snippet in addition to the configuration
of the `mqtt` service shown above:

```python
def lookup_data(data, srv=None):
    if type(data) == dict and 'fruit' in data:
            return "Ananas"
    return None
```

Then, in the section defining the topic we listen on:

```ini
...
[test/topic]
#format =  Since when does a {fruit} cost {price}?
format =  lookup_data()
```

We've replaced the `formatmap` entry for the topic by a function which you
define within the _functions_ file you configure as `functions` in `mqttwarn.ini` configuration file. These functions
are invoked with decoded JSON `data` passed to them as a _dict_. The string returned
by the function returned string replaces the outgoing `message`:

```
in/a1 {"fruit":"pineapple", "price": 131, "tst" : "1391779336"}
out/food Ananas
out/fruit/pineapple Ananas
```

If a function operating on a message (i.e. within `format =`) returns `None` or an empty string, the target notification is suppressed.

The optional `srv` is an object with some helper functions. In particular, these allow us to use _mqttwarn_'s logging and MQTT publish functions, as in this example:

```python
def p01Format(data, srv):
    s = "p01-HOLA"

    srv.logging.info("+++++++++++ HUHU")

    srv.mqttc.publish("p01/RESPonse", s, qos=0, retain=False)

    return s
```

Be advised that if you MQTT publish back to the same topic which triggered the invocation
of your function, you'll create an endless loop.

### Incorporating topic names into transformation data

An MQTT topic branch name contains information you may want to use in transformations.
As a rather extreme example, consider the [OwnTracks] program (the
artist formerly known as _MQTTitude_).

When an [OwnTracks] device detects a change of a configured waypoint or geo-fence (a region monitoring a user can set up on the device), it emits a JSON payload which looks like this, on a topic name consisting of `owntracks/_username_/_deviceid_`:

```
owntracks/jane/phone -m '{"_type": "location", "lat": "52.4770352" ..  "desc": "Home", "event": "leave"}'
```

In order to be able to obtain the username (`jane`) and her device name (`phone`) for use
in transformations (see previous section), we would ideally want to parse the MQTT topic name and add that to the item data our plugins obtain. Yes, we can.

An optional `datamap` in our configuration file defines the name of a function we provide, also in the configuration file, which accomplishes that.

```ini
[owntracks/jane/phone]
datamap = OwnTracksTopicDataMap()
```

This specifies that when a message for the defined topic `owntracks/jane/phone` is processed, our function `OwnTracksTopicDataMap()` should be invoked to parse that. (As usual, topic names may contain MQTT wildcards.)

The function we define to do that is:

```python
def OwnTracksTopicDataMap(topic):
    if type(topic) == str:
        try:
            # owntracks/username/device
            parts = topic.split('/')
            username = parts[1]
            deviceid = parts[2]
        except:
            deviceid = 'unknown'
            username = 'unknown'
        return dict(username=username, device=deviceid)
    return None
```

The returned _dict_ is merged into the transformation data, i.e. it is made available to plugins and to transformation rules (`format`). If we then create the following rule

```ini
format = {username}: {event} => {desc}
```

the above PUBlish will be transformed into

```
jane: leave => Home
```

### Merging more data ###

The optional `alldata` function you write and configure on a per/topic basis, is
passed the message _topic_, its _data_ and an optional _srv_ object. This function
should return a _dict_ (or _None_) of data which is merged into the whole
list of transformation data. This expands on the two other transformation functions
to make topic and the message's payload available simultaneously.


### Accessing Nested JSON Nodes ###

Within templates and formats, you can refer only to the top-level names of an incoming JSON message,
which significantly limits the kinds of messages `mqttwarn` can process. A [solution is in the works](https://github.com/jpmens/mqttwarn/issues/303)
for this, but in the meantime you can use an `alldata` function to transform the JSON into something 
`mqttwarn` _can_ process.

The trick is to build a new JSON message with _only_ top-level values, specifically the values you need.
 
For example, say we are receiving messages from a temperature sensor 
running [Tasmota](https://github.com/arendst/Sonoff-Tasmota/),
and we wish to convert them into [InfluxDB line format](https://docs.influxdata.com/influxdb/v1.6/write_protocols/line_protocol_tutorial/).

The incoming [JSON](https://github.com/arendst/Sonoff-Tasmota/wiki/JSON-Status-Responses#ds18b20) will look like this:
```
{
    "Time": "2018.02.01 21:29:40",
    "DS18B20": {
      "Temperature": 19.7
    },
    "TempUnit": "C"
},
```

Since `Temperature` cannot be referenced directly within a `format`, we need to make it a top-level value. 
While we're at it, we can change the date to milliseconds since the epoch, and include the topic:
```
{
    "Topic": "tasmota/temp/ds/1", 
    "Timestamp": 1517525319000, 
    "Temperature": 19.7
}
```

This can be accomplished with the following function: 
```
import ast
import logging
import time
from datetime import datetime

def ds18b20_values(topic, data, srv=None):
    payload = ast.literal_eval(data["payload"])
    ts = datetime.strptime(payload["Time"], "%Y.%m.%d %H:%M:%S")
    millis = long(time.mktime(ts.timetuple()) * 1000)
    temp = payload["DS18B20"]["Temperature"]
    d = dict( Topic = topic, Timestamp = millis, Temperature = temp )
    logging.debug(d)
    return d
```

Apply it to a topic in `mqttwarn.ini`:
```
[tasmota/temp/ds/+]
targets = log:info
alldata = ds18b20_values()
format  = weather,Topic={Topic} Temperature={Temperature} {Timestamp}
```

Which results in:
```
2018-07-19 22:00:24,452 DEBUG [mqttwarn] Message received on tasmota/temp/ds/1: { "Time": "2018.02.01 22:48:39", "DS18B20": { "Temperature": 19.7 }, "TempUnit": "C" }
2018-07-19 22:00:24,453 DEBUG [mqttwarn] Section [tasmota/temp/ds/+] matches message on tasmota/temp/ds/1. Processing...
2018-07-19 22:00:24,457 DEBUG [funcs] {'Topic': u'tasmota/temp/ds/1', 'Timestamp': 1517525319000L, 'Temperature': 19.7}
2018-07-19 22:00:24,459 DEBUG [mqttwarn] Message on tasmota/temp/ds/1 going to log:info
2018-07-19 22:00:24,459 DEBUG [mqttwarn] New `log:info' job: tasmota/temp/ds/1
2018-07-19 22:00:24,459 DEBUG [mqttwarn] Processor #0 is handling: `log' for info
2018-07-19 22:00:24,460 DEBUG [log] *** MODULE=services/log.pyc: service=log, target=info
2018-07-19 22:00:24,460 INFO  [log] weather,Topic=tasmota/temp/ds/1 Temperature=19.7 1517525319000
```




### Using transformation data in other contexts ###

Beside using the transformation data dictionary in `format` to create custom outgoing messages,
it can be used in other contexts as well. Let's have a look at different ways this can be
used throughout _mqttwarn_.

#### Topic targets ####

By incorporating transformation data into topic targets, we can make _mqttwarn_ dispatch
messages dynamically based on the values of the transformation data dictionary.

To get an idea about how this works, let's define a placeholder variable inside the
`targets` directive of a topic section in the `mqttwarn.ini` configuration file:

    [topic-targets-dynamic]
    topic   = test/topic-targets-dynamic
    format  = Something {loglevel} happened! {message}
    targets = log:{loglevel}

When sending this value through a JSON encoded message or by computing it
through the `datamap` or `alldata` transformation machinery, it will get
interpolated into the designated topic target. Example:

    mosquitto_pub -t test/topic-targets-dynamic -m '{"loglevel": "crit", "message": "Nur Döner macht schöner!"}'

This will issue the following message into the log file:

    2016-02-14 18:09:34,822 CRITICAL [log] Something crit happened! Nur Döner macht schöner!

While this little example might feel artificial, there are more meaningful
use cases like determining the recipient address of `smtp` or `xmpp` receivers
through information from topic names or message payloads.
Please have a look at [Incorporate topic names into topic targets](https://github.com/jpmens/mqttwarn/wiki/Incorporating-topic-names#incorporate-topic-names-into-topic-targets)
for a more sensible example.


### Filtering notifications ###

A notification can be filtered (or suppressed) using a custom function.

An optional `filter` in our configuration file, defines the name of a function we provide. The function is provided in another file, as specified by the functions directive in the configuration file.

```ini
filter = owntracks_filter()
```

This specifies that when a message for the defined topic `owntracks/jane/phone` is processed, our function `owntracks_filter()` should be invoked to parse that. The filter function should return `True` if the message should be suppressed, or `False` if the message should be processed. (As usual, topic names may contain MQTT wildcards.)

The function we define to do that is:

```python
def owntracks_filter(topic, message):
    return message.find('event') == -1
```

This filter will suppress any messages that do not contain the `event` token.  This filter goes in the file specified by the functions directive.

### Templates ###

Instead of formatting output with the `format` specification as described above,
_mqttwarn_ has provision for rendering the output message from [Jinja2] templates,
probably particularly interesting for the `smtp` or `nntp` and `file` targets.

Consider the following example topic configuration, where we illustrate using
a template instead of `format` (which is commented out).

```ini
[nn/+]
targets = nntp:jpaa
; format = {name}: {number} => {_dthhmm}
template = demo.j2
```

_mqttwarn_ loads Jinja2 templates from the `templates/` directory relative to the
configured `directory`. Assuming we have the following content in the file
`templates/demo.j2`

```jinja2
{#
    this is a comment
    in Jinja2
    See http://jinja.pocoo.org/docs/templates/ for information
    on Jinja2 templates.
#}
{% set upname = name | upper %}
{% set width = 60 %}
{% for n in range(0, width) %}-{% endfor %}

Name.................: {{ upname }}
Number...............: {{ number }}
Timestamp............: {{ _dthhmm }}
Original payload.....: {{ payload }}
```

could produce the following message, on any target which uses this configuration.

```
------------------------------------------------------------
Name.................: JANE JOLIE
Number...............: 47
Timestamp............: 19:15
Original payload.....: {"name":"Jane Jolie","number":47, "id":91}
```

One of the template variables you may be interested in is called `{{ payload }}`; this
carries the original MQTT message in it. Also, if the payload was JSON, those are
available also (as shown in the above example), together with all the other
transformation data.

If the template cannot be rendered, say, it contains a Jinja2 error or the template
file cannot be found, etc., the original raw message is used in lieu on output.

As mentioned already, we think this is useful for targets which expect a certain
amount of text (`file`, `smtp`, and `nntp` come to mind).

Use of this feature requires [Jinja2], but you don't have to install it if you don't need
templating.

### Periodic tasks ###

_mqttwarn_ can use functions you define in the file specified `[defaults]` section
to periodically do whatever you want, for example, publish an MQTT message. There
are two things you have to do:

1. Create the function
2. Configure _mqttwarn_ to use that function and specify the interval in seconds

Assume we have the following custom function defined:

```python
def pinger(srv=None):
    srv.mqttc.publish("pt/PINGER", "Hello from mqttwarn!", qos=0)
```

We configure this function to run every, say, 10 seconds, in the `mqttwarn.ini`,
in the `[cron]` section:

```ini
[cron]
pinger = 10.5
```

Each keyword in the `[cron]` section specifies the name of one of your custom
functions, and its float value is an interval in _seconds_ after which your
custom function (_pinger()_ in this case) is invoked. Your function has access
to the `srv` object (which was described earlier).

Function names are to be specified in lower-case characters.

If you want to run the custom function immediately after starting mqttwarn
instead of waiting for the interval to elapse, you might want to configure:

```ini
[cron]
pinger = 10.5; now=true
```


## Running with Docker

If you would rather use `mqttwarn` without installing Python
and the required libraries, you can run it as a [Docker container](https://www.docker.com/).
You need to install only the Docker executable.

### Run the Image

You can run the image as a service, i.e. in the background, or you can 
run it interactively, perhaps to help diagnose a problem.

Note that you can run a local copy of the image, if you've built one (see below), 
by replacing `jpmens/mqttwarn` with `mqttwarn-local` in the following examples.

#### As a Service

This is the typical way of running `mqttwarn`.

From the folder containing your `mqttwarn.ini` file:

```
docker run -d --rm --name mqttwarn \
    -v $PWD:/opt/mqttwarn/conf \
    jpmens/mqttwarn
```

To stop the container:
```
docker stop mqttwarn
```

#### Interactively

If you want to experiment with your configuration, or to diagnose
a problem, it can be simpler to restart the Python script,
rather than to restart the Docker container.

From the folder containing your `mqttwarn.ini` file:

```
docker run -it --rm \
    -v $PWD:/opt/mqttwarn/conf \
    --entrypoint bash \
    jpmens/mqttwarn
```
 
To start the application: 
```
python mqttwarn.py
```

`Ctrl-C` will stop it. You can start and stop it as often as you like, here, probably editing the `.ini` file as you go.

`Ctrl-D` or `exit` will stop the container. 



#### Options

##### Configuration Location

You can of course run the Docker image from anywhere if you 
specify a full path to the configuration file:
```
     -v /full/path/to/folder:/opt/mqttwarn/conf
```

##### Functions
If you have one or more files of Python functions in the same folder
as your `.ini` file, then prefix
 the filenames in `.ini` file with a folder:
```
functions = 'functions/funcs.py'
```
Then add this argument to `docker run`:
```
    -v $PWD:/opt/mqttwarn/functions
```

##### Log file

By default the log file will be created inside the container.
If you would like instead log to a file on the host, add this to your
`mqttwarn.ini` file:
```
logfile = 'log/mqttwarn.log'
```
Add this argument to `docker run`
```
    -v $PWD:/opt/mqttwarn/log
```
`mqttwarn.log` will be created in your current folder,
and appended to
each time the container is executed. You can delete the file
between executions.


##### If your MQTT Broker is Also Running in Docker on the Same Host

If you give the MQTT broker container a name, then you can 
refer to it by name rather than by
IP address.  For instance, if it's named `mosquitto` 
 put this in your `mqttwarn.ini` file:
```
hostname  = 'mosquitto'
```
Then add this argument to `docker run`:
```
    --link mosquitto
```

##### A full example

If you have your `.ini` and Python files in your current directory,
this will run `mqttwarn` and place the log file in the current directory:
```
docker run -d --rm --name mqttwarn \
    -v $PWD:/opt/mqttwarn/conf \
    -v $PWD:/opt/mqttwarn/functions \
    -v $PWD:/opt/mqttwarn/log \
    --link mosquitto \
    jpmens/mqttwarn
```



### Build the image

If you are making any changes to the `mqttwarn` application or to
the `Dockerfile`, you can build a local image from the files on your drive
(not from the files on Github).

Execute the following from the root of the project :

```
docker build -t mqttwarn-local .
```

You can then edit any files and rebuild the image as many times as you need. 
You don't need to commit any changes.

The name `mqttwarn-local` is not meaningful, other than
making it obvious when you run it that you are using your
own personal image.  It will be renamed when it is published.

### Deploy the Image (Administrators Only)

Only do this when you have a clean checkout from `master`:
```
docker login
```

Set the version accordingly:
```
docker tag mqttwarn-local jpmens/mqttwarn:0.10.1
docker push jpmens/mqttwarn:0.10.1
```

If this is the latest version, tag it as such (which will untag
the previous latest version):
```
docker tag mqttwarn-local jpmens/mqttwarn:latest
docker push jpmens/mqttwarn:latest
```



## Examples ##

This section contains some examples of how `mqttwarn` can be used with some more complex configurations.

### Low battery notifications ###

By subscribing to your [OwnTracks] topic and adding the following custom filter you can get `mqttwarn` to send notifications when your phone battery gets below a certain level;

```python
def owntracks_battfilter(topic, message):
    data = dict(json.loads(message).items())
    if data['batt'] is not None:
        return int(data['batt']) > 20
    return True
```

Now simply add your choice of target(s) to the topic's section and a nice format string and you are done;

```ini
[owntracks/#]
targets = pushover, xbmc
filter = owntracks_battfilter()
format = My phone battery is getting low ({batt}%)!
```

### Producing JSON

Assuming we get, from an Arduino, say, a single numerical value in the payload of an MQTT
message, we want to generate JSON with some additional fields. Using a Jinja2 template
for the task, does exactly what we need:

The following target configuration invokes the template:

```ini
[arduino/temp]
targets = log:info, http:graylog2
template = temp2json.json
```

The Jinja2 template looks like this:

```jinja2
{#
    We expect a single numeric temperature value in `payload'
    Return JSON suitable for Graylog2 (requires host and short_message)

    Define a data structure in Jinja2 and return it as a JSON string.
    Note how transformation data (produced within mqttwarn) is used:
    the variables `_dtiso' and `payload' contain a timestamp and our
    payload respectively.
#}
{% set data = {
	'host'		: topic,
	'short_message'	: "Heat " + payload,
	'tst'		: _dtiso,
	'temperature'	: payload,
	'woohooo'	: 17,
	}
	%}
{{ data | jsonify }}
```

and an example JSON string returned by that template is then passed to our configured
targets thusly:

```json
"host": "arduino/temp", "woohooo": 17, "tst": "2014-04-13T09:25:46.247150Z", "temperature": "22", "short_message": "Heat 22"}
```



## Notes

"MQTT" is a trademark of the OASIS open standards consortium, which publishes the MQTT specifications.



## Press

* [MQTTwarn: Ein Rundum-Sorglos-Notifier](http://jaxenter.de/news/MQTTwarn-Ein-Rundum-Sorglos-Notifier-171312), article in German at JAXenter.
* [Schwarmalarm using mqttwarn](https://hiveeyes.org/docs/system/schwarmalarm-mqttwarn.html)

  [OwnTracks]: http://owntracks.org
  [Jinja2]: http://jinja.pocoo.org/docs/templates/
  [Zabbix]: http://zabbix.com
