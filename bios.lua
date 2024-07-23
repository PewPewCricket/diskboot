_G._OSVERSION = "DiskBoot-dev-1"
local component = component or require('component')
local computer = computer or require('computer')
local unicode = unicode or require('unicode')
local disk = {}
local partition = {}
local bootcode = ""
local bootdisk, w, h

-- Initialize Components
for address, name in component.list() do
  local componentType = component.proxy(address).type
  if componentType == "drive" then
    table.insert(disk, component.proxy(address))
  end
end

local eeprom = component.list("eeprom")()
local gpu = component.list("gpu")()
local screen = component.list("screen")()
for address in component.list("screen") do
  if #component.invoke(address, "getKeyboards") > 0 then
    screen = address
  end
end

local cls = function()end
if gpu and screen then
  component.invoke(gpu, "bind", screen)
  w, h = component.invoke(gpu, "getResolution")
  component.invoke(gpu, "setResolution", w, h)
  component.invoke(gpu, "setBackground", 0x000000)
  component.invoke(gpu, "setForeground", 0xFFF200)
  component.invoke(gpu, "fill", 1, 1, w, h, " ")
  cls = function()component.invoke(gpu,"fill", 1, 1, w, h, " ")end
end

-- Functions

-- by gammawave
local function getBit(num, pos)
  local bitmask = 2^pos
  return (num & bitmask) == bitmask
end

-- by gammawave 
local function setBit(num, value, pos)
  local bitmask = 2^pos
  if getBit(num, pos) == value then
    return num
  else
    return (num ~ bitmask)
  end
end

local function vram_out(msg, x, y)
  if gpu and screen then
    component.invoke(gpu, "set", x, y, msg)
  end
end

-- BIOS Code
::start::
cls()
vram_out(string.format("MEM: %dKB | CPU: %s | BIOS: %s", computer.totalMemory() / 1024 , computer.getArchitecture(), _OSVERSION), 1, 1)
vram_out("D=", 1, 2)

-- Get user input
while true do
  local event, _, char, code, _ = computer.pullSignal()
  if event == "key_down" then
    local input = string.char(char)
    if input ~= "0" and input == '1' or input == '2' or input == '3' or input == '4' then
      vram_out(input, 3, 2)
      bootdisk = tonumber(input)
      break
    else
      goto start
    end
  end
end

-- Assign bootdrive to the proxy of the drive the user selected in the D= prompt
bootdisk = disk[bootdisk]
local _, _, header, _, volLabel = string.unpack("< I4 I4 c8 I3 c13", bootdisk.readSector(1))
if header ~= "OSDI\xAA\xAA\x55\x55" then
  error("Invalid partition table")
end
vram_out("Volume label: " .. volLabel, 1, 2)
bootdisk.setLabel(volLabel)

-- Get all partitions in table
for i = 1, 15 do
  local offset = 32 * i + 1
  local start, size, partType, flags, name = string.unpack("< I4 I4 c8 I3 c13", bootdisk.readSector(1), offset)
  if start == 0 then
    break
  end
  local datatable = {
  start = start,
  size = size,
  type = partType,
  flags = flags,
  name = name
  }
  partition[i] = datatable
end

-- Find bootcode partition
for i, v in pairs(partition) do
  local part = partition[i]
  if getBit(part.flags, 9) then
    part.last = part.start + part.size - 1
    for i=part.start, part.last do
      bootcode = bootcode .. bootdisk.readSector(i)
    end
  end 
end
bootcode = string.gsub(bootcode, "\0", "")

-- Execute bootcode
component.invoke(gpu, "setForeground", 0xFFFFFF)
local boot, err = load(bootcode, "BOOTCODE", "t", _G)
if type(err) ~= "string" then err = tostring(err) end
if boot then
  cls()
  boot(gpu, screen, bootdisk)
else
  error("Error loading BOOTCODE: " .. err)
end