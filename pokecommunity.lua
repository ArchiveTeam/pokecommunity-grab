dofile("urlcode.lua")
dofile("table_show.lua")

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local ids = {}

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

start, end_ = string.match(item_value, "([0-9]+)-([0-9]+)")
for i=start, end_ do
  ids[i] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
     or string.match(url, "[<>\\]")
     or string.match(url, "//$")
     or string.match(url, "^https?://[^/]*facebook%.com")
     or string.match(url, "^https?://[^/]*twitter%.com") then
    return false
  end

  --if parenturl ~= nil and string.match(parenturl, "postcount=[0-9]+") then
  --  return false
  --end

  if string.match(url, "[^a-zA-Z0-9]goto=") or
     string.match(url, "[%?&]do=newreply") or
     string.match(url, "[%?&]do=addlist") or
     string.match(url, "[%?&]do=newpm") or
     string.match(url, "/report%.php") or
     string.match(url, "/sendmessage%.php") or
     string.match(url, "/subscription%.php") or
     string.match(url, "/search%.php") or
     string.match(url, "do=logout") or
     string.match(url, "%[/") then
     --string.match(url, "/showthread%.php%?p=[0-9]+") then
    return false
  end

  if item_type == "forums" then
    if string.match(url, "[%?&]order=asc") or
       string.match(url, "[%?&]sort=") then
      return false
    end
  end

  if (item_type == "threads" or item_type == "forums" or item_type == "members" or item_type == "attachments")
     and string.match(url, "^https?://[^/]*pokecommunity%.com") then
    for id in string.gmatch(url, "([0-9]+)") do
      if ids[tonumber(id)] == true then
        return true
      end
    end
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  --if string.match(url, "[%?&]s=[0-9a-f]+") then
  --  return false
  --end

  if string.match(url, "%[/") then
    return false
  end

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
     and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end

  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true
  
  local function check(urla)
    local origurl = url
    local url = string.gsub(string.match(urla, "^([^#]+)"), "&amp;", "&")
    --if string.match(url, "[%?&]s=[0-9a-f]+&") then
    --  url = string.gsub(url, "s=[0-9a-f]+&", "")
    --elseif string.match(url, "[%?&]s=[0-9a-f]+") then
    --  url = string.gsub(url, "%?s=[0-9a-f]+", "")
    --end
    if (downloaded[url] ~= true and addedtolist[url] ~= true)
       and allowed(url, origurl) then
      table.insert(urls, { url=url })
      addedtolist[origurl] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
       or string.match(newurl, "^[/\\]")
       or string.match(newurl, "^[jJ]ava[sS]cript:")
       or string.match(newurl, "^[mM]ail[tT]o:")
       or string.match(newurl, "^vine:")
       or string.match(newurl, "^android%-app:")
       or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end
  
  if allowed(url, nil) then
    html = read_file(file)

    if item_type == "threads" then
      for post in string.gmatch(html, 'id="postcount([0-9]+)"') do
        ids[tonumber(post)] = true
        check("http://pokecommunity.com/showthread.php?p=" .. post)
        check("http://pokecommunity.com/showpost.php?p=" .. post)
      end
    end

    --if string.match(url, "^https?://forums%.steampowered%.com/forums/showthread%.php%?t=[0-9]+") then
    --  check(string.gsub(url, "showthread", "announcement")
    --end

    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      check(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]

  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404) or
    status_code == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 20 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end