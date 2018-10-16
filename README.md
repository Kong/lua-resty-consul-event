lua-resty-consul-events
=======================

Consul Events HTTP API Wrapper

# Table of Contents

* [Overview](#overview)
* [Dependencies](#dependencies)
* [Synopsis](#synopsis)
* [Usage](#usage)
  * [new](#new)
  * [watch](#watch)
* [License](#license)

# Overview

This module provides an OpenResty client wrapper for the [Consul Events API](https://www.consul.io/api/event.html). This allows for OpenResty integration with Consul's custom user event mechanism, which can be used to build scripting infrastructure to do automated deploys, restart services, or perform any other orchestration action.

This module leverages Consul's concept of [blocking queries](https://www.consul.io/api/index.html#blocking-queries) to watch for events broadcast on a given event name.

# Dependencies

 * [lua-resty-http](https://github.com/pintsized/lua-resty-http)

# Synopsis

```lua
local event = require "resty.consul.event"

local e, err = event.new({
  host = "127.0.0.1",
  port = 8500,
})

if err then
  ngx.log(ngx.ERR, err)
end

e:watch("foo", function(event)
  ngx.log(ngx.INFO, "i got ", ngx.decode_base64(event.payload))
end)
```

# Usage

## new

`syntax: e, err = event.new(opts?)`

Instantiates a new watch object. `opts` may be a table with the following options: 

 * `host`: String defining the Consul host
 * `port`: Number defining the Consul port
 * `timeout`: Number, in seconds, to pass to Consul blocking query API via the `wait` parameter. This value is also used to to define TCP layer timeouts, which are set higher than the application-layer timeout.
 * `ssl_verify`: Boolean defining whether to validate the TLS certificate presented by the remote Consul server.

## watch

`syntax: e:watch(name, callback)`

Watch the Consul events API for events broadcast under a given `name`, and execute the function `callback` . `callback` is passed a single parameter `event`, which contains the body of a single event as defined by the [Consul Events API](https://www.consul.io/api/event.html)

*Note: This body of this function runs in an infinite loop in order to watch the Consul events API indefinitely. As a result, it is strongly recommended to call this function inside a background timer generated via ngx.timer.at*

# License

Copyright 2018 Kong Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
