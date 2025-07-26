_G._OSVERSION = "Diskboot 0.2.1"

local cpt = component or require("component")
local computer = computer or require("computer")
local gpu = cpt.proxy(cpt.list("gpu")())

local function boot(d)
  local bootAddr = d.address
  computer.getBootAddress = function() return bootAddr end
  computer.setBootAddress = function(s) bootAddr = s end

  local data
  if d.type == "filesystem" then
    local f = d.open("/init.lua", "r")
    local size = d.size("/init.lua")
    data = d.read(f, size)
    d.close(f)
  elseif d.type == "drive" then
    error("Unmanaged Drive Support Not Yet Implemented.")
  end

  local init = load(data, "init")
  init()
  error("init returned")
end

-- Video Setup
if gpu then
  for a in cpt.list("screen") do
    if cpt.invoke(a, "getKeyboards") then
      gpu.bind(a)
      gpu.setResolution(50, 16)
      gpu.setBackground(0x0000FF)
      gpu.setForeground(0xFFFFFF)
      goto video_success
    else
      error("No Keyboard Connected!")
    end
  end
  error("Screen Not Found!")
else
  error("GPU Not Found!")
end
:: video_success ::

local function cls()
  gpu.fill(1, 1, 50, 16, " ")
end

local scr_y = 1
local function write(msg)
  gpu.set(1, scr_y, msg)
  scr_y = scr_y + 1
end

local function getkey()
  while true do
    local id, _, char, code = computer.pullSignal()
    if id == "key_down" then
      return string.char(char), code
    end
  end
end

cls()

-- Get Bootable disks
local disk = {}

for addr in pairs(cpt.list("filesystem")) do
  local d = cpt.proxy(addr)
  if d.type == "filesystem" then
    if d.exists("/init.lua") then
      table.insert(disk, d)
    end
  end
end

for addr in pairs(cpt.list("drive")) do
  local d = cpt.proxy(addr)
  if d.type == "drive" then
    table.insert(disk, d)
  end
end

-- Make Boot Menu
write(_OSVERSION)
for i, v in ipairs(disk) do
  write(string.format("%d: %s [%.5s]", i, v.getLabel() or "nil", v.address))
end

-- Boot Disk
local entry = tonumber(getkey())
boot(disk[entry])