local event = require "event"

local e, err = event.new({
  host = "127.0.0.1",
  port = 8500,
  timeout = 3,
})
if not e then error(err) end

e:watch(
  "foo",
  function(event)
    ngx.sleep(4)
    ngx.log(ngx.NOTICE, "i got " .. require("cjson").encode(event))
    return "YEP YEP YEP"
  end
)
