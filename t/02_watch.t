use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

plan tests => 6 * blocks();


$ENV{TEST_NGINX_CONSUL_ADDR} |= "127.0.0.1";
$ENV{TEST_NGINX_CONSUL_PORT} |= 8500;

check_accum_error_log();

my $pwd = cwd();

our $HttpConfig = <<"_EOC_";
    lua_package_path "$pwd/lib/?.lua;/usr/local/share/lua/5.1/?.lua;;";

    lua_shared_dict hits 1m;

    init_by_lua_block {
      chost = "$ENV{TEST_NGINX_CONSUL_ADDR}"
      cport = $ENV{TEST_NGINX_CONSUL_PORT}
    }

    init_worker_by_lua_block {
      local event = require "resty.consul.event"

      local e, err = event.new({
        host = chost,
        port = cport,
      })
      if err then
        ngx.log(ngx.ERR, err)
      end

      ngx.timer.at(0, function()
        e:watch("foo", function() ngx.shared.hits:incr("foo", 1, 0) end )
      end)
      ngx.timer.at(0, function()
        e:watch("bar", function() ngx.shared.hits:incr("bar", 1, 0) end )
      end)
      ngx.timer.at(0, function()
        e:watch("error", function() error("whups") end )
      end)
    }
_EOC_

no_shuffle();
run_tests();

__DATA__

=== TEST 1: Catches a single event (1/2)
--- http_config eval: $::HttpConfig
--- config
location /s {
  content_by_lua_block {
    local h = require("resty.http").new()

    local res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/fire/foo", {
      method = "PUT",
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    ngx.print("ok")
  }
}
location /t {
  content_by_lua_block {
    ngx.sleep(0.5)

    ngx.print(ngx.shared.hits:get("foo"))
  }
}
--- error_code eval
[200, 200]
--- request eval
["GET /s", "GET /t"]
--- response_body eval
["ok", 1]
--- no_error_log
[error]


=== TEST 2: Catches a single event (2/2)
--- http_config eval: $::HttpConfig
--- config
location /s {
  content_by_lua_block {
    local h = require("resty.http").new()

    local res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/fire/bar", {
      method = "PUT",
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    ngx.print("ok")
  }
}
location /t {
  content_by_lua_block {
    ngx.sleep(0.5)

    ngx.print(ngx.shared.hits:get("bar"))
  }
}
--- error_code eval
[200, 200]
--- request eval
["GET /s", "GET /t"]
--- response_body eval
["ok", 1]
--- no_error_log
[error]


=== TEST 3: Catches and swallows callback errors
--- http_config eval: $::HttpConfig
--- config
location /s {
  content_by_lua_block {
    local h = require("resty.http").new()

    local res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/fire/error", {
      method = "PUT",
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    ngx.print("ok")
  }
}
location /t {
  content_by_lua_block {
    ngx.sleep(0.5)

    ngx.print("ok")
  }
}
--- error_code eval
[200, 200]
--- request eval
["GET /s", "GET /t"]
--- response_body eval
["ok", "ok"]
--- no_error_log
[error]


=== TEST 4: Catches a new event under a previously broadcast name
--- http_config eval: $::HttpConfig
--- config
location /s {
  content_by_lua_block {
    local h = require("resty.http").new()

    local res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/fire/bar", {
      method = "PUT",
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    ngx.print("ok")
  }
}
location /t {
  content_by_lua_block {
    ngx.sleep(0.5)

    ngx.print(ngx.shared.hits:get("bar"))
  }
}
--- error_code eval
[200, 200]
--- request eval
["GET /s", "GET /t"]
--- response_body eval
["ok", 2]
--- no_error_log
[error]


