use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

plan tests => 3 * blocks();

my $pwd = cwd();

our $HttpConfig = <<"_EOC_";
    lua_package_path "$pwd/lib/?.lua;/usr/local/share/lua/5.1/?.lua;;";
_EOC_

no_shuffle();
run_tests();

__DATA__

=== TEST 1: nil new
--- http_config eval: $::HttpConfig
--- config
location /t {
  content_by_lua_block {
    local e = require "resty.consul.event"

    local event, err = e.new()

    ngx.say(type(event) == "table")
    ngx.say(err)
  }
}
--- request
GET /t
--- error_code: 200
--- response_body
true
nil
--- no_error_log
[error]


=== TEST 2: empty tab new
--- http_config eval: $::HttpConfig
--- config
location /t {
  content_by_lua_block {
    local e = require "resty.consul.event"

    local event, err = e.new({})

    ngx.say(type(event) == "table")
    ngx.say(err)
  }
}
--- request
GET /t
--- error_code: 200
--- response_body
true
nil
--- no_error_log
[error]


=== TEST 3: new with a custom host
--- http_config eval: $::HttpConfig
--- config
location /t {
  content_by_lua_block {
    local e = require "resty.consul.event"

    local event, err = e.new({
      host = "consul",
    })

    ngx.say(type(event) == "table")
    ngx.say(err)
  }
}
--- request
GET /t
--- error_code: 200
--- response_body
true
nil
--- no_error_log
[error]


=== TEST 4: new with a custom port
--- http_config eval: $::HttpConfig
--- config
location /t {
  content_by_lua_block {
    local e = require "resty.consul.event"

    local event, err = e.new({
      port = 12355,
    })

    ngx.say(type(event) == "table")
    ngx.say(err)
  }
}
--- request
GET /t
--- error_code: 200
--- response_body
true
nil
--- no_error_log
[error]


=== TEST 5: new with custom timeout
--- http_config eval: $::HttpConfig
--- config
location /t {
  content_by_lua_block {
    local e = require "resty.consul.event"

    local event, err = e.new({
      timeout = 30,
    })

    ngx.say(type(event) == "table")
    ngx.say(err)
  }
}
--- request
GET /t
--- error_code: 200
--- response_body
true
nil
--- no_error_log
[error]


=== TEST 6: new with an invalid host
--- http_config eval: $::HttpConfig
--- config
location /t {
  content_by_lua_block {
    local e = require "resty.consul.event"

    local event, err = e.new({
      host = true,
    })

    ngx.say(type(event) == "table")
    ngx.say(err)
  }
}
--- request
GET /t
--- error_code: 200
--- response_body
false
invalid host
--- no_error_log
[error]


=== TEST 7: new with an invalid port
--- http_config eval: $::HttpConfig
--- config
location /t {
  content_by_lua_block {
    local e = require "resty.consul.event"

    local event, err = e.new({
      port = "nope",
    })

    ngx.say(type(event) == "table")
    ngx.say(err)
  }
}
--- request
GET /t
--- error_code: 200
--- response_body
false
invalid port
--- no_error_log
[error]


=== TEST 8: new with an invalid timeout type
--- http_config eval: $::HttpConfig
--- config
location /t {
  content_by_lua_block {
    local e = require "resty.consul.event"

    local event, err = e.new({
      timeout = "notathing",
    })

    ngx.say(type(event) == "table")
    ngx.say(err)
  }
}
--- request
GET /t
--- error_code: 200
--- response_body
false
invalid timeout
--- no_error_log
[error]


=== TEST 9: new with an invalid timeout value
--- http_config eval: $::HttpConfig
--- config
location /t {
  content_by_lua_block {
    local e = require "resty.consul.event"

    local event, err = e.new({
      timeout = -1
    })

    ngx.say(type(event) == "table")
    ngx.say(err)
  }
}
--- request
GET /t
--- error_code: 200
--- response_body
false
invalid timeout
--- no_error_log
[error]


=== TEST 10: new with an invalid token value
--- http_config eval: $::HttpConfig
--- config
location /t {
  content_by_lua_block {
    local e = require "resty.consul.event"

    local event, err = e.new({
      token = true
    })

    ngx.say(type(event) == "table")
    ngx.say(err)
  }
}
--- request
GET /t
--- error_code: 200
--- response_body
false
invalid token
--- no_error_log
[error]
