local _M = {}


local http  = require "resty.http"
local cjson = require "cjson.safe"


local ngx_DEBUG = ngx.DEBUG
local ngx_ERR   = ngx.ERR
local ngx_WARN  = ngx.WARN


local co_status    = coroutine.status
local ipairs       = ipairs
local insert       = table.insert
local ngx_log      = ngx.log
local pairs        = pairs
local pcall        = pcall
local remove       = table.remove
local setmetatable = setmetatable
local spawn        = ngx.thread.spawn
local tostring     = tostring
local wait         = ngx.thread.wait


local EVENTS_ENDPOINT = "/v1/event/list"
local INDEX_HEADER = "X-Consul-Index"


_M.version = "0.1"
_M.user_agent = "lua-resty-consul-events/" .. _M.version ..
                "(Lua) ngx_lua/" .. ngx.config.ngx_lua_version


local mt = { __index = _M }


local function copy(o)
  local t = {}

  for k, v in pairs(o) do
    t[k] = v
  end

  return t
end


local function watch_event(ctx)
  local httpc = http.new()

  -- set the tcp timeout higher than the consul timeout
  httpc:set_timeout((ctx.timeout * 1000) * 2)

  local scheme = ctx.use_tls and "https" or "http"

  local path = scheme .. "://" .. ctx.host .. ":" ..
               tostring(ctx.port) .. EVENTS_ENDPOINT

  local res, err = httpc:request_uri(path, {
    query = {
      index = ctx.index,
      name  = ctx.name,
      wait  = ctx.timeout .. "s",
    },
    headers = {
      ["User-Agent"] = _M.user_agent,
    },
    ssl_verify = ctx.ssl_verify,
  })

  if err then
    return { "watch", false, err }
  end

  if res.status ~= 200 then
    return { "watch", false, res.body }
  end

  -- check that the index has changed- if it hasn"t,
  -- return an empty events table
  if res.headers[INDEX_HEADER] == ctx.index then
    ngx_log(ngx_DEBUG, "returned identical index")
    return { "watch", true, {} }
  end

  -- new event(s). consul's interface isn't great here
  -- we have no way to know which events returned we have
  -- already processed, so we need to walk each event and
  -- confirm that the ltime is newer than the most recent
  -- event we've seen
  local events, err = cjson.decode(res.body)
  if not events then
    return { "watch", false, err }
  end

  local new_events = {}

  for _, event in ipairs(events) do
    if not ctx.ltime_lru:get(event.LTime) then
      ctx.ltime_lru:set(event.LTime, true)

      insert(new_events, event)
    end
  end

  ctx.index = res.headers[INDEX_HEADER]

  return { "watch", true, new_events }
end


local function fire_callback(ctx, event)
  local ok, err = pcall(ctx.callback, event)

  return { "event", ok, err }
end


-- spawns a thread to listen for events
-- when a response is received, respawn the listen thread,
-- and spawn threads for each event callback
function _M:watch(name, callback, initial_index, seen_ltime)
  local t = {} -- threads table

  local ctx    = copy(self)
  ctx.name     = name
  ctx.callback = callback

  if initial_index then
    ctx.index = initial_index
  end

  if seen_ltime then
    for i = 1, #seen_ltime do
      ctx.ltime_lru:set(seen_ltime[i], true)
    end
  end

  -- bootstrap the first event watch thread
  insert(t, spawn(watch_event, ctx))

  while true do
    -- wait on our threads. if we got back a watch event,
    -- spawn the necessary callbacks and a new watch thread
    -- otherwise, we just wait again

    -- res is expected to be an array containing 3 values:
    -- 1. a string indicating the type of thread executed
    -- 2. a boolean indicating the function response status
    -- 3. a table containing context-specific return data
    --      in the case of "watch" return types, this value
    --      is a table containing the event details, if any.
    --      for "event" return types, this value is the return
    --      of the callback function. because callback functions
    --      are wrapped in pcall(), this value may either be the
    --      function return or a bubbled error
    local ok, res = wait(unpack(t))

    if not ok then
      ngx_log(ngx_ERR, res)
    end

    for i, co in ipairs(t) do
      if co_status(co) == "dead" then
        remove(t, i)
      end
    end

    if res[1] == "watch" then
      if not res[2] then
        ngx_log(ngx_ERR, "error in fetching events: ", res[3])

      else
        for _, event in ipairs(res[3]) do
          insert(t, spawn(fire_callback, ctx, event))
        end
      end

      -- after firing any potential callbacks, re-spawn a
      -- thread to watch for new events
      insert(t, spawn(watch_event, ctx))

    elseif res[1] == "event" then
      ngx_log(ngx_DEBUG, "callback returned ", tostring(res[3]))

    else
      ngx_log(ngx_WARN, "invalid thread return type ", tostring(res[1]))
    end
  end
end


function _M.new(opts)
  if not opts then
    opts = {}
  end

  if type(opts) ~= "table" then
    return false, "opts must be a table"
  end

  opts.host       = opts.host or "127.0.0.1"
  opts.port       = opts.port or 8500
  opts.timeout    = opts.timeout or 60
  opts.ssl_verify = opts.ssl or false

  if type(opts.host) ~= "string" then
    return false, "invalid host"
  end
  if type(opts.port) ~= "number" or opts.port < 0 or opts.port > 65535 then
    return false, "invalid port"
  end
  if type(opts.timeout) ~= "number" or opts.timeout < 0 then
    return false, "invalid timeout"
  end
  if type(opts.ssl_verify) ~= "boolean" then
    return false, "invalid ssl"
  end

  local lrucache = require "resty.lrucache"
  local lru, err = lrucache.new(256)
  if err then
    return false, err
  end

  return setmetatable({
    host       = opts.host,
    port       = opts.port,
    timeout    = opts.timeout,
    ssl_verify = opts.ssl_verify,

    -- index = nil,
    ltime_lru = lru,
  }, mt)
end

return _M
