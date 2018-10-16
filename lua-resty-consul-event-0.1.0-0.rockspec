package = "lua-resty-consul-event"
version = "0.1.0-0"
source = {
  url = "git://github.com/kong/lua-resty-consul-event",
  tag = "0.1.0"
}
description = {
  summary  = "Consul Events HTTP API Wrapper for OpenResty",
  homepage = "https://github.com/kong/lua-resty-consul-event",
  license  = "Apache 2.0"
}
dependencies = {
  "lua-resty-http == 0.12"
}
build = {
  type    = "builtin",
  modules = {
    ["resty.consul.event"] = "lib/resty/consul/event.lua",
  }
}