=== TEST 5: Handles consul wait events appropriately
--- http_config eval: $::HttpConfig
--- config
location /s {
content_by_lua_block {
    local event = require "resty.consul.event"

    local e, err = event.new({
      host = chost,
      port = cport,
      timeout = 1,
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    ngx.timer.at(0, function()
      e:watch("foo", function() ngx.shared.hits:incr("foo", 1, 0) end )
    end)

    ngx.print("ok")
  }
}
location /t {
  content_by_lua_block {
    ngx.sleep(4)

    ngx.print("ok")
  }
}
--- error_code eval
[200, 200]
--- request eval
["GET /s", "GET /t"]
--- response_body eval
["ok", "ok"]
--- error_log
returned identical index
--- no_error_log
[error]
--- timeout: 5s
--- SKIP # error_log is only looking at the first request, triggering a false failure


=== TEST 6: Successfully executes a callback running longer than the watch timeout
--- http_config eval: $::HttpConfig
--- config
location /s {
  content_by_lua_block {
    local event = require "resty.consul.event"

    local e, err = event.new({
      host = chost,
      port = cport,
      timeout = 1,
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    ngx.timer.at(0, function()
      e:watch("delay", function() ngx.sleep(3); ngx.shared.hits:incr("delay", 1, 0) end )
    end)

    ngx.print("ok")
  }
}
location /t {
  content_by_lua_block {
    local h = require("resty.http").new()

    local res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/fire/delay", {
      method = "PUT",
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    ngx.sleep(5)

    ngx.print(ngx.shared.hits:get("delay"))
  }
}
--- timeout: 10s
--- error_code eval
[200, 200]
--- request eval
["GET /s", "GET /t"]
--- response_body eval
["ok", 1]
--- no_error_log
[error]


=== TEST 7: Does not execute callbacks for past events
--- http_config eval: $::HttpConfig
--- config
location /s {
  content_by_lua_block {
    local h = require("resty.http").new()

    local res, err

    for i = 1, 3 do
      res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
        "/v1/event/fire/baz", {
        method = "PUT",
      })
      if err then
        ngx.log(ngx.ERR, err)
      end
    end

    -- get the current events
    res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/list?name=baz")
    if err then
      ngx.log(ngx.ERR, err)
    end

    local event = require "resty.consul.event"

    local e, err = event.new({
      host = chost,
      port = cport,
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    local l = {}

    for _, e in ipairs(require("cjson").decode(res.body)) do
      table.insert(l, e.LTime)
    end

    ngx.timer.at(0, function()
      e:watch("baz", function() ngx.shared.hits:incr("baz", 1, 0) end,
        res.headers["X-Consul-Index"],
        l
      )
    end)

    res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/fire/baz", {
      method = "PUT",
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    ngx.print("ok")
  }
}
location /t {
  content_by_lua_block {
    ngx.sleep(0.5)

    ngx.print(ngx.shared.hits:get("baz"))
  }
}
--- timeout: 10s
--- error_code eval
[200, 200]
--- request eval
["GET /s", "GET /t"]
--- response_body eval
["ok", 1]
--- no_error_log
[error]


=== TEST 8: Does not execute callbacks for past events with no initial index
--- http_config eval: $::HttpConfig
--- config
location /s {
  content_by_lua_block {
    local h = require("resty.http").new()

    local res, err

    for i = 1, 3 do
      res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
        "/v1/event/fire/bat", {
        method = "PUT",
      })
      if err then
        ngx.log(ngx.ERR, err)
      end
    end

    -- get the current events
    res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/list?name=bat")
    if err then
      ngx.log(ngx.ERR, err)
    end

    local event = require "resty.consul.event"

    local e, err = event.new({
      host = chost,
      port = cport,
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    local l = {}

    for _, e in ipairs(require("cjson").decode(res.body)) do
      table.insert(l, e.LTime)
    end

    ngx.timer.at(0, function()
      e:watch("bat", function() ngx.shared.hits:incr("bat", 1, 0) end,
        nil,
        l
      )
    end)

    res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/fire/bat", {
      method = "PUT",
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    ngx.print("ok")
  }
}
location /t {
  content_by_lua_block {
    ngx.sleep(0.5)

    ngx.print(ngx.shared.hits:get("bat"))
  }
}
--- timeout: 10s
--- error_code eval
[200, 200]
--- request eval
["GET /s", "GET /t"]
--- response_body eval
["ok", 1]
--- no_error_log
[error]


=== TEST 9: Does execute callbacks for past events with initial index but no seen_ltime
--- http_config eval: $::HttpConfig
--- config
location /s {
  content_by_lua_block {
    local h = require("resty.http").new()

    local res, err

    for i = 1, 3 do
      res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
        "/v1/event/fire/qux", {
        method = "PUT",
      })
      if err then
        ngx.log(ngx.ERR, err)
      end
    end

    -- get the current events
    res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/list?name=qux")
    if err then
      ngx.log(ngx.ERR, err)
    end

    local event = require "resty.consul.event"

    local e, err = event.new({
      host = chost,
      port = cport,
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    local l = {}

    for _, e in ipairs(require("cjson").decode(res.body)) do
      table.insert(l, e.LTime)
    end

    ngx.timer.at(0, function()
      e:watch("qux", function() ngx.shared.hits:incr("qux", 1, 0) end,
        res.headers["X-Consul-Index"]
      )
    end)

    res, err = h:request_uri("http://" .. chost .. ":" .. cport ..
      "/v1/event/fire/qux", {
      method = "PUT",
    })
    if err then
      ngx.log(ngx.ERR, err)
    end

    ngx.print("ok")
  }
}
location /t {
  content_by_lua_block {
    ngx.sleep(0.5)

    ngx.print(ngx.shared.hits:get("qux"))
  }
}
--- timeout: 10s
--- error_code eval
[200, 200]
--- request eval
["GET /s", "GET /t"]
--- response_body eval
["ok", 4]
--- no_error_log
[error]
