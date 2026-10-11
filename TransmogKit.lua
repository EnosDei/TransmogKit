-- TransmogKit v0.18 - Transmog overhaul
local ADDON = ...
local TK = CreateFrame("Frame")
local DB
local MOUNT_MACRO, HEARTH_MACRO = "TMK_Mount", "TMK_Hearth"
local QMARK = 134400
local pendingMacro = false


local TYPE_GROUND   = {[230]=true,[241]=true,[269]=true,[284]=true,[408]=true,[412]=true}
local TYPE_FLYING   = {[242]=true,[247]=true,[248]=true,[398]=true,[402]=true,[407]=true,[424]=true,[436]=true,[437]=true,[444]=true}
local TYPE_SWIMMING = {[231]=true,[232]=true,[254]=true,[407]=true,[412]=true}

local HEARTH_TOYS = {
  54452,64488,93672,110560,140192,142542,162973,163045,163206,165669,165670,165802,166746,166747,168907,
  172179,180290,182773,183716,184353,188952,190196,190237,193588,200630,206195,208704,209035,
  210455,212337,228940,235016,236687,245970,246565,257736,263489,263933,265100,281136,281615}
-- spell visual kit each hearth plays while casting (for the character preview)
local HEARTH_KITS = {
  [6948]=36,[54452]=14579,[64488]=36,[93672]=31681,[110560]=266,[140192]=266,[142542]=180930,[162973]=102715,
  [163045]=102824,[163206]=104086,[165669]=106223,[165670]=106285,[165802]=106481,[166746]=106582,[166747]=106588,[168907]=112576,[172179]=118950,
  [180290]=128103,[182773]=142152,[183716]=139168,[184353]=140841,[188952]=152793,[190196]=154737,[190237]=154740,[193588]=159673,
  [200630]=167276,[206195]=180823,[208704]=185670,[209035]=186691,[210455]=198294,[212337]=174334,[228940]=210248,[236687]=224060,
  [245970]=234534,[246565]=235783,[257736]=247250,[263489]=251306,[263933]=251445,[265100]=252859,[281136]=276054,[281615]=277034}

-- itemID -> AnimKit ID for hearths whose cast plays its own character pose; itemID -> looping AnimationData ID for
-- hearths whose kit names a specific loop instead. Both come from SpellVisualKitEffect -> SpellVisualAnim (build 12.1.5).
-- Anything not listed uses the generic casting loop.
local HEARTH_ANIMKITS = {
  [142542]=27317, [165669]=16976, [165670]=16984, [166746]=17054, [180290]=11602, [182773]=11603,
  [184353]=10212, [208704]=27823, [210455]=28517, [212337]=26649, [228940]=30897, [236687]=32318,
  [246565]=19057, [257736]=35175, [265100]=19057, [281136]=2194,
}
local HEARTH_LOOPANIMS = {
  [54452]=52, [93672]=52, [110560]=52, [140192]=52, [162973]=69, [163045]=922, [165802]=1330, [166747]=69,
  [168907]=113, [172179]=879, [183716]=52, [188952]=52, [190196]=1448, [190237]=52, [193588]=52, [200630]=52,
  [206195]=879, [209035]=52, [245970]=52, [263489]=52, [263933]=52, [281615]=878,
}

local function Print(msg) print("|cff66ccffTransmogKit:|r "..msg) end

---------------------------------------------------------------- Blizzard outfits (Midnight)
local OI = C_TransmogOutfitInfo

local function CallFirst(fns, ...)
  if not OI then return end
  for _, fn in ipairs(fns) do
    if OI[fn] then
      local ok, v = pcall(OI[fn], ...)
      if ok and v ~= nil then
        if type(v) == "table" then v = v.outfitID or v.id end
        if type(v) == "number" then return v end
      end
    end
  end
end

-- Outfit worn right now (drives the macros)
local function ActiveOutfitID()
  if OI and OI.GetOutfitsInfo then
    local ok, info = pcall(OI.GetOutfitsInfo)
    if ok and type(info) == "table" and (info.outfitID or info.activeOutfitID) then
      return info.outfitID or info.activeOutfitID
    end
  end
  return CallFirst({"GetActiveOutfitID", "GetCurrentOutfitID", "GetEquippedOutfitID"})
end

-- Outfit selected in the transmog window (drives the mount strip)
local function ViewedOutfitID()
  local v = CallFirst({"GetCurrentlyViewedOutfitID", "GetViewedOutfitID", "GetSelectedOutfitID", "GetDisplayedOutfitID"})
  -- the game reports 0 when no outfit is selected; that is not a real outfit, so don't save anything under it
  if v and v ~= 0 then return v end
  return ActiveOutfitID()
end

local STD = {spell=1,item=1,macro=1,companion=1,equipmentset=1,flyout=1,summonmount=1,summonpet=1}
local function OutfitName(id)
  if not id then return "No outfit" end
  if OI and OI.GetOutfitInfo then
    local ok, info = pcall(OI.GetOutfitInfo, id)
    if ok and type(info) == "table" and info.name and info.name ~= "" then return info.name end
  end
  for slot = 1, 180 do
    local t, aid = GetActionInfo(slot)
    if t and not STD[t] and aid == id then
      local n = GetActionText(slot); if n and n ~= "" then return n end
    end
  end
  return "Outfit "..id
end

local function OutfitExists(id)
  if not (OI and OI.GetOutfitInfo) then return false end
  local ok, info = pcall(OI.GetOutfitInfo, id)
  return ok and type(info) == "table" and info.name ~= nil and info.name ~= ""
end

-- Settings are keyed by outfit ID. If the game hands the same outfit a different ID later (IDs aren't guaranteed
-- to be stable between sessions or characters), find the settings saved under the same outfit name and move them.
local function FindKit(id)
  if not id then return end
  local k = DB.kits[id]
  if k then return k end
  local nm = OutfitName(id)
  if nm and not nm:find("^Outfit %d+$") and nm ~= "No outfit" then
    for oid, kit in pairs(DB.kits) do
      if oid ~= id and kit.name == nm and not OutfitExists(oid) then
        DB.kits[id] = kit; DB.kits[oid] = nil
        return kit
      end
    end
  end
end

local function Kit(id)
  if not id then return end
  local k = FindKit(id)
  if not k then k = {name = OutfitName(id)}; DB.kits[id] = k end
  k.name = OutfitName(id)
  return k
end

local function Saved(kind, what, id)
  if DB then
    DB.lastSave = date("%H:%M:%S").." "..kind.." = "..tostring(what or "cleared").." (outfit "..tostring(id)..")"
    if TransmogKitDB then TransmogKitDB.probe = DB.lastSave end
    if TransmogKitAccountDB then TransmogKitAccountDB.probe = DB.lastSave end
  end
  local o = TransmogKitAccountDB and TransmogKitAccountDB.opts
  if DB and o and o.verbose then Print(("saved %s = %s for outfit %s (%s)"):format(kind, tostring(what or "cleared"), tostring(id), tostring(OutfitName(id)))) end
end

-- Storage: settings live in an account-wide file (like Fitter's FitterSaved), one entry per character. The old
-- per-character file is still read once to carry existing settings over, but nothing depends on it being writable.
local function CharKey()
  return UnitGUID("player") or ("name:"..tostring(UnitName("player")).."-"..tostring(GetRealmName()))
end
local function BindDB()
  local key = CharKey()
  local chars = TransmogKitAccountDB.chars
  if not chars[key] then
    local entry = {}
    for k, v in pairs(TransmogKitDB or {}) do
      if k ~= "probe" then entry[k] = v end
    end
    chars[key] = entry
  end
  DB = chars[key]
  DB.charKey = key
  DB.charName = UnitName("player")
end

-- Each character's file should only hold that character's outfits. If it holds someone else's (a copied settings file),
-- set those aside instead of showing another character's mounts, hearths and titles on this one.
local function ValidateOwner()
  local me = UnitGUID("player")
  if not (DB and me) then return end
  local foreign, checked, why = false, 0, ""
  local function tail(g) return type(g) == "string" and g:sub(-6) or tostring(g) end
  if DB.owner then
    foreign = DB.owner ~= me
    why = "file tagged "..tail(DB.owner).." but this character is "..tail(me)
  else
    local matched = 0
    for oid, k in pairs(DB.kits) do
      if k.name and OutfitExists(oid) then
        checked = checked + 1
        if OutfitName(oid) == k.name then matched = matched + 1 end
      end
    end
    foreign = checked > 0 and matched == 0
    why = "none of the "..checked.." saved outfit names matched this character's outfits"
  end
  if foreign and next(DB.kits) then
    DB.otherKits = DB.kits; DB.kits = {}
    DB.lastPicks = nil; DB.mountCache = nil; DB.hearthCache = nil
    Print("The saved mounts/hearths/titles in this character's file belonged to a different character, so they were set aside ("..why.."). Set this character's own.")
  end
  -- only claim the file once it has been checked (outfit data can still be loading at login)
  if DB.owner or checked > 0 or not next(DB.kits) or foreign then DB.owner = me end
end

---------------------------------------------------------------- macros
-- Account-wide macros: every character rewrites them with its own outfit's mounts on login and on outfit change.
local function WriteMacro(name, icon, body)
  local idx = GetMacroIndexByName(name)
  if idx and idx > 0 then
    EditMacro(idx, name, icon, body)
  else
    local numAccount = GetNumMacros()
    if numAccount >= (MAX_ACCOUNT_MACROS or 120) then
      Print("General (account) macro slots are full. Free one up to create "..name..".")
      return
    end
    CreateMacro(name, icon, body)
    if not (GetMacroIndexByName(name) > 0) then Print("Could not create macro "..name..".") end
  end
end

local function AnyKitSet()
  for _, k in pairs(DB.kits) do
    if k.ground or k.flying or k.swimming or k.hearth then return true end
  end
end

local function BuildMacros(look)
  if not look then return end
  if InCombatLockdown() then pendingMacro = true return end
  -- Settings are per character but the macros are shared by the whole account. A character that hasn't set any
  -- mounts or hearths yet must not overwrite another character's working macros with an empty placeholder.
  if not AnyKitSet() and GetMacroIndexByName(MOUNT_MACRO) > 0 and GetMacroIndexByName(HEARTH_MACRO) > 0 then
    DB.active = look
    return
  end
  local parts = {}
  if look.swimming then parts[#parts+1] = "[swimming] "..look.swimming.name end
  if look.flying   then parts[#parts+1] = "[flyable] "..look.flying.name end
  if look.ground   then parts[#parts+1] = look.ground.name end
  local mountBody
  if #parts == 0 then
    mountBody = "/run print('TransmogKit: no mounts set for "..look.name:gsub("'","").."')"
  else
    if not look.ground then parts[#parts] = parts[#parts]:gsub("^%[%w+%] ", "") end
    mountBody = "#showtooltip\n/cast "..table.concat(parts, "; ")
  end
  WriteMacro(MOUNT_MACRO, QMARK, mountBody)

  local hearthBody = look.hearth and ("#showtooltip\n/use "..look.hearth.name)
    or "/run print('TransmogKit: no hearthstone set for "..look.name:gsub("'","").."')"
  WriteMacro(HEARTH_MACRO, QMARK, hearthBody)
  DB.active = look
end

local lastApplied
local function ApplyActiveOutfit(force)
  local id = ActiveOutfitID()
  if not id then return end
  if id == lastApplied and not force then return end
  local kit = FindKit(id) or {}
  kit.name = OutfitName(id)
  lastApplied = id
  -- The macros follow the outfit you are wearing. If that outfit has no mounts/hearth set, keep using the last ones
  -- that were set rather than blanking the macros.
  local function HasPicks(k) return k and (k.ground or k.flying or k.swimming or k.hearth) end
  local effective = kit
  if HasPicks(kit) then
    DB.lastPicks = {ground = kit.ground, flying = kit.flying, swimming = kit.swimming, hearth = kit.hearth}
  elseif HasPicks(DB.lastPicks) then
    local lp = DB.lastPicks
    effective = {name = kit.name, ground = lp.ground, flying = lp.flying, swimming = lp.swimming, hearth = lp.hearth}
  end
  BuildMacros(effective)
  -- title tied to this outfit (-1 = no title, nil = leave whatever is set)
  if kit.title and GetCurrentTitle and GetCurrentTitle() ~= kit.title then
    if kit.title == -1 or IsTitleKnown(kit.title) then pcall(SetCurrentTitle, kit.title) end
  end
end

local checkQueued = false
local function QueueTransmogCheck()
  if checkQueued or not DB then return end
  checkQueued = true
  C_Timer.After(0.4, function() checkQueued = false; ApplyActiveOutfit() end)
end

---------------------------------------------------------------- data lists
-- Inside raids/dungeons the game can hide mount data from addons, so every good scan is
-- remembered and reused whenever a live scan comes back empty or blocked.
local function IsSecret(v) return issecretvalue and issecretvalue(v) end
local function ScanMounts()
  local out = {}
  local myFaction = (UnitFactionGroup("player") == "Horde") and 0 or 1
  local ok = pcall(function()
    for _, id in ipairs(C_MountJournal.GetMountIDs() or {}) do
      local name, _, icon, _, isUsable, _, isFav, isFactionSpecific, faction, hide, collected = C_MountJournal.GetMountInfoByID(id)
      if IsSecret(name) or IsSecret(collected) then error("blocked") end
      if IsSecret(isUsable) then isUsable = nil end -- hidden in some instances: treat as unknown (usable) instead of blocking the whole list
      if collected and not hide and isUsable ~= false and not (isFactionSpecific and faction ~= nil and faction ~= myFaction) then
        local _, _, _, _, typeID = C_MountJournal.GetMountInfoExtraByID(id)
        if IsSecret(typeID) then typeID = nil end
        out[#out+1] = {id=id, name=name, icon=icon, fav=isFav and true or false, t=typeID}
      end
    end
  end)
  if ok and #out > 0 then
    if DB then DB.mountCache = out end
    return out
  end
  return (DB and DB.mountCache) or out
end

local function GetMountList(kind, showAll)
  local list = {}
  for _, e in ipairs(ScanMounts()) do
    local t = e.t
    local ok = showAll or t == nil
      or (kind == "ground" and TYPE_GROUND[t])
      or (kind == "flying" and TYPE_FLYING[t])
      or (kind == "swimming" and TYPE_SWIMMING[t])
    if ok then list[#list+1] = e end
  end
  table.sort(list, function(a,b) if a.fav ~= b.fav then return a.fav end return a.name < b.name end)
  return list
end

local function GetHearthListLive()
  local list = {}
  local count = (C_Item and C_Item.GetItemCount) and C_Item.GetItemCount(6948) or GetItemCount(6948)
  if count and count > 0 then
    list[#list+1] = {id=6948, name=(C_Item.GetItemNameByID(6948) or "Hearthstone"), icon=134414}
  end
  local ids, seen = {}, {}
  for _, id in ipairs(HEARTH_TOYS) do ids[#ids+1] = id; seen[id] = true end
  -- also pick up any newer hearthstone toy by name (catches ones added after this addon was built)
  local word = ((C_Item.GetItemNameByID(6948) or "Hearthstone"):lower())
  if C_ToyBox and C_ToyBox.GetNumFilteredToys then
    for i = 1, C_ToyBox.GetNumFilteredToys() do
      local tid = C_ToyBox.GetToyFromIndex(i)
      if tid and tid > 0 and not seen[tid] then
        local _, tname = C_ToyBox.GetToyInfo(tid)
        if tname and tname:lower():find(word, 1, true) then ids[#ids+1] = tid; seen[tid] = true end
      end
    end
  end
  for _, id in ipairs(ids) do
    local usable = C_ToyBox.IsToyUsable and C_ToyBox.IsToyUsable(id)
    if IsSecret(usable) then usable = nil end
    if PlayerHasToy(id) and usable ~= false then
      local _, name, icon = C_ToyBox.GetToyInfo(id)
      name = name or C_Item.GetItemNameByID(id)
      if name then list[#list+1] = {id=id, name=name, icon=icon or QMARK}
      else C_Item.RequestLoadItemDataByID(id) end
    end
  end
  table.sort(list, function(a,b) return a.name < b.name end)
  return list
end

local function GetHearthList()
  local ok, list = pcall(GetHearthListLive)
  if ok and list and #list > 0 then
    if DB then DB.hearthCache = list end
    return list
  end
  return (DB and DB.hearthCache) or {}
end

---------------------------------------------------------------- UI helpers
local function Label(parent, text, size)
  local fs = parent:CreateFontString(nil, "OVERLAY", size or "GameFontNormal")
  fs:SetText(text)
  return fs
end

local function Button(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 80, h or 22); b:SetText(text)
  return b
end

local function MakeFrame(name, w, h, title)
  local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(w, h); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  local t = Label(f, title); t:SetPoint("TOP", 0, -5)
  tinsert(UISpecialFrames, name)
  f:Hide()
  return f
end

---------------------------------------------------------------- picker
local ROWS, ROW_H = 10, 24
local picker = MakeFrame("TransmogKitPicker", 300, 370, "Choose")
picker:SetFrameStrata("FULLSCREEN_DIALOG"); picker:SetFixedFrameStrata(true); picker:SetToplevel(true); picker:SetFrameLevel(600)
local pSearch = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
pSearch:SetSize(180, 20); pSearch:SetPoint("TOPLEFT", 18, -32); pSearch:SetAutoFocus(false)
local pAll = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
pAll:SetPoint("LEFT", pSearch, "RIGHT", 6, 0); pAll:SetSize(24, 24)
local pAllText = Label(pAll, "All", "GameFontHighlightSmall"); pAllText:SetPoint("LEFT", pAll, "RIGHT", 0, 0)
local pScroll = CreateFrame("ScrollFrame", "TransmogKitPickerScroll", picker, "FauxScrollFrameTemplate")
pScroll:SetPoint("TOPLEFT", 10, -60); pScroll:SetPoint("BOTTOMRIGHT", -30, 40)
local pClear = Button(picker, "Clear slot", 100); pClear:SetPoint("BOTTOM", 0, 12)
picker.rows, picker.data = {}, {}
for r = 1, ROWS do
  local b = CreateFrame("Button", nil, picker)
  b:SetSize(250, ROW_H); b:SetPoint("TOPLEFT", 14, -60 - (r-1)*ROW_H)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(20, 20); b.icon:SetPoint("LEFT")
  b.text = Label(b, "", "GameFontHighlight"); b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetWidth(220); b.text:SetJustifyH("LEFT")
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b:SetScript("OnClick", function(self)
    if picker.onPick and self.entry then picker.onPick(self.entry) end
    picker:Hide()
  end)
  b:SetScript("OnEnter", function(self) if self.entry and picker.Preview then picker.Preview(self.entry) end end)
  picker.rows[r] = b
end

local function PickerUpdate()
  local filter = (pSearch:GetText() or ""):lower()
  local src = picker.kind == "hearth" and GetHearthList() or GetMountList(picker.kind, pAll:GetChecked())
  wipe(picker.data)
  for _, e in ipairs(src) do
    if filter == "" or e.name:lower():find(filter, 1, true) then picker.data[#picker.data+1] = e end
  end
  FauxScrollFrame_Update(pScroll, #picker.data, ROWS, ROW_H)
  local off = FauxScrollFrame_GetOffset(pScroll)
  for r = 1, ROWS do
    local e, row = picker.data[off + r], picker.rows[r]
    if e then row.entry = e; row.icon:SetTexture(e.icon); row.text:SetText((e.fav and "|A:PetJournal-FavoritesIcon:14:14|a " or "")..e.name); row:Show()
    else row.entry = nil; row:Hide() end
  end
end
pScroll:SetScript("OnVerticalScroll", function(self, o) FauxScrollFrame_OnVerticalScroll(self, o, ROW_H, PickerUpdate) end)
pSearch:SetScript("OnTextChanged", PickerUpdate)
pSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
pAll:SetScript("OnClick", PickerUpdate)
pClear:SetScript("OnClick", function() if picker.onPick then picker.onPick(nil) end picker:Hide() end)

---- preview: mounts in a Mount Journal-style scene, hearths on the transmog character
local pv = CreateFrame("Frame", nil, picker, "BackdropTemplate")
pv:SetPoint("TOPLEFT", picker, "TOPRIGHT", 4, 0); pv:SetSize(300, 370)
pv:SetFrameStrata("FULLSCREEN_DIALOG"); pv:SetFixedFrameStrata(true); pv:SetFrameLevel(600)
pv:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
pv:SetBackdropColor(0.04, 0.04, 0.06, 0.95); pv:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.9); pv:Hide()
pv.name = Label(pv, "", "GameFontNormal"); pv.name:SetPoint("TOP", 0, -8); pv.name:SetWidth(280)
pv.hint = Label(pv, "Hover a mount to preview it", "GameFontDisableSmall"); pv.hint:SetPoint("BOTTOM", 0, 8)
local okScene, scene = pcall(CreateFrame, "ModelScene", nil, pv, "WrappedAndUnwrappedModelScene")
if okScene and scene then scene:SetPoint("TOPLEFT", 4, -26); scene:SetPoint("BOTTOMRIGHT", -4, 24) else scene = nil end

local function PendingLook()
  local cp = _G.TransmogFrame and _G.TransmogFrame:IsShown() and _G.TransmogFrame.CharacterPreview
  if cp and cp.GetItemTransmogInfoList then
    local ok, list = pcall(cp.GetItemTransmogInfoList, cp); if ok then return list end
  end
end
local function DressRider()
  if not scene then return end
  local rider = scene.GetPlayerActor and scene:GetPlayerActor("player-rider")
  local list = PendingLook()
  if not (rider and list) then return end
  for slotID, info in pairs(list) do
    if slotID ~= 16 and slotID ~= 17 then pcall(rider.SetItemTransmogInfo, rider, info, slotID) end
  end
end

local function PreviewMount(mountID)
  if not scene then return end
  local creatureDisplayID, _, _, isSelfMount, _, modelSceneID, animID, spellVisualKitID, disableRider = C_MountJournal.GetMountInfoExtraByID(mountID)
  if not creatureDisplayID then
    local all = C_MountJournal.GetMountAllCreatureDisplayInfoByID and C_MountJournal.GetMountAllCreatureDisplayInfoByID(mountID)
    creatureDisplayID = all and all[1] and all[1].creatureDisplayID
  end
  if not (creatureDisplayID and modelSceneID) then return end
  scene:TransitionToModelSceneID(modelSceneID, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
  local actor = scene:GetActorByTag("unwrapped")
  if not actor then return end
  actor:SetModelByCreatureDisplayID(creatureDisplayID, true)
  if isSelfMount then
    actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.None); actor:SetAnimation(618)
  else
    actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.Anim); actor:SetAnimation(0)
  end
  local native = PlayerUtil and PlayerUtil.ShouldUseNativeFormInModelScene and PlayerUtil.ShouldUseNativeFormInModelScene() or false
  scene:AttachPlayerToMount(actor, animID, isSelfMount, disableRider, spellVisualKitID, native)
  DressRider(); C_Timer.After(0.15, DressRider); C_Timer.After(0.6, DressRider)
end

-- hearth: play the hearth's cast effect on the big transmog character, stop when the picker closes
local hearthActor
local function StopHearth()
  if hearthActor then
    pcall(hearthActor.SetSpellVisualKit, hearthActor, 0); pcall(hearthActor.SetAnimation, hearthActor, 0)
    hearthActor = nil
  end
end
local function PreviewHearth(itemID)
  StopHearth()
  local cp = _G.TransmogFrame and _G.TransmogFrame:IsShown() and _G.TransmogFrame.CharacterPreview
  local ms = cp and cp.ModelScene
  local actor = type(ms) == "table" and ms.GetPlayerActor and ms:GetPlayerActor()
  if not actor then return end
  hearthActor = actor
  -- a hearth with its own animation kit or loop plays that pose; everything else gets the generic casting loop
  local anim = HEARTH_ANIMKITS[itemID]
  if anim and actor.PlayAnimationKit and pcall(actor.PlayAnimationKit, actor, anim, true) then
    -- pose is playing
  else
    pcall(actor.SetAnimation, actor, HEARTH_LOOPANIMS[itemID] or 51) -- 51 = generic SpellCastDirected loop
  end
  local kit = HEARTH_KITS[itemID]
  if kit then pcall(actor.SetSpellVisualKit, actor, kit, false) end
end

picker.Preview = function(e)
  if picker.kind == "hearth" then PreviewHearth(e.id)
  else pv.name:SetText(e.name); pv.hint:SetText(""); pcall(PreviewMount, e.id) end
end
-- 3D models ignore frame layering against each other, so tuck the big character and the
-- Finder's item models away while the mount preview is up, and bring them back after.
local tucked = {}
local function Tuck()
  local cp = _G.TransmogFrame and _G.TransmogFrame.CharacterPreview
  for _, f in ipairs({cp and type(cp.ModelScene) == "table" and cp.ModelScene or nil, _G.TransmogKitItemGrid}) do
    if f and f.IsShown and f:IsShown() then f:Hide(); tucked[#tucked+1] = f end
  end
end
local function Untuck()
  for _, f in ipairs(tucked) do f:Show() end
  wipe(tucked)
end
picker:HookScript("OnHide", function() StopHearth(); pv:Hide(); Untuck() end)

local function OpenPicker(kind, onPick)
  picker.kind, picker.onPick = kind, onPick
  pSearch:SetText(""); pAll:SetChecked(false)
  pAll:SetShown(kind ~= "hearth")
  StopHearth()
  pv:SetShown(kind ~= "hearth" and scene ~= nil)
  Untuck(); if pv:IsShown() then Tuck() end
  pv.name:SetText(""); pv.hint:SetText("Hover a mount to preview it")
  -- open right above the mount/hearth strip when it's visible
  picker:ClearAllPoints()
  local st = _G.TransmogKitStrip
  if st and st:IsVisible() then picker:SetPoint("BOTTOMLEFT", st, "TOPLEFT", 0, 4) else picker:SetPoint("CENTER") end
  picker:Show(); picker:Raise(); PickerUpdate()
end

---------------------------------------------------------------- theme
local function Skin(f, a)
  if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
  f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
  f:SetBackdropColor(0.06, 0.06, 0.08, a or 0.92)
  f:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.9)
end

local function FlatButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h or 22); Skin(b, 1)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("CENTER"); b.text:SetText(text)
  b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0.3, 1) end)
  b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.9) end)
  function b:SetLabel(t) self.text:SetText(t) end
  return b
end

---------------------------------------------------------------- mount strip inside the transmog window
local strip = CreateFrame("Frame", "TransmogKitStrip", UIParent, "BackdropTemplate")
strip:SetSize(228, 112); Skin(strip); strip:Hide()
strip.title = Label(strip, "", "GameFontNormalSmall"); strip.title:SetPoint("TOPLEFT", 8, -7); strip.title:SetWidth(212); strip.title:SetJustifyH("LEFT")
strip.slots = {}
local STRIP_DEFS = {
  {key="ground", label="Ground"}, {key="flying", label="Flying"},
  {key="swimming", label="Swim"}, {key="hearth", label="Hearth"},
}
local TitleRefresh
local function StripRefresh()
  if TitleRefresh then TitleRefresh() end
  local id = ViewedOutfitID()
  strip.outfitID = id
  strip.title:SetText(id and ("Mounts for: |cffffffff"..OutfitName(id).."|r") or "Select an outfit")
  local kit = id and FindKit(id)
  for _, def in ipairs(STRIP_DEFS) do
    local b, v = strip.slots[def.key], kit and kit[def.key]
    b.icon:SetTexture(v and v.icon or QMARK); b.icon:SetDesaturated(not v)
    b:SetEnabled(id ~= nil)
  end
end
for i, def in ipairs(STRIP_DEFS) do
  local b = CreateFrame("Button", nil, strip, "BackdropTemplate")
  b:SetSize(46, 46); b:SetPoint("TOPLEFT", 8 + (i-1)*54, -24); Skin(b, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.lab = Label(b, def.label, "GameFontDisableSmall"); b.lab:SetPoint("TOP", b, "BOTTOM", 0, -2)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnEnter", function(self)
    local kit = strip.outfitID and FindKit(strip.outfitID); local v = kit and kit[def.key]
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(def.label..": "..(v and v.name or "not set"))
    GameTooltip:AddLine("Click to choose, right-click to clear", 1,1,1); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:SetScript("OnClick", function(_, btn)
    local id = strip.outfitID; if not id then return end
    local function set(e)
      Kit(id)[def.key] = e and {id=e.id, name=e.name, icon=e.icon} or nil
      Saved(def.key, e and e.name, id)
      StripRefresh()
      if id == ActiveOutfitID() then ApplyActiveOutfit(true) end
    end
    if btn == "RightButton" then set(nil)
    elseif not (TransmogKit_OpenMountFinder and TransmogKit_OpenMountFinder(def.key)) then OpenPicker(def.key, set) end
  end)
  strip.slots[def.key] = b
end
local macroB = FlatButton(strip, "Put macros on bars", 212, 18); macroB:SetPoint("BOTTOM", 0, 6)
macroB:SetScript("OnClick", function()
  if not InCombatLockdown() then ApplyActiveOutfit(true); ShowMacroFrame() end
  Print("Drag |cffffff00"..MOUNT_MACRO.."|r and |cffffff00"..HEARTH_MACRO.."|r from the General Macros tab onto your bars once. They follow your outfit from then on.")
end)
local stripTimer = 0
strip:SetScript("OnUpdate", function(self, el)
  stripTimer = stripTimer + el
  if stripTimer > 0.4 then stripTimer = 0; if ViewedOutfitID() ~= self.outfitID then StripRefresh() end end
end)

---------------------------------------------------------------- title picker above the character
local titleB = FlatButton(UIParent, "", 256, 22); titleB:Hide()
local function TitleText(id)
  if id == -1 then return "No title" end
  local n = id and GetTitleName(id)
  return n and (n:gsub("^%s+", ""):gsub("%s+$", "")) or nil
end
function TitleRefresh()
  local id = ViewedOutfitID(); local kit = id and FindKit(id)
  local t = kit and kit.title
  titleB:SetLabel("Title: "..(t and ("|cffffffff"..(TitleText(t) or "?").."|r") or "|cff888888keep current|r"))
  titleB:SetEnabled(id ~= nil)
end
local function SetOutfitTitle(t)
  local id = ViewedOutfitID(); if not id then return end
  Kit(id).title = t
  Saved("title", t, id)
  TitleRefresh()
  if id == ActiveOutfitID() then ApplyActiveOutfit(true) end
end
titleB:SetScript("OnClick", function(self)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  local list = {}
  for i = 1, GetNumTitles() do
    if IsTitleKnown(i) then local n = TitleText(i); if n and n ~= "" then list[#list+1] = {i, n} end end
  end
  table.sort(list, function(a, b) return a[2] < b[2] end)
  local id = ViewedOutfitID(); local cur = id and FindKit(id) and FindKit(id).title
  MenuUtil.CreateContextMenu(self, function(_, root)
    if root.SetScrollMode then root:SetScrollMode(420) end
    root:CreateRadio("Keep current title", function() return cur == nil end, function() SetOutfitTitle(nil) end)
    root:CreateRadio("No title", function() return cur == -1 end, function() SetOutfitTitle(-1) end)
    if root.CreateDivider then root:CreateDivider() end
    for _, t in ipairs(list) do
      root:CreateRadio(t[2], function() return cur == t[1] end, function() SetOutfitTitle(t[1]) end)
    end
  end)
end)
titleB:HookScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Outfit title")
  GameTooltip:AddLine("Switches to this title whenever you wear this outfit.", 1, 1, 1, true); GameTooltip:Show()
end)
titleB:HookScript("OnLeave", GameTooltip_Hide)

---------------------------------------------------------------- Finder: sets + items by color
local EXPANSIONS = {[0]="Classic","Burning Crusade","Wrath","Cataclysm","Pandaria","Draenor","Legion",
  "Battle for Azeroth","Shadowlands","Dragonflight","The War Within","Midnight"}
local TYPE_OPTS = {"Any", "PvE", "PvP"}
local COLL_OPTS = {"Collected", "Collected", "Collected", "Favorites"}  -- 2 = collected, 4 = favorites; uncollected is never listed

-- Blizzard-style dropdown menu (falls back to nothing if the menu system is missing)
local function OpenMenu(owner, items, isSel, onSel)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    for _, it in ipairs(items) do
      root:CreateRadio(it[2], function() return isSel(it[1]) end, function() onSel(it[1]) end, it[1])
    end
  end)
  return true
end
local function AddArrow(b)
  b.arrow = b:CreateTexture(nil, "OVERLAY"); b.arrow:SetSize(10, 10); b.arrow:SetPoint("RIGHT", -5, 0)
  b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up"); b.arrow:SetTexCoord(0, 1, 0, 0.5)
end
local PVP_WORDS = {"gladiator","combatant","aspirant","elite","vindictive","veteran","pvp","warfront","conquest","honor"}
local DIFF_WORDS = {"raid finder","normal","heroic","mythic","lfr"}
local TOLS = {{"Exact", 11}, {"Close", 18}, {"Similar", 27}, {"Loose", 38}}

local function IsPvP(set)
  local t = ((set.name or "").." "..(set.label or "").." "..(set.description or "")):lower()
  for _, w in ipairs(PVP_WORDS) do if t:find(w, 1, true) then return true end end
end
local function IsTier(set)
  if IsPvP(set) or not set.classMask or set.classMask == 0 then return false end
  local d = (set.description or ""):lower()
  for _, w in ipairs(DIFF_WORDS) do if d:find(w, 1, true) then return true end end
  return set.baseSetID ~= nil
end
local function SetProgress(setID)
  local have, total = 0, 0
  local ok, list = pcall(C_TransmogSets.GetSetPrimaryAppearances, setID)
  if ok and list then
    for _, a in ipairs(list) do total = total + 1; if a.collected then have = have + 1 end end
  end
  return have, total, list
end
local function SetIcon(list)
  if list and list[1] and C_TransmogCollection.GetSourceIcon then
    local ok, ic = pcall(C_TransmogCollection.GetSourceIcon, list[1].appearanceID or list[1].sourceID)
    if ok and ic then return ic end
  end
  return QMARK
end

---- color math (data file: TransmogKitColorData[visualID] = "exp,rrggbbW rrggbbW ...")
local CM = {cache = {}}
function CM.lin(c) c = c / 255; if c > 0.04045 then return ((c + 0.055) / 1.055) ^ 2.4 end return c / 12.92 end
function CM.lab(r, g, b) -- 0..255
  r, g, b = CM.lin(r), CM.lin(g), CM.lin(b)
  local x = (r*0.4124 + g*0.3576 + b*0.1805) / 0.95047
  local y =  r*0.2126 + g*0.7152 + b*0.0722
  local z = (r*0.0193 + g*0.1192 + b*0.9505) / 1.08883
  local function f(t) if t > 0.008856 then return t ^ (1/3) end return 7.787 * t + 16/116 end
  x, y, z = f(x), f(y), f(z)
  return 116*y - 16, 500*(x - y), 200*(y - z)
end
function CM.get(visualID)
  local c = CM.cache[visualID]; if c ~= nil then return c end
  local s = TransmogKitColorData and TransmogKitColorData[visualID]
  if not s then CM.cache[visualID] = false; return false end
  local exp, cols = s:match("^(%-?%d*),(.*)$")
  local out = {exp = tonumber(exp)}
  for hex, w in (cols or ""):gmatch("(%x%x%x%x%x%x)(%d)") do
    local r, g, b = tonumber(hex:sub(1,2), 16), tonumber(hex:sub(3,4), 16), tonumber(hex:sub(5,6), 16)
    local L, A, B = CM.lab(r, g, b)
    out[#out+1] = {L, A, B, tonumber(w), r/255, g/255, b/255}
  end
  CM.cache[visualID] = out; return out
end
-- returns raw distance of the closest meaningful color, and a sort score favoring dominant colors
function CM.dist(info, q)
  local best, score = 999, 999
  for _, c in ipairs(info) do
    if c[4] >= 2 then
      local d = math.sqrt((c[1]-q[1])^2 + (c[2]-q[2])^2 + (c[3]-q[3])^2)
      if d < best then best = d end
      local sc = d - c[4] * 0.8
      if sc < score then score = sc end
    end
  end
  return best, score
end
-- how well one appearance's full color palette matches another's (both from CM.get); used for
-- the saved-palette filter. Passes only when most of the query's dominant color weight finds a
-- close match; score favors both closeness and coverage, so results rank most-similar-first.
function CM.itemDist(info, qInfo, tol, need)
  local wsum, dsum, hitw = 0, 0, 0
  for _, qc in ipairs(qInfo) do
    if qc[4] >= 2 then
      local d = CM.dist(info, qc)
      wsum = wsum + qc[4]; dsum = dsum + d * qc[4]
      if d <= tol then hitw = hitw + qc[4] end
    end
  end
  if wsum == 0 then return false, 999, 0 end
  local frac = hitw / wsum
  return frac >= (need or 0.5), (dsum / wsum) - frac * 20, math.floor(frac * 100 + 0.5)
end
-- turns a hand-picked list of colors ({r,g,b} in 0-1) into a query like CM.get returns. Every picked color
-- counts equally; with 1-2 colors an item must match all of them, with more it may miss one.
function CM.multiInfo(list)
  local q = {}
  for _, c in ipairs(list) do
    local L, A, B = CM.lab(c[1] * 255, c[2] * 255, c[3] * 255)
    q[#q+1] = {L, A, B, 3}
  end
  local n = #q
  return q, (n <= 2 and 1 or (n - 1) / n) - 0.001
end
function CM.hsv(h, s, v)
  local i = math.floor(h * 6); local f = h * 6 - i
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  i = i % 6
  if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
  return v, p, q
end

---- main frame
local SearchUpdate
local search = CreateFrame("Frame", "TransmogKitSearch", UIParent, "BackdropTemplate")
search:SetSize(330, 600); Skin(search); search:Hide()
search:SetMovable(true); search:EnableMouse(true); search:RegisterForDrag("LeftButton")
search:SetScript("OnDragStart", search.StartMoving); search:SetScript("OnDragStop", search.StopMovingOrSizing)
tinsert(UISpecialFrames, "TransmogKitSearch")
local sTitle = Label(search, "TransmogKit  |cffaaaaaaFinder|r", "GameFontNormal"); sTitle:SetPoint("TOP", 0, -8)
local sClose = CreateFrame("Button", nil, search, "UIPanelCloseButton"); sClose:SetPoint("TOPRIGHT", 2, 2)
local countT = Label(search, "", "GameFontDisableSmall"); countT:SetPoint("TOPLEFT", 12, -10)
search.f = {exp=-1, type=1, coll=2, tier=false, color=nil, tol=2, mode="items", cat=1, page=1}
search.rows, search.data, search.cache = {}, {}, nil
local UI = {}   -- groups widgets to stay under Lua's local-variable limit

UI.modeSets    = FlatButton(search, "Sets", 40, 18)
UI.modeItems   = FlatButton(search, "Items", 44, 18)
UI.modeMounts  = FlatButton(search, "Mounts", 52, 18)
UI.modeEffects = FlatButton(search, "Effects", 52, 18)
UI.modeMore = FlatButton(search, "More", 44, 18)
UI.modeMore:SetPoint("TOPRIGHT", -34, -6)
UI.modeEffects:SetPoint("RIGHT", UI.modeMore, "LEFT", -3, 0)
UI.modeMounts:SetPoint("RIGHT", UI.modeEffects, "LEFT", -3, 0)
UI.modeItems:SetPoint("RIGHT", UI.modeMounts, "LEFT", -3, 0)
UI.modeSets:SetPoint("RIGHT", UI.modeItems, "LEFT", -3, 0)

local sBox = CreateFrame("EditBox", nil, search, "InputBoxTemplate")
sBox:SetHeight(20); sBox:SetAutoFocus(false)
sBox.hint = Label(sBox, "Search set names...", "GameFontDisableSmall"); sBox.hint:SetPoint("LEFT", 4, 0)

UI.exp   = FlatButton(search, "", 150, 22)
UI.type  = FlatButton(search, "", 76, 22)
UI.tier  = FlatButton(search, "", 76, 22)
UI.coll  = FlatButton(search, "", 100, 22)
UI.nameBox = CreateFrame("EditBox", nil, search, "InputBoxTemplate"); UI.nameBox:SetHeight(20); UI.nameBox:SetAutoFocus(false)
UI.nameBox:SetMaxLetters(60); UI.nameBox:Hide()
UI.nameBox.ph = UI.nameBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); UI.nameBox.ph:SetPoint("LEFT", 2, 0); UI.nameBox.ph:SetText("Search by name...")
UI.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
UI.nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
UI.nameBox:SetScript("OnTextChanged", function(self, user)
  self.ph:SetShown((self:GetText() or "") == "")
  if not user then return end
  local token = (self.tok or 0) + 1; self.tok = token
  C_Timer.After(0.25, function()
    if self.tok ~= token then return end
    local t = (self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    search.f.text = t; search.f.page = 1; SearchUpdate()
  end)
end)
UI.color = FlatButton(search, "", 100, 22)
UI.color.swatch = UI.color:CreateTexture(nil, "OVERLAY"); UI.color.swatch:SetSize(12, 12); UI.color.swatch:SetPoint("LEFT", 6, 0)
UI.color.ms = {}
for i = 1, 8 do
  local t = UI.color:CreateTexture(nil, "OVERLAY"); t:SetSize(12, 12); t:SetPoint("LEFT", 6 + (i - 1) * 14, 0); t:Hide(); UI.color.ms[i] = t
end
UI.items = FlatButton(search, "Search Items tab", 102, 22)
for _, b in ipairs({UI.exp, UI.type, UI.coll}) do AddArrow(b) end

local SROWS, SROW_H, MAX_ROWS = 16, 28, 26
local sScroll = CreateFrame("ScrollFrame", "TransmogKitSearchScroll", search, "FauxScrollFrameTemplate")
sScroll:SetPoint("TOPLEFT", 8, -118); sScroll:SetPoint("BOTTOMRIGHT", -30, 34)
UI.help = Label(search, "", "GameFontDisableSmall"); UI.help:SetPoint("BOTTOM", 0, 10)

---- talking to Blizzard's window
local function FindTab(parent, label, depth)
  depth = depth or 0
  if depth > 3 or not parent or not parent.GetChildren then return end
  for _, c in ipairs({parent:GetChildren()}) do
    local t = (c.GetText and c:GetText()) or (c.Text and c.Text.GetText and c.Text:GetText())
    if t == label and c.Click then return c end
    local found = FindTab(c, label, depth + 1); if found then return found end
  end
end

local function PushSearch(frameKey, tabLabel, tabIndex, text)
  local host = _G.TransmogFrame
  local wc = host and host.WardrobeCollection
  local page = wc and wc.TabContent and wc.TabContent[frameKey]
  if not page then return false end
  if not page:IsShown() then
    local tab = FindTab(wc.TabHeaders, tabLabel) or FindTab(wc, tabLabel)
    if tab then tab:Click()
    elseif wc.SetTab then pcall(wc.SetTab, wc, tabIndex)
    elseif wc.tabSystem and wc.tabSystem.SetTab then pcall(wc.tabSystem.SetTab, wc.tabSystem, tabIndex) end
  end
  local box = page.SearchBox
  if box then
    box:SetText(text or "")
    local fn = box:GetScript("OnTextChanged"); if fn then pcall(fn, box, true) end
  end
  return true
end

-- Click the matching slot button on Blizzard's character preview
local function SelectBlizzSlot(invSlot)
  local cp = _G.TransmogFrame and _G.TransmogFrame.CharacterPreview
  if not cp then return end
  for _, group in ipairs({cp.LeftSlots, cp.RightSlots, cp.BottomSlots}) do
    if group then
      local function scan(f, d)
        if d > 2 then return end
        for _, c in ipairs({f:GetChildren()}) do
          local sid = c.slotID or c.slot or c.inventorySlot
          if not sid and c.transmogLocation and c.transmogLocation.GetSlotID then sid = c.transmogLocation:GetSlotID() end
          if not sid and c.GetSlotID then local ok, v = pcall(c.GetSlotID, c); if ok then sid = v end end
          if sid == invSlot and c.Click then c:Click(); return true end
          if scan(c, d + 1) then return true end
        end
      end
      if scan(group, 0) then return true end
    end
  end
end

local function Preview(links)
  local first = true
  for _, link in ipairs(links) do
    if first and DressUpFrame and DressUpFrame_Show then pcall(DressUpFrame_Show, DressUpFrame); first = false end
    pcall(DressUpItemLink, link)
  end
end

local function SetLinks(e)
  local out = {}
  local _, _, list = SetProgress(e.setID)
  for _, a in ipairs(list or {}) do
    local info = C_TransmogCollection.GetSourceInfo(a.appearanceID or a.sourceID)
    if info and info.itemID then
      local link = select(2, C_Item.GetItemInfo(info.itemID))
      if link then out[#out+1] = link else C_Item.RequestLoadItemDataByID(info.itemID) end
    end
  end
  return out
end

---- set rows
for r = 1, MAX_ROWS do
  local b = CreateFrame("Button", nil, search)
  b:SetHeight(SROW_H); b:SetPoint("TOPLEFT", 12, -118 - (r-1)*SROW_H); b:SetPoint("RIGHT", search, "RIGHT", -30, 0)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(24, 24); b.icon:SetPoint("LEFT")
  b.name = Label(b, "", "GameFontHighlightSmall"); b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, 0)
  b.name:SetPoint("RIGHT", b, "RIGHT", -44, 0); b.name:SetJustifyH("LEFT"); b.name:SetWordWrap(false)
  b.sub = Label(b, "", "GameFontDisableSmall"); b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 6, 0)
  b.sub:SetPoint("RIGHT", b, "RIGHT", -44, 0); b.sub:SetJustifyH("LEFT"); b.sub:SetWordWrap(false)
  b.prog = Label(b, "", "GameFontHighlightSmall"); b.prog:SetPoint("RIGHT", -2, 0)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b:SetScript("OnClick", function(self)
    local e = self.entry; if not e then return end
    if IsShiftKeyDown() then
      local link = "|cffff80ff|Htransmogset:"..e.setID.."|h["..e.name.."]|h|r"
      if not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
    elseif IsControlKeyDown() or not PushSearch("SetsFrame", _G.WARDROBE_SETS or "Sets", 2, e.name) then
      Preview(SetLinks(e))
    end
  end)
  search.rows[r] = b
end

local function LoadSets()
  if search.cache then return search.cache end
  local out = {}
  local ok, sets = pcall(C_TransmogSets.GetAllSets)
  local myBit = bit.lshift(1, select(3, UnitClass("player")) - 1)
  for _, set in ipairs(ok and sets or {}) do
    if not set.classMask or set.classMask == 0 or bit.band(set.classMask, myBit) ~= 0 then
      local have, total, list = SetProgress(set.setID)
      out[#out+1] = {
        setID=set.setID, name=set.name or "?", label=set.label, desc=set.description,
        exp=set.expansionID or -1, pvp=IsPvP(set), tier=IsTier(set),
        have=have, total=total, icon=SetIcon(list), fav=set.favorite,
      }
    end
  end
  table.sort(out, function(a, b) if a.exp ~= b.exp then return a.exp > b.exp end return a.name < b.name end)
  search.cache = out
  return out
end

-- fraction of a set's pieces that match the chosen color
local function SetColorMatch(e, q, tol)
  if not e.vis then
    e.vis = {}
    local _, _, list = SetProgress(e.setID)
    for _, a in ipairs(list or {}) do
      local info = C_TransmogCollection.GetSourceInfo(a.appearanceID or a.sourceID)
      if info and info.visualID then e.vis[#e.vis+1] = info.visualID end
    end
  end
  local hit, n, sc = 0, 0, 0
  for _, v in ipairs(e.vis) do
    local info = CM.get(v)
    if info then
      n = n + 1
      local d, s = CM.dist(info, q)
      if d <= tol then hit = hit + 1; sc = sc + s end
    end
  end
  if n == 0 then return false end
  return hit >= math.max(1, math.ceil(n * 0.35)), hit / n
end

---- items view (model grid)
local iv = CreateFrame("Frame", "TransmogKitItemGrid", search)
iv:SetPoint("TOPLEFT", 8, -60); iv:SetPoint("BOTTOMRIGHT", -8, 26)
iv.cells, iv.data, iv.slotButtons = {}, {}, {}
local ARMOR = { -- category order used by the game (Enum.TransmogCollectionType)
  {1, 1, "Head"}, {2, 3, "Shldr"}, {3, 15, "Back"}, {4, 5, "Chest"}, {5, 4, "Shirt"}, {6, 19, "Tabard"},
  {7, 9, "Wrist"}, {8, 10, "Hands"}, {9, 6, "Waist"}, {10, 7, "Legs"}, {11, 8, "Feet"},
}
iv.weapons = nil
-- Blizzard's slot frame for an inventory slot (only while the transmog window is open)
local function BlizzSlot(invSlot)
  local tf = _G.TransmogFrame
  local cp = tf and tf:IsShown() and tf.CharacterPreview
  local OI = C_TransmogOutfitInfo
  if not (cp and cp.GetSlotFrame and OI and OI.GetTransmogOutfitSlotFromInventorySlot) then return end
  local ok, slot = pcall(OI.GetTransmogOutfitSlotFromInventorySlot, invSlot - 1)
  if not ok or slot == nil then return end
  local okF, sf = pcall(cp.GetSlotFrame, cp, slot, Enum.TransmogType.Appearance)
  if okF and sf and sf.slotData then return slot, sf end
end

-- Only weapon types this character can actually put in the main or off hand
local function WeaponCats()
  if iv.weapons then return iv.weapons end
  local out, seen = {}, {}
  local OI = C_TransmogOutfitInfo
  for _, inv in ipairs({16, 17}) do
    local slot, sf = BlizzSlot(inv)
    if slot then
      local opts = sf.slotData.weaponOptionsInfo or (OI.GetWeaponOptionsForSlot and OI.GetWeaponOptionsForSlot(slot)) or {}
      for cat = 12, 60 do
        if not seen[cat] then
          for _, w in ipairs(opts) do
            if w.enabled then
              local ok, info = pcall(OI.GetCollectionInfoForSlotAndOption, slot, w.weaponOption, cat)
              if ok and info and info.isWeapon then
                seen[cat] = true; out[#out+1] = {cat, inv, info.name or ("Weapon "..cat)}; break
              end
            end
          end
        end
      end
    end
  end
  if #out == 0 then -- window closed: fall back to the full list
    for cat = 12, 40 do
      local ok, name, isWeapon, _, canMain, canOff = pcall(C_TransmogCollection.GetCategoryInfo, cat)
      if ok and name and isWeapon then out[#out+1] = {cat, (canOff and not canMain) and 17 or 16, name} end
    end
    return out
  end
  table.sort(out, function(x, y) return x[3] < y[3] end)
  iv.weapons = out
  return out
end
local function CatInfo(cat)
  for _, a in ipairs(ARMOR) do if a[1] == cat then return a end end
  for _, w in ipairs(WeaponCats()) do if w[1] == cat then return w end end
end

for i, a in ipairs(ARMOR) do
  local b = FlatButton(iv, a[3], 40, 20)
  b:SetScript("OnClick", function() search.f.cat = a[1]; search.f.page = 1; SearchUpdate() end)
  iv.slotButtons[i] = b
end
-- can this weapon category go in the given hand (16 main, 17 off)? Dual-wielders can use one-handers in both.
local function CatFitsHand(cat, inv)
  local OI = C_TransmogOutfitInfo
  local slot, sf = BlizzSlot(inv)
  if not slot then return false end
  local opts = sf.slotData.weaponOptionsInfo or (OI.GetWeaponOptionsForSlot and OI.GetWeaponOptionsForSlot(slot)) or {}
  for _, w in ipairs(opts) do
    if w.enabled then
      local ok, info = pcall(OI.GetCollectionInfoForSlotAndOption, slot, w.weaponOption, cat)
      if ok and info and info.isWeapon then return true end
    end
  end
  return false
end
-- split shoulders: when "transmog shoulders differently" is on, the left one is its own slot
local function ShoulderSlot(primary)
  local OI, ES = C_TransmogOutfitInfo, Enum.TransmogOutfitSlot
  if ES and primary == ES.ShoulderRight and iv.shoulder == ES.ShoulderLeft and OI.GetSecondarySlotState and OI.GetSecondarySlotState(primary) then
    return ES.ShoulderLeft
  end
  return primary
end
-- the hand that clicking an appearance will change: the one last selected in the window, if this weapon type fits it
local function EffectiveHand(ci)
  local inv = ci[2]
  if ci[1] >= 12 and (iv.hand == 16 or iv.hand == 17) and iv.hand ~= inv and CatFitsHand(ci[1], iv.hand) then inv = iv.hand end
  return inv
end
iv.weapon = FlatButton(iv, "Weapons", 170, 20); AddArrow(iv.weapon)
iv.weapon:SetScript("OnClick", function(self)
  local ws = WeaponCats(); if #ws == 0 then return end
  local items = {}
  for _, w in ipairs(ws) do items[#items+1] = {w[1], w[3]} end
  OpenMenu(self, items, function(v) return v == search.f.cat end, function(v) search.f.cat = v; search.f.page = 1; SearchUpdate() end)
end)
iv.handB = {}
for i, h in ipairs({{16, "Main"}, {17, "Off"}}) do
  local b = FlatButton(iv, h[2], 44, 20)
  if i == 1 then b:SetPoint("LEFT", iv.weapon, "RIGHT", 6, 0) else b:SetPoint("LEFT", iv.handB[16], "RIGHT", 3, 0) end
  b:SetScript("OnClick", function()
    iv.hand = h[1]
    local tf = _G.TransmogFrame
    local _, sf = BlizzSlot(h[1])
    if sf and tf and tf.SelectSlot then iv.selfSelect = true; pcall(tf.SelectSlot, tf, sf); iv.selfSelect = false end
    iv.Refresh()
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(h[1] == 16 and "Apply to the main hand" or "Apply to the off hand"); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  iv.handB[h[1]] = b
end
iv.prev = FlatButton(iv, "<", 24, 20); iv.next = FlatButton(iv, ">", 24, 20)
iv.pageT = Label(iv, "", "GameFontHighlightSmall")
iv.prev:SetScript("OnClick", function() search.f.page = math.max(1, search.f.page - 1); iv.Render() end)
iv.next:SetScript("OnClick", function() search.f.page = search.f.page + 1; iv.Render() end)
iv:EnableMouseWheel(true)
iv:SetScript("OnMouseWheel", function(_, d) search.f.page = math.max(1, search.f.page - d); iv.Render() end)
iv.empty = Label(iv, "", "GameFontDisable"); iv.empty:SetPoint("CENTER")

-- Same call Blizzard's Items tab makes: category + the selected outfit slot's location,
-- so the game itself removes other classes' tier pieces, other specs' artifacts, etc.
local function GetApps(cat, invSlot)
  local list
  local _, sf = BlizzSlot(invSlot)
  if sf and sf.slotData.transmogLocation and sf.slotData.transmogLocation.GetData then
    local ok, l = pcall(C_TransmogCollection.GetCategoryAppearances, cat, sf.slotData.transmogLocation:GetData())
    if ok and type(l) == "table" then list = l end
  end
  if not list then
    local okL, loc = pcall(TransmogUtil.GetTransmogLocation, invSlot, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
    local ok, l = pcall(C_TransmogCollection.GetCategoryAppearances, cat, okL and loc and loc.GetData and loc:GetData() or loc)
    if not (ok and type(l) == "table" and #l > 0) then ok, l = pcall(C_TransmogCollection.GetCategoryAppearances, cat) end
    list = (ok and type(l) == "table") and l or {}
  end
  return list
end

local function UsableHere(a, cat)
  if a.alwaysShowItem then return true end
  if a.isUsable == false then return false end
  if CollectionWardrobeUtil and CollectionWardrobeUtil.IsAppearanceUsable then
    local art = TransmogUtil and TransmogUtil.IsCategoryLegionArtifact and TransmogUtil.IsCategoryLegionArtifact(cat) or false
    local ok, u = pcall(CollectionWardrobeUtil.IsAppearanceUsable, a, art)
    if ok and u == false then return false end
  end
  return true
end

local function SourceFor(visualID)
  local ok, srcs = pcall(C_TransmogCollection.GetAllAppearanceSources, visualID)
  if not ok or not srcs or #srcs == 0 then return end
  local pick
  for _, s in ipairs(srcs) do
    local info = C_TransmogCollection.GetSourceInfo(s)
    if info then
      pick = pick or info
      if info.isCollected then pick = info; break end
    end
  end
  return pick
end

-- Appearance names. The game only knows an item's name once its data has loaded, so ask for it, remember the
-- answer, and redo whatever was waiting when the data arrives. A name search looks at every item sharing the look.
local NAME_CACHE = {}
local function NameInfo(visualID, request)
  local c = NAME_CACHE[visualID]
  if c then return c end
  local ok, srcs = pcall(C_TransmogCollection.GetAllAppearanceSources, visualID)
  if not ok or type(srcs) ~= "table" then return nil, false end
  local show, showOwned, hay, missing = nil, false, {}, false
  for _, sid in ipairs(srcs) do
    local info = C_TransmogCollection.GetSourceInfo(sid)
    if info then
      local nm = info.name
      if IsSecret(nm) then nm = nil end
      if (not nm or nm == "") and info.itemID then
        nm = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID)) or (GetItemInfo and GetItemInfo(info.itemID))
      end
      if nm and nm ~= "" then
        hay[#hay+1] = nm:lower()
        if not show or (info.isCollected and not showOwned) then show = nm; showOwned = info.isCollected and true or false end
      else
        missing = true
        if request and info.itemID and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, info.itemID) end
      end
    end
  end
  if not show then return nil, missing end
  local entry = {show = show, hay = table.concat(hay, "\n")}
  if not missing then NAME_CACHE[visualID] = entry end
  return entry, missing
end
do
  local queued
  local nf = CreateFrame("Frame")
  nf:RegisterEvent("GET_ITEM_INFO_RECEIVED"); pcall(nf.RegisterEvent, nf, "ITEM_DATA_LOAD_RESULT")
  nf:SetScript("OnEvent", function()
    if queued then return end
    queued = true
    C_Timer.After(0.4, function()
      queued = false
      if not search:IsShown() then return end
      local f = search.f
      if UI.tipPending and UI.tipPending:IsMouseOver() and UI.tipPending:GetScript("OnEnter") then UI.tipPending:GetScript("OnEnter")(UI.tipPending) end
      if f.paletteItem and f.paletteName and f.paletteName:find("^Appearance ") then
        local ent = NameInfo(f.paletteItem, true)
        if ent then f.paletteName = ent.show; SearchUpdate() return end
      end
      if f.mode == "items" and (f.text or "") ~= "" then SearchUpdate() end
    end)
  end)
end

-- Put an appearance on the character exactly like Blizzard's Items tab does (pending until you save the outfit).
local pal
local function ApplyToCharacter(e, ci)
  local tf = _G.TransmogFrame
  local cp = tf and tf.CharacterPreview
  local OI = C_TransmogOutfitInfo
  if not (tf and tf:IsShown() and cp and cp.GetSlotFrame and OI and OI.SetPendingTransmog) then
    return false, "Open a transmogrifier to apply appearances."
  end
  local slot = OI.GetTransmogOutfitSlotFromInventorySlot(EffectiveHand(ci) - 1)
  if slot ~= nil then slot = ShoulderSlot(slot) end
  local aType = Enum.TransmogType.Appearance
  local slotFrame = slot ~= nil and cp:GetSlotFrame(slot, aType)
  if not slotFrame or not slotFrame.slotData then return false, "That slot isn't available on this outfit." end
  local sd = slotFrame.slotData

  local option = (Enum.TransmogOutfitSlotOption and Enum.TransmogOutfitSlotOption.None) or 0
  if ci[1] >= 12 then
    local function valid(opt)
      local ok, info = pcall(OI.GetCollectionInfoForSlotAndOption, slot, opt, ci[1])
      return ok and info and info.isWeapon
    end
    local cur = sd.currentWeaponOptionInfo and sd.currentWeaponOptionInfo.weaponOption
    if cur and valid(cur) then option = cur
    else
      local found
      for _, w in ipairs(sd.weaponOptionsInfo or OI.GetWeaponOptionsForSlot(slot) or {}) do
        if w.enabled and valid(w.weaponOption) then found = w.weaponOption; break end
      end
      if not found then return false, "Your character can't use that weapon type in this slot." end
      option = found
      if slotFrame.SetCurrentWeaponOption then pcall(slotFrame.SetCurrentWeaponOption, slotFrame, found) end
    end
  elseif sd.currentWeaponOptionInfo then
    option = sd.currentWeaponOptionInfo.weaponOption
  end

  if cp:GetSelectedSlotData() ~= sd then iv.selfSelect = true; pcall(tf.SelectSlot, tf, slotFrame); iv.selfSelect = false end

  -- pick a collected, usable source for this appearance
  local sourceID
  local okS, sources = pcall(CollectionWardrobeUtil.GetSortedAppearanceSources, e.visualID, ci[1], sd.transmogLocation)
  if okS and sources then
    for _, src in ipairs(sources) do
      local usable = true
      if CollectionWardrobeUtil.IsAppearanceUsable then
        local okU, u = pcall(CollectionWardrobeUtil.IsAppearanceUsable, src, false); if okU then usable = u end
      end
      if src.isCollected and usable then sourceID = src.sourceID; break end
    end
  end
  if not sourceID and e.info and e.info.isCollected then sourceID = e.info.sourceID end
  if not sourceID then return false, "You haven't collected that appearance yet (Ctrl-click to preview it)." end

  local DT = Enum.TransmogOutfitDisplayType
  local displayType = (C_TransmogCollection.IsAppearanceHiddenVisual and C_TransmogCollection.IsAppearanceHiddenVisual(sourceID)) and DT.Hidden or DT.Assigned
  if UI.PushUndo then UI.PushUndo(slot, aType, option) end
  local ok, err = pcall(OI.SetPendingTransmog, slot, aType, option, sourceID, displayType)
  if not ok then return false, "Blizzard rejected the change: "..tostring(err) end
  if SOUNDKIT and SOUNDKIT.UI_TRANSMOG_ITEM_CLICK then PlaySound(SOUNDKIT.UI_TRANSMOG_ITEM_CLICK) end
  return true
end

local function ToggleFavorite(e)
  local new = not e.fav
  local ok = pcall(C_TransmogCollection.SetIsAppearanceFavorite, e.visualID, new)
  if ok then e.fav = new; iv.Render() else UIErrorsFrame:AddMessage("Couldn't change that favorite.", 1, 0.3, 0.3) end
end

-- shift-right-click: save this appearance's full color palette as a sticky filter. It works like the
-- manual color swatch, but matches against the item's whole palette and stays active while you click
-- through slot tabs normally, so each slot's grid narrows to (and ranks) its best matches for that look.
local function SaveColorPalette(e)
  local cd = CM.get(e.visualID)
  if not cd or #cd == 0 then UIErrorsFrame:AddMessage("No color data for that appearance.", 1, 0.3, 0.3); return end
  e.info = e.info or SourceFor(e.visualID)
  local f = search.f
  f.paletteItem = e.visualID
  local nameEnt = NameInfo(e.visualID, true)
  f.paletteName = (nameEnt and nameEnt.show) or (e.info and e.info.name) or ("Appearance "..e.visualID)
  f.page = 1
  SearchUpdate()
end

local function CellClick(self, btn)
  local e = self.entry; if not e then return end
  if btn == "RightButton" then
    if IsShiftKeyDown() then SaveColorPalette(e); return end
    if MenuUtil and MenuUtil.CreateContextMenu then
      MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateButton(e.fav and (_G.TRANSMOG_ITEM_UNSET_FAVORITE or "Remove Favorite") or (_G.TRANSMOG_ITEM_SET_FAVORITE or "Set Favorite"), function() ToggleFavorite(e) end)
        root:CreateButton("Preview", function() local i = e.info or SourceFor(e.visualID); local l = i and i.itemID and select(2, C_Item.GetItemInfo(i.itemID)); if l then Preview({l}) end end)
      end)
    else ToggleFavorite(e) end
    return
  end
  pal = pal or _G.TransmogKitPalette; if pal then pal:Hide() end
  local info = e.info or SourceFor(e.visualID); e.info = info
  local link = info and info.itemID and select(2, C_Item.GetItemInfo(info.itemID))
  if IsShiftKeyDown() and link then
    if not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
  elseif IsControlKeyDown() and link then
    Preview({link})
  else
    local ci = CatInfo(search.f.cat)
    local ok, msg = false, "Unknown slot."
    if ci then ok, msg = ApplyToCharacter(e, ci) end
    if not ok then UIErrorsFrame:AddMessage(msg, 1, 0.3, 0.3) end
  end
end

local function NewCell(i)
  local c = CreateFrame("Button", nil, iv, "BackdropTemplate"); Skin(c, 1)
  c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c.model = CreateFrame("DressUpModel", nil, c)
  c.model:SetPoint("TOPLEFT", 2, -2); c.model:SetPoint("BOTTOMRIGHT", -2, 10)
  c.model:EnableMouse(false)
  pcall(c.model.SetKeepModelOnHide, c.model, true)
  pcall(c.model.SetDoBlend, c.model, false)
  c.sw = {}
  for k = 1, 3 do
    c.sw[k] = c:CreateTexture(nil, "OVERLAY"); c.sw[k]:SetHeight(6)
    c.sw[k]:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 2 + (k-1) * 0, 2)
  end
  c.dim = c:CreateTexture(nil, "OVERLAY"); c.dim:SetAllPoints(c.model); c.dim:SetColorTexture(0, 0, 0, 0.45)
  c.hl = c:CreateTexture(nil, "HIGHLIGHT"); c.hl:SetAllPoints(); c.hl:SetColorTexture(1, 0.82, 0.3, 0.12)
  c.star = c:CreateTexture(nil, "OVERLAY", nil, 7); c.star:SetSize(18, 18); c.star:SetPoint("TOPLEFT", 3, -3)
  c.star:SetAtlas("PetJournal-FavoritesIcon"); c.star:Hide()
  c.slotTxt = Label(c, "", "GameFontHighlightSmall"); c.slotTxt:SetPoint("TOPRIGHT", -3, -3); c.slotTxt:Hide()
  c.slotTxt:SetTextColor(0.4, 1, 0.5)
  c.eye = c:CreateTexture(nil, "OVERLAY", nil, 7); c.eye:SetSize(30, 30); c.eye:SetPoint("CENTER", 0, 8)
  c.eye:SetAtlas("transmog-icon-hidden"); c.eye:Hide()
  c.hideT = Label(c, "Hide this slot", "GameFontHighlightSmall"); c.hideT:SetPoint("BOTTOM", 0, 10); c.hideT:SetTextColor(0.9, 0.4, 1); c.hideT:Hide()
  c.newT = Label(c, "NEW", "GameFontHighlightSmall"); c.newT:SetPoint("BOTTOMLEFT", 5, 5); c.newT:SetTextColor(1, 0.9, 0.3); c.newT:Hide()
  c.cur = c:CreateTexture(nil, "OVERLAY", nil, 6); c.cur:SetPoint("TOPLEFT", -2, 2); c.cur:SetPoint("BOTTOMRIGHT", 2, -2)
  c.cur:SetAtlas("transmog-wardrobe-border-selected"); if not c.cur:GetAtlas() then c.cur:SetColorTexture(0.2, 0.9, 0.3, 0.35) end
  c.cur:SetBlendMode("ADD"); c.cur:Hide()
  c:SetScript("OnClick", CellClick)
  c:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(1, 0.82, 0.3, 1)
    local e = self.entry; if not e then return end
    if e.new then pcall(C_TransmogCollection.ClearNewAppearance, e.visualID); e.new = false; self.newT:Hide() end
    e.info = e.info or SourceFor(e.visualID)
    local nameEnt = (not e.hide) and NameInfo(e.visualID, true)
    UI.tipPending = ((not e.hide) and not nameEnt) and self or nil
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(e.hide and "Hide this slot" or (nameEnt and nameEnt.show) or (e.info and e.info.name) or ("Appearance "..e.visualID))
    if e.hide then GameTooltip:AddLine("Makes whatever is in this slot invisible.", 0.9, 0.4, 1) end
    local cd = CM.get(e.visualID)
    if cd and cd.exp and EXPANSIONS[cd.exp] then GameTooltip:AddLine(EXPANSIONS[cd.exp], 0.7, 0.7, 0.7) end
    if e.pct then GameTooltip:AddLine(("Palette match: %d%%"):format(e.pct), 0.4, 1, 0.5) end
    GameTooltip:AddLine("Click: put it on your character", 1, 1, 1)
    GameTooltip:AddLine("Ctrl-click: preview   Shift-click: link", 1, 1, 1)
    GameTooltip:AddLine("Right-click: favorite   Shift-Right: save its palette to compare", 1, 1, 1)
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.9); GameTooltip:Hide() end)
  iv.cells[i] = c
  return c
end

local function ApplyModel(m, e, isWeapon)
  if m.applying then return end -- OnModelLoaded fires from inside SetItemAppearance/TryOn
  m.applying = true
  pcall(function()
    if isWeapon and m.SetItemAppearance then
      m:SetItemAppearance(e.visualID)
    else
      m:Undress()
      if e.info and e.info.sourceID then m:TryOn(e.info.sourceID) end
    end
    local cam = C_TransmogCollection.GetAppearanceCameraID and C_TransmogCollection.GetAppearanceCameraID(e.visualID)
    if cam and cam > 0 and Model_ApplyUICamera then Model_ApplyUICamera(m, cam) end
  end)
  m.applying = false
end

local function LoadModel(c, e)
  local m = c.model
  e.info = e.info or SourceFor(e.visualID)
  local ci = CatInfo(search.f.cat)
  local isWeapon = ci and ci[1] >= 12
  m.pendingEntry, m.pendingWeapon = e, isWeapon
  if not m.loadHooked then
    m:SetScript("OnModelLoaded", function(self) if self.pendingEntry then ApplyModel(self, self.pendingEntry, self.pendingWeapon) end end)
    m.loadHooked = true
  end
  if isWeapon then m.hasUnit = false; ApplyModel(m, e, true) return end
  if not m.hasUnit then
    m.hasUnit = true; pcall(m.SetUnit, m, "player", false)
    C_Timer.After(0.25, function() if m.pendingEntry == e then ApplyModel(m, e, false) end end)
    return
  end
  ApplyModel(m, e, false)
end

function iv.Render()
  local W, H = iv:GetWidth(), iv:GetHeight()
  if not W or W < 50 then W, H = 314, 480 end
  local cw, ch, gap, top = 92, 120, 6, iv.topOffset or 50
  local cols = math.max(2, math.floor((W + gap) / (cw + gap)))
  local rows = math.max(1, math.floor((H - top + gap) / (ch + gap)))
  cw = math.floor((W - (cols - 1) * gap) / cols)
  local per = cols * rows
  if iv.jumpTo then
    for idx, d in ipairs(iv.data) do
      if d.visualID == iv.jumpTo then search.f.page = math.ceil(idx / per); break end
    end
    iv.jumpTo = nil
  end
  local pages = math.max(1, math.ceil(#iv.data / per))
  if search.f.page > pages then search.f.page = pages end
  local off = (search.f.page - 1) * per
  iv.pageT:SetText("Page "..search.f.page.." / "..pages)
  for i = 1, math.max(per, #iv.cells) do
    local c = iv.cells[i]
    local e = i <= per and iv.data[off + i]
    if e then
      c = c or NewCell(i)
      local r, col = math.floor((i - 1) / cols), (i - 1) % cols
      c:SetSize(cw, ch); c:ClearAllPoints(); c:SetPoint("TOPLEFT", iv, "TOPLEFT", col * (cw + gap), -top - r * (ch + gap))
      if c.entry ~= e then c.entry = e; if not e.hide then LoadModel(c, e) else c.model.pendingEntry = nil end end
      c.model:SetShown(not e.hide); c.eye:SetShown(e.hide and true or false); c.hideT:SetShown(e.hide and true or false)
      c.dim:SetShown(not e.collected)
      c.star:SetShown(e.fav and true or false)
      if e.pct then c.slotTxt:SetText(e.pct.."%"); c.slotTxt:Show() else c.slotTxt:Hide() end
      c.newT:SetShown(e.new and true or false)
      if c.cur then c.cur:SetShown(e.visualID == iv.current) end
      local cd = CM.get(e.visualID)
      local x = 2
      for k = 1, 3 do
        local s = cd and cd[k]
        if s then
          local w = math.max(4, math.floor((cw - 4) * s[4] / 9))
          c.sw[k]:ClearAllPoints(); c.sw[k]:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", x, 2)
          c.sw[k]:SetWidth(w); c.sw[k]:SetColorTexture(s[5], s[6], s[7], 1); c.sw[k]:Show(); x = x + w
        else c.sw[k]:Hide() end
      end
      c:Show()
    elseif c then c.entry = nil; c:Hide() end
  end
  iv.empty:SetText(#iv.data == 0 and (TransmogKitColorData and "No appearances match these filters." or "Color data file missing.") or "")
end

function iv.Refresh()
  local f = search.f
  if f.cat == nil then f.cat = 1 end
  local ci = CatInfo(f.cat) or ARMOR[1]
  for i, a in ipairs(ARMOR) do
    local b = iv.slotButtons[i]
    local on = a[1] == f.cat
    b:SetBackdropColor(on and 0.35 or 0.06, on and 0.27 or 0.06, on and 0.1 or 0.08, 1)
  end
  iv.weapon:SetLabel(ci[1] >= 12 and ("|cffffd100"..ci[3].."|r") or "Weapons")
  do
    local isW = ci[1] >= 12
    local eff = isW and EffectiveHand(ci)
    for h, b in pairs(iv.handB) do
      local fits = isW and CatFitsHand(ci[1], h)
      b:SetShown(fits and true or false)
      b:SetBackdropColor(eff == h and 0.35 or 0.06, eff == h and 0.27 or 0.06, eff == h and 0.1 or 0.08, 1)
    end
  end
  wipe(iv.data)
  local q, tol = f.color, TOLS[f.tol][2]
  local txt, unresolved = f.text or "", 0
  local qInfo, need
  if f.paletteItem then qInfo = CM.get(f.paletteItem)
  elseif f.multi and #f.multi > 0 then qInfo, need = CM.multiInfo(f.multi); if f.multiNeed then need = f.multiNeed end end
  local apps = GetApps(ci[1], EffectiveHand(ci))
  -- the game sometimes hands back an empty list right after a slot change; ask again shortly
  if #apps == 0 and (iv.retries or 0) < 8 then
    iv.retries = (iv.retries or 0) + 1
    C_Timer.After(0.15, function() if iv:IsShown() and search.f.mode == "items" then iv.Refresh() end end)
  elseif #apps > 0 then iv.retries = 0 end
  for _, a in ipairs(apps) do
    if a.visualID ~= f.paletteItem and a.isValidAppearanceForPlayer ~= false and (a.isHideVisual or UsableHere(a, ci[1])) then
      local cd = CM.get(a.visualID)
      local ok = a.isCollected and (f.coll ~= 4 or a.isFavorite)
        and (a.isHideVisual or f.exp == -1 or (cd and cd.exp == f.exp))
      if ok and txt ~= "" then
        if a.isHideVisual then ok = false
        else
          local ent, missing = NameInfo(a.visualID, true)
          if not (ent and ent.hay:find(txt, 1, true)) then
            ok = false
            if missing then unresolved = unresolved + 1 end
          end
        end
      end
      local score, pct = 0, nil
      if ok and qInfo then
        if cd then local pass, s, p = CM.itemDist(cd, qInfo, tol, need); ok = pass; score, pct = s, p
        else ok = false end
      elseif ok and q then
        if cd then local d, s = CM.dist(cd, q); ok = d <= tol; score = s
        else ok = false end
      end
      if ok then
        local isNew = C_TransmogCollection.IsNewAppearance and C_TransmogCollection.IsNewAppearance(a.visualID) or false
        iv.data[#iv.data+1] = {visualID = a.visualID, collected = a.isCollected, fav = a.isFavorite, new = isNew and true or false, hide = a.isHideVisual and true or false, score = score, pct = pct, exp = cd and cd.exp or 99, order = #iv.data}
      end
    end
  end
  if qInfo or q then table.sort(iv.data, function(x, y) if x.score ~= y.score then return x.score < y.score end return x.order < y.order end)
  else table.sort(iv.data, function(x, y)
    if (x.hide and 1 or 0) ~= (y.hide and 1 or 0) then return x.hide and true or false end
    if (x.fav and 1 or 0) ~= (y.fav and 1 or 0) then return x.fav and true or false end
    if (x.new and 1 or 0) ~= (y.new and 1 or 0) then return x.new and true or false end
    if x.exp ~= y.exp then return x.exp > y.exp end return x.visualID > y.visualID end) end
  countT:SetText(#iv.data..(qInfo and " matches" or " appearances")..(unresolved > 0 and ("  |cff888888(loading "..unresolved.." names...)|r") or ""))
  iv.Render()
  if UI.RefreshSheath then UI.RefreshSheath() end
  if UI.RefreshShoulder then UI.RefreshShoulder() end
end
iv:SetScript("OnSizeChanged", function() if iv:IsShown() then iv.Render() end end)

---- color palette popup
pal = CreateFrame("Frame", "TransmogKitPalette", UIParent, "BackdropTemplate"); Skin(pal, 1)
pal:SetFrameStrata("FULLSCREEN_DIALOG"); pal:SetFixedFrameStrata(true); pal:SetToplevel(true); pal:SetFrameLevel(500); pal:SetClampedToScreen(true); pal:SetSize(12 * 20 + 16, 5 * 20 + 148); pal:Hide(); pal:EnableMouse(true)
pal.title = Label(pal, "Pick a color", "GameFontNormalSmall"); pal.title:SetPoint("TOPLEFT", 8, -6)
local function SetQuery(r, g, b)
  search.f.paletteItem = nil; search.f.paletteName = nil; search.f.multi = nil; search.f.themeName = nil; search.f.multiNeed = nil
  if not r then search.f.color = nil
  else local L, A, B = CM.lab(r * 255, g * 255, b * 255); search.f.color = {L, A, B, r = r, g = g, b = b} end
  search.f.page = 1; SearchUpdate()
end
local TONES = {{0.35, 1.0}, {0.85, 0.95}, {0.85, 0.62}, {0.75, 0.35}}
local swatchIdx = 0
local swatches = {}
local function SameColor(a, r, g, b) return math.abs(a[1] - r) < 0.002 and math.abs(a[2] - g) < 0.002 and math.abs(a[3] - b) < 0.002 end
-- multi-select: build a set of up to 8 colors; items must contain all of them (or all but one when 3+)
local function ToggleMulti(r, g, b)
  local f = search.f
  if not f.multi then
    f.multi = {}
    if f.color then f.multi[1] = {f.color.r, f.color.g, f.color.b} end
  end
  local found
  for i, c in ipairs(f.multi) do if SameColor(c, r, g, b) then found = i; break end end
  if found then table.remove(f.multi, found) elseif #f.multi < 8 then f.multi[#f.multi + 1] = {r, g, b} end
  if #f.multi == 0 then f.multi = nil end
  f.themeName = nil; f.multiNeed = nil; f.color = nil; f.paletteItem = nil; f.paletteName = nil
  f.page = 1; SearchUpdate(); pal.Refresh()
end
local function Swatch(r, g, b, x, y)
  swatchIdx = swatchIdx + 1
  local s = CreateFrame("Button", nil, pal); s:SetSize(18, 18); s:SetPoint("TOPLEFT", 8 + x * 20, -22 - y * 20)
  s.sel = s:CreateTexture(nil, "BACKGROUND"); s.sel:SetPoint("TOPLEFT", -2, 2); s.sel:SetPoint("BOTTOMRIGHT", 2, -2); s.sel:SetColorTexture(1, 1, 1, 1); s.sel:Hide()
  s.t = s:CreateTexture(nil, "ARTWORK"); s.t:SetAllPoints(); s.t:SetColorTexture(r, g, b, 1)
  s.r, s.g, s.b = r, g, b
  s:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  s:SetScript("OnClick", function()
    if pal.multiOn or IsShiftKeyDown() then ToggleMulti(r, g, b) else SetQuery(r, g, b); pal:Hide() end
  end)
  swatches[#swatches + 1] = s
end
for y, tone in ipairs(TONES) do
  for x = 0, 11 do local r, g, b = CM.hsv(x / 12, tone[1], tone[2]); Swatch(r, g, b, x, y - 1) end
end
for x = 0, 11 do local v = 1 - x / 11; Swatch(v, v, v, x, 4) end
pal.tolT = Label(pal, "Match:", "GameFontDisableSmall"); pal.tolT:SetPoint("TOPLEFT", 8, -128)
pal.tols = {}
for i, t in ipairs(TOLS) do
  local b = FlatButton(pal, t[1], 56, 18); b:SetPoint("TOPLEFT", 8 + (i - 1) * 60, -142)
  b:SetScript("OnClick", function() search.f.tol = i; search.f.page = 1; SearchUpdate(); pal.Refresh() end)
  pal.tols[i] = b
end
-- common transmog looks: name, then the colors an appearance should contain
local THEMES = {
  {"Black & Gold", "1c1c1c", "d4af37"}, {"Red & Black", "a31919", "1c1c1c"}, {"Crimson & Gold", "a31919", "d4af37"},
  {"Purple & Gold", "5a2a8a", "d4af37"}, {"Royal Blue & Gold", "1e3a8a", "d4af37"}, {"Green & Gold", "2f6a2f", "d4af37"},
  {"Holy White & Gold", "f2f0e6", "d4af37"}, {"Orange & Black", "e07a1a", "1c1c1c"}, {"Silver & Steel", "b8bcc4", "5a6270"},
  {"Blue & Silver", "2a5bd0", "b8bcc4"}, {"Frost", "8ed1f5", "dfe9f2", "3a6ea5"}, {"Arcane", "5a8af0", "a06ae0"},
  {"Ocean & Sand", "1f7f8f", "d8d2b8"}, {"Shadow & Void", "6a3aa8", "1c1c22"}, {"Fel Green & Black", "4fd64f", "1c1c1c"},
  {"Fire & Ember", "d8401a", "f0a020", "1c1c1c"}, {"Bone & Rot", "d8d2b8", "3f5a3a"}, {"Nature", "3a7a30", "7a5a30"},
  {"Bronze & Copper", "a86a3a", "6a4a2a"}, {"Rose & Ivory", "e88ab8", "f2f0e6"}, {"All Black", "1c1c1c", "2e2e33"},
  {"White & Silver", "f2f0e6", "c8c8cc"},
}
local function HexRGB(h) return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 end
local function ApplyTheme(t)
  local f = search.f
  f.multi = {}
  for i = 2, #t do local r, g, b = HexRGB(t[i]); f.multi[#f.multi + 1] = {r, g, b} end
  f.themeName = t[1]; f.multiNeed = nil; f.color = nil; f.paletteItem = nil; f.paletteName = nil
  f.page = 1; SearchUpdate()
end
function pal.Refresh()
  local f = search.f
  for i, b in ipairs(pal.tols) do
    b:SetBackdropColor(i == f.tol and 0.35 or 0.06, i == f.tol and 0.27 or 0.06, i == f.tol and 0.1 or 0.08, 1)
  end
  for _, s in ipairs(swatches) do
    local on = false
    for _, c in ipairs(f.multi or {}) do if SameColor(c, s.r, s.g, s.b) then on = true; break end end
    s.sel:SetShown(on)
  end
  pal.multiBtn:SetLabel(pal.multiOn and "|cff55ff55Multi-select: ON|r" or "Multi-select: off")
  pal.multiBtn:SetBackdropColor(pal.multiOn and 0.35 or 0.06, pal.multiOn and 0.27 or 0.06, pal.multiOn and 0.1 or 0.08, 1)
  pal.title:SetText(pal.multiOn and "Click swatches to add / remove" or ((f.paletteItem or (f.multi and #f.multi > 0)) and "Match settings" or "Pick a color"))
end
pal.multiBtn = FlatButton(pal, "Multi-select: off", 118, 20); pal.multiBtn:SetPoint("TOPLEFT", 8, -166)
pal.multiBtn:SetScript("OnClick", function() pal.multiOn = not pal.multiOn; pal.Refresh() end)
pal.themeBtn = FlatButton(pal, "Themes", 118, 20); pal.themeBtn:SetPoint("TOPLEFT", 132, -166); AddArrow(pal.themeBtn)
pal.outfitBtn = FlatButton(pal, "Match my outfit's colors", 242, 20); pal.outfitBtn:SetPoint("TOPLEFT", 8, -192)
pal.outfitBtn:SetScript("OnClick", function() if UI.UseOutfitPalette and UI.UseOutfitPalette() then pal:Hide() end end)
pal.themeBtn:SetScript("OnClick", function()
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  pal:Hide()
  MenuUtil.CreateContextMenu(UI.color, function(_, root)
    if root.SetScrollMode then root:SetScrollMode(420) end
    for _, t in ipairs(THEMES) do root:CreateButton(t[1], function() ApplyTheme(t) end) end
  end)
end)
pal.custom = FlatButton(pal, "Custom shade...", 120, 20); pal.custom:SetPoint("BOTTOMLEFT", 8, 8)
pal.custom:SetScript("OnClick", function()
  pal:Hide()
  local c = search.f.color or {r = 0.5, g = 0.5, b = 0.5}
  local info = {r = c.r, g = c.g, b = c.b, hasOpacity = false,
    swatchFunc = function() local r, g, b = ColorPickerFrame:GetColorRGB(); SetQuery(r, g, b) end,
    cancelFunc = function() end}
  if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then ColorPickerFrame:SetupColorPickerAndShow(info) end
end)
pal.clear = FlatButton(pal, "Any color", 100, 20); pal.clear:SetPoint("BOTTOMRIGHT", -8, 8)
pal.clear:SetScript("OnClick", function() SetQuery(nil); pal:Hide() end)
UI.color:HookScript("OnEnter", function(self)
  local f = search.f
  local txt = (f.paletteItem and f.paletteName) or (f.multi and #f.multi > 0 and ((f.themeName or "Custom colors").." ("..#f.multi.." colors)"))
  if txt then
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(txt, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end
end)
UI.color:HookScript("OnLeave", function() GameTooltip:Hide() end)
UI.color:SetScript("OnClick", function()
  if pal:IsShown() then pal:Hide() else
    pal:ClearAllPoints(); pal:SetPoint("TOPLEFT", UI.color, "BOTTOMLEFT", 0, -2); pal.Refresh(); pal:Show(); pal:Raise()
  end
end)

---- layout per mode
local function LayoutMode()
  local mounts = search.f.mode == "mounts"
  local effects = search.f.mode == "effects"
  local more = search.f.mode == "more"
  local special = mounts or effects or more
  for _, w in ipairs({sBox, UI.type, UI.tier, UI.items, sScroll, UI.exp, UI.coll, UI.color}) do w:SetShown(not special) end
  if UI.mv then UI.mv:SetShown(mounts) end
  if UI.ev then UI.ev:SetShown(effects) end
  if UI.sv then UI.sv:SetShown(more) end
  UI.modeMore:SetBackdropColor(more and 0.35 or 0.06, more and 0.27 or 0.06, more and 0.1 or 0.08, 1)
  UI.modeMounts:SetBackdropColor(mounts and 0.35 or 0.06, mounts and 0.27 or 0.06, mounts and 0.1 or 0.08, 1)
  UI.modeEffects:SetBackdropColor(effects and 0.35 or 0.06, effects and 0.27 or 0.06, effects and 0.1 or 0.08, 1)
  if special then
    for _, r in ipairs(search.rows) do r:Hide() end
    iv:Hide(); UI.nameBox:Hide()
    if UI.RefreshSheath then UI.RefreshSheath() end
    if UI.RefreshShoulder then UI.RefreshShoulder() end
    UI.help:SetText(mounts and "Hover: preview on your character   Click: assign to this outfit" or (more and "Settings, sharing and tools" or "Click: apply the effect   Right-click: favorite"))
    UI.modeItems:SetBackdropColor(0.06, 0.06, 0.08, 1); UI.modeSets:SetBackdropColor(0.06, 0.06, 0.08, 1)
    return
  end
  local items = search.f.mode == "items"
  for _, w in ipairs({sBox, UI.type, UI.tier, UI.items, sScroll}) do w:SetShown(not items) end
  for _, r in ipairs(search.rows) do if items then r:Hide() end end
  iv:SetShown(items)
  for _, w in ipairs({UI.exp, UI.coll, UI.color, UI.items, UI.type, UI.tier, sBox, UI.nameBox}) do w:ClearAllPoints() end
  UI.nameBox:SetShown(items)
  if items then
    local paletteRow = search.f.paletteItem ~= nil or (search.f.multi ~= nil and #search.f.multi > 0)
    UI.exp:SetPoint("TOPLEFT", 12, -30); UI.coll:SetPoint("LEFT", UI.exp, "RIGHT", 6, 0)
    if paletteRow then
      UI.color:SetPoint("TOPLEFT", 12, -56); UI.color:SetPoint("TOPRIGHT", -12, -56)
      UI.color.text:SetWidth(UI.color:GetWidth() - 16); UI.color.text:SetWordWrap(false)
    else
      UI.color:SetPoint("LEFT", UI.coll, "RIGHT", 6, 0)
      UI.color.text:SetWidth(0); UI.color.text:SetWordWrap(true)
    end
    local W0 = search:GetWidth() or 330
    local extra = 0
    if W0 >= 560 then
      local anchor = paletteRow and UI.coll or UI.color
      local used = paletteRow and (12 + 150 + 6 + 100) or (12 + 150 + 6 + 100 + 6 + 100)
      UI.nameBox:SetPoint("LEFT", anchor, "RIGHT", 12, 0); UI.nameBox:SetWidth(math.max(120, math.min(260, W0 - used - 34)))
    else
      local y = paletteRow and -82 or -56
      UI.nameBox:SetPoint("TOPLEFT", 18, y); UI.nameBox:SetPoint("TOPRIGHT", -12, y)
      extra = 26
    end
    iv:ClearAllPoints(); iv:SetPoint("TOPLEFT", 8, (paletteRow and -84 or -60) - extra); iv:SetPoint("BOTTOMRIGHT", -8, 26)
    -- slot bar
    local W = iv:GetWidth(); if not W or W < 50 then W = 314 end
    local perRow = math.max(4, math.floor((W + 3) / 43))
    for i, b in ipairs(iv.slotButtons) do
      b:ClearAllPoints()
      local r, c = math.floor((i - 1) / perRow), (i - 1) % perRow
      if r > 0 and perRow < #ARMOR then
        -- second row sits next to the weapon button's row
      end
      b:SetPoint("TOPLEFT", iv, "TOPLEFT", c * 43, -r * 24)
    end
    local rowsUsed = math.ceil(#ARMOR / perRow)
    iv.weapon:ClearAllPoints(); iv.weapon:SetPoint("TOPLEFT", iv, "TOPLEFT", 0, -rowsUsed * 24)
    iv.next:ClearAllPoints(); iv.next:SetPoint("TOPRIGHT", iv, "TOPRIGHT", 0, -rowsUsed * 24)
    iv.pageT:ClearAllPoints(); iv.pageT:SetPoint("RIGHT", iv.next, "LEFT", -6, 0)
    iv.prev:ClearAllPoints(); iv.prev:SetPoint("RIGHT", iv.pageT, "LEFT", -6, 0)
    iv.topOffset = (rowsUsed + 1) * 24 + 4
    UI.help:SetText("Click: apply to character   Ctrl: preview   Shift: link   Shift-Right: save palette")
  else
    sBox:SetPoint("TOPLEFT", 18, -30); sBox:SetPoint("TOPRIGHT", -12, -30)
    UI.exp:SetPoint("TOPLEFT", 12, -58); UI.type:SetPoint("LEFT", UI.exp, "RIGHT", 6, 0); UI.tier:SetPoint("LEFT", UI.type, "RIGHT", 6, 0)
    UI.coll:SetPoint("TOPLEFT", UI.exp, "BOTTOMLEFT", 0, -6); UI.color:SetPoint("LEFT", UI.coll, "RIGHT", 6, 0)
    UI.items:SetPoint("LEFT", UI.color, "RIGHT", 6, 0)
    UI.help:SetText("Click: show in window   Ctrl: preview   Shift: link")
  end
  UI.modeItems:SetBackdropColor(items and 0.35 or 0.06, items and 0.27 or 0.06, items and 0.1 or 0.08, 1)
  UI.modeSets:SetBackdropColor(items and 0.06 or 0.35, items and 0.06 or 0.27, items and 0.08 or 0.1, 1)
end

function SearchUpdate()
  local f = search.f
  if f.coll ~= 2 and f.coll ~= 4 then f.coll = 2 end
  LayoutMode()
  UI.exp:SetLabel("Expansion: "..(f.exp == -1 and "Any" or EXPANSIONS[f.exp] or f.exp))
  UI.type:SetLabel(TYPE_OPTS[f.type]); UI.tier:SetLabel(f.tier and "|cff55ff55Tier only|r" or "Tier: any")
  UI.coll:SetLabel(COLL_OPTS[f.coll])
  local q = f.color
  local nm = f.multi and #f.multi or 0
  for _, t in ipairs(UI.color.ms) do t:Hide() end
  if f.paletteItem then
    UI.color:SetLabel("|cffffd100Like: "..(f.paletteName or "item").."|r")
    UI.color.swatch:SetShown(false)
  elseif nm > 0 then
    UI.color:SetLabel("|cffffd100"..(f.themeName and ("Theme: "..f.themeName) or ("Colors: "..nm)).."|r")
    UI.color.swatch:SetShown(false)
    for i, c in ipairs(f.multi) do local t = UI.color.ms[i]; t:SetColorTexture(c[1], c[2], c[3], 1); t:Show() end
  else
    UI.color:SetLabel(q and ("    "..TOLS[f.tol][1]) or "Color: any")
    UI.color.swatch:SetShown(q ~= nil); if q then UI.color.swatch:SetColorTexture(q.r, q.g, q.b, 1) end
  end
  if f.mode == "mounts" then if UI.mv then UI.mv.Refresh() end countT:SetText("") return end
  if f.mode == "effects" then if UI.ev then UI.ev.Refresh() end countT:SetText("") return end
  if f.mode == "more" then if UI.sv then UI.sv.Refresh() end countT:SetText("") return end
  if f.mode == "items" then iv.Refresh() return end

  local txt = (sBox:GetText() or ""):lower()
  sBox.hint:SetShown(txt == "" and not sBox:HasFocus())
  wipe(search.data)
  local tol = TOLS[f.tol][2]
  for _, e in ipairs(LoadSets()) do
    local ok = (f.exp == -1 or e.exp == f.exp)
      and (f.type == 1 or (f.type == 2 and not e.pvp) or (f.type == 3 and e.pvp))
      and (not f.tier or e.tier)
      and (e.total > 0 and e.have == e.total) and (f.coll ~= 4 or e.fav)
      and (txt == "" or e.name:lower():find(txt, 1, true) or (e.label or ""):lower():find(txt, 1, true))
    if ok and q then local m, frac = SetColorMatch(e, q, tol); ok = m; e.cfrac = frac end
    if ok then search.data[#search.data+1] = e end
  end
  if q then table.sort(search.data, function(a, b) if (a.cfrac or 0) ~= (b.cfrac or 0) then return (a.cfrac or 0) > (b.cfrac or 0) end return a.name < b.name end) end
  countT:SetText(#search.data.." sets")
  FauxScrollFrame_Update(sScroll, #search.data, SROWS, SROW_H)
  local off = FauxScrollFrame_GetOffset(sScroll)
  for r = 1, MAX_ROWS do
    local e, row = r <= SROWS and search.data[off + r], search.rows[r]
    if e then
      row.entry = e; row.icon:SetTexture(e.icon); row.name:SetText(e.name)
      local sub = {}
      if e.label then sub[#sub+1] = e.label end
      if e.desc and e.desc ~= "" then sub[#sub+1] = e.desc end
      if e.pvp then sub[#sub+1] = "|cffff6666PvP|r" elseif e.tier then sub[#sub+1] = "|cff66ccffTier|r" end
      row.sub:SetText(table.concat(sub, " - "))
      local done = e.total > 0 and e.have == e.total
      row.prog:SetText((e.fav and "|A:PetJournal-FavoritesIcon:14:14|a " or "")..(done and "|cff55ff55" or "|cffaaaaaa")..e.have.."/"..e.total.."|r")
      row:Show()
    else row.entry = nil; row:Hide() end
  end
end

-- Clicking a slot on Blizzard's character jumps the Finder to that slot and the look it's wearing now,
-- the same way Blizzard's Items tab does.
local function SyncFinderToSlot(slotData)
  if iv.selfSelect or not search:IsShown() then return end
  local loc = slotData and slotData.transmogLocation
  if not (loc and loc.GetSlotID) then return end
  if loc.IsIllusion and loc:IsIllusion() then
    -- the effect box next to a weapon: show the Effects tab for that hand
    local invSlot = loc:GetSlotID()
    if UI.ev and (invSlot == 16 or invSlot == 17) then UI.ev.hand = invSlot end
    if UI.ev then UI.ev.page = 1 end
    search.f.mode = "effects"; SearchUpdate()
    return
  end
  if search.f.mode == "effects" then search.f.mode = "items" end
  if search.f.mode ~= "items" then return end
  if loc.IsAppearance and not loc:IsAppearance() then return end
  local inv = loc:GetSlotID()
  if inv == 16 or inv == 17 then iv.hand = inv end
  do
    local ES = Enum.TransmogOutfitSlot
    local so = loc.GetSlot and loc:GetSlot()
    if ES and (so == ES.ShoulderLeft or so == ES.ShoulderRight) then iv.shoulder = so end
  end
  local src
  local opt = slotData.currentWeaponOptionInfo and slotData.currentWeaponOptionInfo.weaponOption or 0
  local okI, info = pcall(C_TransmogOutfitInfo.GetViewedOutfitSlotInfo, loc:GetSlot(), loc:GetType(), opt)
  if okI and info and info.transmogID and info.transmogID ~= 0 and info.displayType == Enum.TransmogOutfitDisplayType.Assigned then src = info.transmogID end
  if not src and TransmogUtil and TransmogUtil.GetInfoForEquippedSlot then
    local okE, ei = pcall(TransmogUtil.GetInfoForEquippedSlot, loc)
    if okE and ei then
      src = (ei.selectedSourceID and ei.selectedSourceID ~= 0 and ei.selectedSourceID) or (ei.appliedSourceID ~= 0 and ei.appliedSourceID) or ei.baseSourceID
    end
  end
  local visual, cat
  if src and src ~= 0 then
    local okS, si = pcall(C_TransmogCollection.GetSourceInfo, src)
    if okS and si then visual = si.visualID; cat = si.categoryID end
  end
  local target
  for _, a in ipairs(ARMOR) do if a[2] == inv then target = a[1] end end
  if not target and (inv == 16 or inv == 17) then
    local ws = WeaponCats()
    for _, w in ipairs(ws) do if w[1] == cat then target = cat end end
    if not target then for _, w in ipairs(ws) do if w[2] == inv then target = w[1]; break end end end
  end
  if not target then return end
  iv.current = visual
  if visual and search.f.coll ~= 2 and search.f.coll ~= 4 then search.f.coll = 2 end
  search.f.cat = target; search.f.page = 1; iv.jumpTo = visual; iv.retries = 0
  SearchUpdate()
  C_Timer.After(0.1, function() if search:IsShown() and search.f.mode == "items" and #iv.data == 0 then iv.jumpTo = visual; iv.Refresh() end end)
end
local function HookSlotSelect()
  if iv.hooked or not (_G.TransmogFrame and _G.TransmogFrame.SelectSlot) then return end
  iv.hooked = true
  hooksecurefunc(_G.TransmogFrame, "SelectSlot", function(_, slotFrame) if slotFrame then SyncFinderToSlot(slotFrame.slotData) end end)
end
search:HookScript("OnShow", function()
  HookSlotSelect()
  local cp = _G.TransmogFrame and _G.TransmogFrame.CharacterPreview
  if cp and cp.GetSelectedSlotData then
    local ok, sd = pcall(cp.GetSelectedSlotData, cp)
    if ok and sd then C_Timer.After(0, function() pcall(SyncFinderToSlot, sd) end) end
  end
end)

sScroll:SetScript("OnVerticalScroll", function(self, o) FauxScrollFrame_OnVerticalScroll(self, o, SROW_H, SearchUpdate) end)
sBox:SetScript("OnTextChanged", SearchUpdate)
sBox:SetScript("OnEditFocusGained", SearchUpdate); sBox:SetScript("OnEditFocusLost", SearchUpdate)
sBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
local function cycle(v, lo, hi, dir) v = v + dir; if v > hi then v = lo elseif v < lo then v = hi end; return v end
UI.exp:SetScript("OnClick", function(self)
  local items = {{-1, "Any expansion"}}
  for i = #EXPANSIONS, 0, -1 do items[#items+1] = {i, EXPANSIONS[i]} end
  OpenMenu(self, items, function(v) return v == search.f.exp end, function(v) search.f.exp = v; search.f.page = 1; SearchUpdate() end)
end)
UI.type:SetScript("OnClick", function(self)
  local items = {}; for i, n in ipairs(TYPE_OPTS) do items[i] = {i, n} end
  OpenMenu(self, items, function(v) return v == search.f.type end, function(v) search.f.type = v; SearchUpdate() end)
end)
UI.coll:SetScript("OnClick", function(self)
  local items = {{2, "Collected"}, {4, "Favorites"}}
  OpenMenu(self, items, function(v) return v == search.f.coll end, function(v) search.f.coll = v; search.f.page = 1; SearchUpdate() end)
end)
UI.tier:SetScript("OnClick", function() search.f.tier = not search.f.tier; SearchUpdate() end)
UI.items:SetScript("OnClick", function()
  if not PushSearch("ItemsFrame", _G.WARDROBE_ITEMS or "Items", 1, sBox:GetText() or "") then Print("Open the transmog window first.") end
end)
UI.modeItems:SetScript("OnClick", function() search.f.mode = "items"; SearchUpdate() end)
UI.modeSets:SetScript("OnClick", function() search.f.mode = "sets"; SearchUpdate() end)
UI.modeMounts:SetScript("OnClick", function() search.f.mode = "mounts"; SearchUpdate() end)
UI.modeEffects:SetScript("OnClick", function() search.f.mode = "effects"; SearchUpdate() end)
UI.modeMore:SetScript("OnClick", function() search.f.mode = "more"; SearchUpdate() end)
search:SetScript("OnShow", function() search.cache = nil; SearchUpdate() end)
search:SetScript("OnHide", function() pal:Hide() end)


---------------------------------------------------------------- Finder: Mounts tab (per-outfit mounts + hearth)
do
  local mv = CreateFrame("Frame", "TransmogKitMountView", search); UI.mv = mv
  mv:SetPoint("TOPLEFT", 12, -30); mv:SetPoint("BOTTOMRIGHT", -12, 26); mv:Hide()
  mv.kind = "ground"; mv.page = 1; mv.data = {}; mv.rows = {}
  local KINDS = {{"ground", "Ground"}, {"flying", "Flying"}, {"swimming", "Swim"}, {"hearth", "Hearth"}}
  mv.kindB = {}
  for i, k in ipairs(KINDS) do
    local b = FlatButton(mv, k[2], 70, 22); b:SetPoint("TOPLEFT", (i - 1) * 74, 0)
    b:SetScript("OnClick", function() mv.kind = k[1]; mv.page = 1; mv.Refresh() end)
    mv.kindB[k[1]] = b
  end
  mv.box = CreateFrame("EditBox", nil, mv, "InputBoxTemplate"); mv.box:SetSize(170, 20); mv.box:SetAutoFocus(false)
  mv.box:SetPoint("TOPLEFT", 6, -30)
  mv.box:SetScript("OnTextChanged", function() mv.page = 1; mv.Refresh() end)
  mv.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  mv.all = CreateFrame("CheckButton", nil, mv, "UICheckButtonTemplate"); mv.all:SetSize(22, 22)
  mv.all:SetPoint("LEFT", mv.box, "RIGHT", 6, 0); mv.all:SetScript("OnClick", function() mv.page = 1; mv.Refresh() end)
  mv.allT = Label(mv.all, "All types", "GameFontHighlightSmall"); mv.allT:SetPoint("LEFT", mv.all, "RIGHT", 0, 0)
  mv.clear = FlatButton(mv, "Clear slot", 80, 20); mv.clear:SetPoint("TOPRIGHT", 0, -30)
  mv.cur = Label(mv, "", "GameFontNormalSmall"); mv.cur:SetPoint("TOPLEFT", 0, -58); mv.cur:SetJustifyH("LEFT")
  mv.prev = FlatButton(mv, "<", 24, 20); mv.next = FlatButton(mv, ">", 24, 20)
  mv.next:SetPoint("TOPRIGHT", 0, -54); mv.pageT = Label(mv, "", "GameFontHighlightSmall"); mv.pageT:SetPoint("RIGHT", mv.next, "LEFT", -6, 0)
  mv.prev:SetPoint("RIGHT", mv.pageT, "LEFT", -6, 0)
  mv.prev:SetScript("OnClick", function() mv.page = math.max(1, mv.page - 1); mv.Render() end)
  mv.next:SetScript("OnClick", function() mv.page = mv.page + 1; mv.Render() end)
  mv:EnableMouseWheel(true)
  mv:SetScript("OnMouseWheel", function(_, d) mv.page = math.max(1, mv.page - d); mv.Render() end)

  -- preview scene laid over the transmog character; Blizzard's model is tucked away only while it shows a mount
  local ov
  local function CP() return _G.TransmogFrame and _G.TransmogFrame:IsShown() and _G.TransmogFrame.CharacterPreview end
  local function Overlay()
    if ov ~= nil then return ov end
    local cp = CP(); if not (cp and type(cp.ModelScene) == "table") then return nil end
    local ok, sc = pcall(CreateFrame, "ModelScene", "TransmogKitMountScene", cp, "WrappedAndUnwrappedModelScene")
    ov = ok and sc or false
    if ov then ov:SetAllPoints(cp.ModelScene); ov:SetFrameLevel(cp.ModelScene:GetFrameLevel() + 1); ov:Hide() end
    return ov
  end
  local function EndMountPreview()
    if ov then ov:Hide() end
    local cp = CP() or (_G.TransmogFrame and _G.TransmogFrame.CharacterPreview)
    if cp and type(cp.ModelScene) == "table" and mv.tuckedBlizz then cp.ModelScene:Show() end
    mv.tuckedBlizz = nil
  end
  local function DressRiderIn(sc)
    local rider = sc.GetPlayerActor and sc:GetPlayerActor("player-rider")
    local list = PendingLook()
    if not (rider and list) then return end
    for slotID, info in pairs(list) do
      if slotID ~= 16 and slotID ~= 17 then pcall(rider.SetItemTransmogInfo, rider, info, slotID) end
    end
  end
  local function ShowMount(mountID)
    local sc = Overlay(); if not sc then return end
    local creatureDisplayID, _, _, isSelfMount, _, modelSceneID, animID, spellVisualKitID, disableRider = C_MountJournal.GetMountInfoExtraByID(mountID)
    if not creatureDisplayID then
      local all = C_MountJournal.GetMountAllCreatureDisplayInfoByID and C_MountJournal.GetMountAllCreatureDisplayInfoByID(mountID)
      creatureDisplayID = all and all[1] and all[1].creatureDisplayID
    end
    if not (creatureDisplayID and modelSceneID) then return end
    local cp = CP()
    if cp and type(cp.ModelScene) == "table" and cp.ModelScene:IsShown() then cp.ModelScene:Hide(); mv.tuckedBlizz = true end
    sc:Show()
    sc:TransitionToModelSceneID(modelSceneID, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
    local actor = sc:GetActorByTag("unwrapped"); if not actor then return end
    actor:SetModelByCreatureDisplayID(creatureDisplayID, true)
    if isSelfMount then actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.None); actor:SetAnimation(618)
    else actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.Anim); actor:SetAnimation(0) end
    local native = PlayerUtil and PlayerUtil.ShouldUseNativeFormInModelScene and PlayerUtil.ShouldUseNativeFormInModelScene() or false
    sc:AttachPlayerToMount(actor, animID, isSelfMount, disableRider, spellVisualKitID, native)
    DressRiderIn(sc); C_Timer.After(0.15, function() DressRiderIn(sc) end); C_Timer.After(0.6, function() DressRiderIn(sc) end)
  end
  local function Preview(e)
    if mv.kind == "hearth" then EndMountPreview(); PreviewHearth(e.id)
    else StopHearth(); pcall(ShowMount, e.id) end
  end
  local function Current()
    local id = ViewedOutfitID(); local kit = id and FindKit(id)
    return id, kit and kit[mv.kind]
  end
  local function Assign(e)
    local id = ViewedOutfitID(); if not id then UIErrorsFrame:AddMessage("Select an outfit first.", 1, 0.3, 0.3) return end
    Kit(id)[mv.kind] = e and {id = e.id, name = e.name, icon = e.icon} or nil
    Saved(mv.kind, e and e.name, id)
    StripRefresh()
    if id == ActiveOutfitID() then ApplyActiveOutfit(true) end
    mv.Render()
  end
  mv.clear:SetScript("OnClick", function() Assign(nil) end)

  local RH, GAP = 30, 4
  local function Row(i)
    local b = mv.rows[i]; if b then return b end
    b = CreateFrame("Button", nil, mv, "BackdropTemplate"); Skin(b, 0.9)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(24, 24); b.icon:SetPoint("LEFT", 3, 0)
    b.text = Label(b, "", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0); b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0.3, 1); if self.entry then Preview(self.entry) end end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.9) end)
    b:SetScript("OnClick", function(self) if self.entry then Assign(self.entry) end end)
    mv.rows[i] = b; return b
  end
  function mv.Render()
    local W, H = mv:GetWidth(), mv:GetHeight()
    if not W or W < 50 then W, H = 314, 480 end
    local top = 80
    local cols = W >= 420 and 2 or 1
    local cw = math.floor((W - (cols - 1) * 6) / cols)
    local rows = math.max(1, math.floor((H - top + GAP) / (RH + GAP)))
    local per = cols * rows
    local pages = math.max(1, math.ceil(#mv.data / per))
    if mv.page > pages then mv.page = pages end
    mv.pageT:SetText("Page "..mv.page.." / "..pages)
    local _, cur = Current()
    local label = mv.kind == "hearth" and "Hearthstone" or (mv.kind == "swimming" and "Swim" or (mv.kind:gsub("^%l", string.upper)))
    mv.cur:SetText(label.." for |cffffffff"..(ViewedOutfitID() and OutfitName(ViewedOutfitID()) or "?").."|r: "..(cur and ("|cff55ff55"..cur.name.."|r") or "|cff888888not set|r"))
    for k, b in pairs(mv.kindB) do
      local on = k == mv.kind
      b:SetBackdropColor(on and 0.35 or 0.06, on and 0.27 or 0.06, on and 0.1 or 0.08, 1)
    end
    local off = (mv.page - 1) * per
    for i = 1, math.max(per, #mv.rows) do
      local e = i <= per and mv.data[off + i]
      local b = e and Row(i) or mv.rows[i]
      if e then
        local r, c = math.floor((i - 1) / cols), (i - 1) % cols
        b:SetSize(cw, RH); b:ClearAllPoints(); b:SetPoint("TOPLEFT", mv, "TOPLEFT", c * (cw + 6), -top - r * (RH + GAP))
        b.entry = e; b.icon:SetTexture(e.icon)
        local sel = cur and cur.id == e.id
        b.text:SetText((e.fav and "|A:PetJournal-FavoritesIcon:14:14|a " or "")..(sel and "|cff55ff55" or "")..e.name..(sel and "|r" or ""))
        b:SetBackdropColor(sel and 0.12 or 0.06, sel and 0.22 or 0.06, sel and 0.1 or 0.08, 0.9)
        b:Show()
      elseif b then b.entry = nil; b:Hide() end
    end
  end
  function mv.Refresh()
    local txt = (mv.box:GetText() or ""):lower()
    mv.all:SetShown(mv.kind ~= "hearth")
    if mv.kind == "hearth" then EndMountPreview() else StopHearth() end
    local src = mv.kind == "hearth" and GetHearthList() or GetMountList(mv.kind, mv.all:GetChecked())
    wipe(mv.data)
    for _, e in ipairs(src) do
      if txt == "" or e.name:lower():find(txt, 1, true) then mv.data[#mv.data+1] = e end
    end
    mv.Render()
  end
  mv:SetScript("OnSizeChanged", function() if mv:IsShown() then mv.Render() end end)
  mv:SetScript("OnShow", function()
    local _, cur = Current()
    if cur and mv.kind ~= "hearth" then pcall(ShowMount, cur.id) end
  end)
  mv:SetScript("OnHide", function() EndMountPreview(); StopHearth() end)

  -- the strip buttons open this tab when the transmog window is up
  function TransmogKit_OpenMountFinder(kind)
    local tf = _G.TransmogFrame
    if not (tf and tf:IsShown() and _G.TransmogKitFinderTab and _G.TransmogKitFinderTab:IsShown()) then return false end
    mv.kind = kind; mv.page = 1; mv.box:SetText("")
    search.f.mode = "mounts"
    _G.TransmogKitFinderTab:Click()
    if search:IsShown() then SearchUpdate() end
    return search:IsShown()
  end
end

---------------------------------------------------------------- Finder: Effects tab (weapon enchant illusions)
-- Same idea as Blizzard's Weapon Enchantment page: a grid of your weapon with each effect applied.
do
  local ev = CreateFrame("Frame", "TransmogKitEffectView", search); UI.ev = ev
  ev:SetPoint("TOPLEFT", 12, -30); ev:SetPoint("BOTTOMRIGHT", -12, 26); ev:Hide()
  ev.hand = 16; ev.page = 1; ev.data = {}; ev.cells = {}; ev.entries = {}
  ev.handB = {}
  for i, h in ipairs({{16, "Main hand"}, {17, "Off hand"}}) do
    local b = FlatButton(ev, h[2], 100, 22); b:SetPoint("TOPLEFT", (i - 1) * 104, 0)
    b:SetScript("OnClick", function() ev.hand = h[1]; ev.page = 1; ev.Refresh() end)
    ev.handB[h[1]] = b
  end
  ev.box = CreateFrame("EditBox", nil, ev, "InputBoxTemplate"); ev.box:SetSize(150, 20); ev.box:SetAutoFocus(false)
  ev.box:SetPoint("TOPLEFT", 6, -30)
  ev.box:SetScript("OnTextChanged", function() ev.page = 1; ev.Refresh() end)
  ev.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  ev.clear = FlatButton(ev, "Clear effect", 90, 20); ev.clear:SetPoint("TOPRIGHT", 0, -30)
  ev.cur = Label(ev, "", "GameFontNormalSmall"); ev.cur:SetPoint("TOPLEFT", 0, -56); ev.cur:SetJustifyH("LEFT")
  ev.msg = Label(ev, "", "GameFontHighlight"); ev.msg:SetPoint("CENTER", 0, 0); ev.msg:SetWidth(240)
  ev.prev = FlatButton(ev, "<", 24, 20); ev.next = FlatButton(ev, ">", 24, 20)
  ev.pageT = Label(ev, "", "GameFontHighlightSmall")
  ev.next:SetPoint("BOTTOMRIGHT", 0, 0); ev.pageT:SetPoint("RIGHT", ev.next, "LEFT", -6, 0); ev.prev:SetPoint("RIGHT", ev.pageT, "LEFT", -6, 0)
  ev.prev:SetScript("OnClick", function() ev.page = math.max(1, ev.page - 1); ev.Render() end)
  ev.next:SetScript("OnClick", function() ev.page = ev.page + 1; ev.Render() end)
  ev:EnableMouseWheel(true)
  ev:SetScript("OnMouseWheel", function(_, d) ev.page = math.max(1, ev.page - d); ev.Render() end)

  local NONE = (Enum.TransmogOutfitSlotOption and Enum.TransmogOutfitSlotOption.None) or 0
  -- the chosen hand's Blizzard weapon slot, and the effect box that belongs to it
  local function Frames()
    local slot, sf = BlizzSlot(ev.hand)
    if not slot then return end
    local ill = sf.GetIllusionSlotFrame and sf:GetIllusionSlotFrame()
    return slot, sf, ill
  end
  local function WeaponOption(sf)
    local ok, info = pcall(sf.GetCurrentWeaponOptionInfo, sf)
    return (ok and info and info.weaponOption) or NONE
  end
  local function Loc(ill)
    if not (ill and ill.GetTransmogLocation) then return end
    local ok, loc = pcall(ill.GetTransmogLocation, ill)
    return ok and loc or nil
  end
  -- what the grid shows: the weapon currently set on this outfit (or the game's default weapon for the category)
  local function Ctx()
    local slot, sf, ill = Frames()
    if not slot then return end
    local opt = WeaponOption(sf)
    local srcID, weaponVisual, subclass, cat
    local ok, info = pcall(OI.GetViewedOutfitSlotInfo, slot, Enum.TransmogType.Appearance, opt)
    if ok and info and info.transmogID and info.transmogID ~= 0 then srcID = info.transmogID end
    local function FromSource(id)
      local okA, ai = pcall(C_TransmogCollection.GetAppearanceSourceInfo, id)
      if okA and type(ai) == "table" then weaponVisual, subclass, cat = ai.itemAppearanceID, ai.itemSubclass, ai.category or ai.categoryID end
      if not weaponVisual then
        local okS, si = pcall(C_TransmogCollection.GetSourceInfo, id)
        if okS and si then weaponVisual = si.visualID; cat = cat or si.categoryID end
      end
    end
    if srcID then FromSource(srcID) end
    if not cat then cat = (search.f.cat and search.f.cat >= 12) and search.f.cat or nil end
    if not cat then
      local okW, cats = pcall(WeaponCats)
      cat = okW and cats and cats[1] and cats[1][1] or nil
    end
    if not weaponVisual and cat and OI.GetIllusionDefaultIMAIDForCollectionType then
      local okD, ima = pcall(OI.GetIllusionDefaultIMAIDForCollectionType, cat)
      if okD and ima then srcID = ima; FromSource(ima) end
    end
    local cameraID
    if srcID and C_TransmogCollection.GetAppearanceCameraIDBySource then
      local variation
      local aloc = sf.GetTransmogLocation and sf:GetTransmogLocation()
      if aloc and TransmogUtil and TransmogUtil.GetCameraVariation then
        local okV, v = pcall(TransmogUtil.GetCameraVariation, aloc, false); if okV then variation = v end
      end
      local okC, cid = pcall(C_TransmogCollection.GetAppearanceCameraIDBySource, srcID, variation)
      if okC then cameraID = cid end
    end
    return {slot = slot, sf = sf, ill = ill, opt = opt, weaponVisual = weaponVisual, subclass = subclass, cat = cat, cameraID = cameraID}
  end
  local function LoadEntries(cat)
    local ok, list = pcall(C_TransmogCollection.GetIllusions, cat)
    if not ok or type(list) ~= "table" or #list == 0 then ok, list = pcall(C_TransmogCollection.GetIllusions) end
    local out = {}
    for _, it in ipairs(ok and type(list) == "table" and list or {}) do
      local name
      if C_TransmogCollection.GetIllusionStrings then
        local okN, n = pcall(C_TransmogCollection.GetIllusionStrings, it.sourceID); if okN then name = n end
      end
      if not name and C_TransmogCollection.GetIllusionSourceInfo then
        local okN, _, n = pcall(C_TransmogCollection.GetIllusionSourceInfo, it.sourceID); if okN then name = n end
      end
      if IsSecret(name) then name = nil end
      if it.isHideVisual then name = "Hide weapon enchant" end
      out[#out+1] = {sourceID = it.sourceID, visualID = it.visualID, icon = it.icon, collected = it.isCollected and true or false,
        hide = it.isHideVisual and true or false, name = name or ("Effect "..tostring(it.sourceID)),
        fav = TransmogKitAccountDB.effectFavs[it.sourceID] and true or false}
    end
    table.sort(out, function(a, b)
      if a.hide ~= b.hide then return a.hide end
      if a.fav ~= b.fav then return a.fav end
      return a.name < b.name
    end)
    return out
  end
  local function CurrentID(ctx)
    local loc = ctx and Loc(ctx.ill)
    if not loc then return end
    local ok, info = pcall(OI.GetViewedOutfitSlotInfo, loc:GetSlot(), loc:GetType(), ctx.opt)
    local DT = Enum.TransmogOutfitDisplayType
    if ok and info and info.displayType ~= DT.Unassigned and info.displayType ~= DT.Equipped then return info.transmogID end
  end
  local function Assign(e) -- e == nil clears the effect
    local ctx = Ctx()
    local loc = ctx and Loc(ctx.ill)
    if not loc then UIErrorsFrame:AddMessage("Open the transmogrifier and pick a weapon first.", 1, 0.3, 0.3) return end
    if ctx.ill.IsEnabled and not ctx.ill:IsEnabled() then UIErrorsFrame:AddMessage("That weapon can't take an effect.", 1, 0.3, 0.3) return end
    if e and not e.collected then UIErrorsFrame:AddMessage("You haven't collected that effect yet.", 1, 0.3, 0.3) return end
    local DT = Enum.TransmogOutfitDisplayType
    local id, dtype = Constants.Transmog.NoTransmogID, DT.Unassigned
    if e then
      id, dtype = e.sourceID, DT.Assigned
      if C_TransmogCollection.IsSpellItemEnchantmentHiddenVisual and C_TransmogCollection.IsSpellItemEnchantmentHiddenVisual(id) then dtype = DT.Hidden end
    end
    -- select the effect box first so the transmog window shows it as the active slot (our own select doesn't re-trigger the Finder)
    local tf = _G.TransmogFrame; local cp = tf and tf.CharacterPreview
    if cp and cp.GetSelectedSlotData and ctx.ill.slotData and cp:GetSelectedSlotData() ~= ctx.ill.slotData then
      iv.selfSelect = true; pcall(tf.SelectSlot, tf, ctx.ill); iv.selfSelect = false
    end
    if UI.PushUndo then UI.PushUndo(loc:GetSlot(), loc:GetType(), ctx.opt) end
    local ok, err = pcall(OI.SetPendingTransmog, loc:GetSlot(), loc:GetType(), ctx.opt, id, dtype)
    if not ok then UIErrorsFrame:AddMessage("Blizzard rejected the change: "..tostring(err), 1, 0.3, 0.3) return end
    if SOUNDKIT and SOUNDKIT.UI_TRANSMOG_ITEM_CLICK then PlaySound(SOUNDKIT.UI_TRANSMOG_ITEM_CLICK) end
    C_Timer.After(0.1, function() if ev:IsShown() then ev.Render() end end)
  end
  ev.clear:SetScript("OnClick", function() Assign(nil) end)

  local function ApplyEffectModel(m)
    local e, ctx = m.pendingEntry, m.pendingCtx
    if not (e and ctx and ctx.weaponVisual) then return end
    pcall(function()
      m:SetItemAppearance(ctx.weaponVisual, e.visualID, ctx.subclass)
      if ctx.cameraID and ctx.cameraID > 0 and Model_ApplyUICamera then Model_ApplyUICamera(m, ctx.cameraID) end
    end)
  end
  local function NewCell(i)
    local c = CreateFrame("Button", nil, ev, "BackdropTemplate"); Skin(c, 1)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c.model = CreateFrame("DressUpModel", nil, c)
    c.model:SetPoint("TOPLEFT", 2, -2); c.model:SetPoint("BOTTOMRIGHT", -2, 2)
    c.model:EnableMouse(false)
    pcall(c.model.SetKeepModelOnHide, c.model, true)
    pcall(c.model.SetDoBlend, c.model, false)
    c.model:SetScript("OnModelLoaded", ApplyEffectModel)
    c.star = c:CreateTexture(nil, "OVERLAY", nil, 7); c.star:SetSize(16, 16); c.star:SetPoint("TOPRIGHT", -3, -3)
    c.star:SetAtlas("PetJournal-FavoritesIcon"); c.star:Hide()
    c.hl = c:CreateTexture(nil, "HIGHLIGHT"); c.hl:SetAllPoints(); c.hl:SetColorTexture(1, 0.82, 0.3, 0.12)
    c.cur = c:CreateTexture(nil, "OVERLAY", nil, 6); c.cur:SetPoint("TOPLEFT", -2, 2); c.cur:SetPoint("BOTTOMRIGHT", 2, -2)
    c.cur:SetAtlas("transmog-wardrobe-border-selected"); if not c.cur:GetAtlas() then c.cur:SetColorTexture(0.7, 0.3, 0.9, 0.35) end
    c.cur:SetBlendMode("ADD"); c.cur:Hide()
    c.tag = Label(c, "", "GameFontHighlightSmall"); c.tag:SetPoint("TOPLEFT", 4, -4); c.tag:SetTextColor(0.9, 0.4, 1)
    c:SetScript("OnClick", function(self, btn)
      local e = self.entry; if not e then return end
      if btn == "RightButton" then
        local favs = TransmogKitAccountDB.effectFavs
        favs[e.sourceID] = (not favs[e.sourceID]) or nil
        ev.Refresh()
      else Assign(e) end
    end)
    c:SetScript("OnEnter", function(self)
      self:SetBackdropBorderColor(1, 0.82, 0.3, 1)
      if self.entry then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.entry.name)
        GameTooltip:AddLine("Click: apply   Right-click: favorite", 1, 1, 1); GameTooltip:Show()
      end
    end)
    c:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.9); GameTooltip:Hide() end)
    ev.cells[i] = c; return c
  end
  function ev.Render()
    local W, H = ev:GetWidth(), ev:GetHeight()
    if not W or W < 50 then W, H = 314, 544 end
    local ctx = Ctx()
    local key = ctx and (tostring(ctx.weaponVisual)..":"..tostring(ctx.subclass)..":"..tostring(ctx.cameraID)) or "none"
    if ev.ctxKey ~= key then ev.ctxKey = key; for _, c in ipairs(ev.cells) do c.entry = nil end end
    for h, b in pairs(ev.handB) do
      local on = h == ev.hand
      b:SetBackdropColor(on and 0.35 or 0.06, on and 0.27 or 0.06, on and 0.1 or 0.08, 1)
    end
    local curID = CurrentID(ctx)
    local curName
    for _, e in ipairs(ev.entries) do if e.sourceID == curID then curName = e.name end end
    ev.cur:SetText((ev.hand == 16 and "Main hand" or "Off hand").." effect: "..(curName and ("|cff55ff55"..curName.."|r") or "|cff888888none|r"))
    local gap, top, ch = 6, 80, 100
    local cols = math.max(2, math.floor((W + gap) / (70 + gap)))
    local cw = math.floor((W - (cols - 1) * gap) / cols)
    local rows = math.max(1, math.floor((H - top - 26 + gap) / (ch + gap)))
    local per = cols * rows
    local pages = math.max(1, math.ceil(#ev.data / per))
    if ev.page > pages then ev.page = pages end
    ev.pageT:SetText("Page "..ev.page.." / "..pages)
    if not (ctx and ctx.weaponVisual) then
      ev.msg:SetText("Pick a weapon appearance for this hand first (Items tab), then come back here.")
      for _, c in ipairs(ev.cells) do c.entry = nil; c:Hide() end
      return
    end
    ev.msg:SetText(#ev.data == 0 and "No collected effects match." or "")
    local off = (ev.page - 1) * per
    for i = 1, math.max(per, #ev.cells) do
      local e = i <= per and ev.data[off + i]
      local c = e and (ev.cells[i] or NewCell(i)) or ev.cells[i]
      if e then
        local r, col = math.floor((i - 1) / cols), (i - 1) % cols
        c:SetSize(cw, ch); c:ClearAllPoints(); c:SetPoint("TOPLEFT", ev, "TOPLEFT", col * (cw + gap), -top - r * (ch + gap))
        if c.entry ~= e then
          c.entry = e
          c.model.pendingEntry, c.model.pendingCtx = e, ctx
          ApplyEffectModel(c.model)
        end
        c.tag:SetText(e.hide and "Hidden" or "")
        c.star:SetShown(e.fav and true or false)
        c.cur:SetShown(curID ~= nil and e.sourceID == curID)
        c:Show()
      elseif c then c.entry = nil; c:Hide() end
    end
  end
  function ev.Refresh()
    local txt = (ev.box:GetText() or ""):lower()
    local ctx = Ctx()
    ev.entries = LoadEntries(ctx and ctx.cat)
    wipe(ev.data)
    for _, e in ipairs(ev.entries) do
      if (e.collected or e.hide) and (txt == "" or e.name:lower():find(txt, 1, true)) then ev.data[#ev.data+1] = e end
    end
    ev.Render()
  end
  ev:SetScript("OnSizeChanged", function() if ev:IsShown() then ev.Render() end end)
  ev:SetScript("OnShow", function() ev.Refresh() end)
end

---------------------------------------------------------------- v0.21: undo, outfit palette, sharing, settings, look library
do
  local OIx = C_TransmogOutfitInfo
  local NONE = (Enum.TransmogOutfitSlotOption and Enum.TransmogOutfitSlotOption.None) or 0
  local DT = Enum.TransmogOutfitDisplayType
  local APPEARANCE = Enum.TransmogType.Appearance

  local function WOpt(sf)
    local ok, wi = pcall(sf.GetCurrentWeaponOptionInfo, sf)
    return (ok and wi and wi.weaponOption) or NONE
  end
  -- every inventory slot the outfit can set: armor, then main hand and off hand
  local function AllInvs()
    local t = {}
    for _, a in ipairs(ARMOR) do t[#t+1] = a[2] end
    t[#t+1] = 16; t[#t+1] = 17
    return t
  end
  local function IllusionLoc(sf)
    local ill = sf.GetIllusionSlotFrame and sf:GetIllusionSlotFrame()
    local loc = ill and ill.GetTransmogLocation and ill:GetTransmogLocation()
    return loc, ill
  end

  ------------------------------------------------------------ undo
  local undo = {}
  local function Snapshot(slot, typ, opt)
    local ok, info = pcall(OIx.GetViewedOutfitSlotInfo, slot, typ, opt)
    if not (ok and info) then return end
    local id, dt = info.transmogID, info.displayType
    if dt == DT.Unassigned or dt == DT.Equipped or not id or id == 0 then id = Constants.Transmog.NoTransmogID end
    return {slot = slot, typ = typ, opt = opt, id = id, dt = dt}
  end
  function UI.undoRefresh()
    if not UI.undo then return end
    local n = #undo
    UI.undo:SetLabel(n > 0 and ("Undo ("..n..")") or "Undo")
    UI.undo:SetEnabled(n > 0); UI.undo:SetAlpha(n > 0 and 1 or 0.45)
  end
  function UI.PushUndoGroup(items)
    if not items or #items == 0 then return end
    local vid = ViewedOutfitID()
    if undo.outfit ~= vid then wipe(undo); undo.outfit = vid end
    undo[#undo+1] = items
    if #undo > 40 then table.remove(undo, 1) end
    UI.undoRefresh()
  end
  function UI.PushUndo(slot, typ, opt)
    local snap = Snapshot(slot, typ, opt)
    if snap then UI.PushUndoGroup({snap}) end
  end
  function UI.DoUndo()
    local top = undo[#undo]
    if not top then return end
    if undo.outfit ~= ViewedOutfitID() then wipe(undo); undo.outfit = nil; UI.undoRefresh(); return end
    undo[#undo] = nil
    local fails = 0
    for i = #top, 1, -1 do
      local sn = top[i]
      if not pcall(OIx.SetPendingTransmog, sn.slot, sn.typ, sn.opt, sn.id, sn.dt) then fails = fails + 1 end
    end
    if fails > 0 then UIErrorsFrame:AddMessage("Couldn't undo "..fails.." change(s).", 1, 0.3, 0.3) end
    UI.undoRefresh()
    C_Timer.After(0.15, function()
      if UI.ev and UI.ev:IsShown() then UI.ev.Render() end
      if search.f.mode == "items" and search:IsShown() then iv.Render() end
    end)
  end
  UI.undo = FlatButton(search, "Undo", 76, 18); UI.undo:SetPoint("BOTTOMRIGHT", -8, 4)
  UI.undo:SetScript("OnClick", function() UI.DoUndo() end)
  UI.undo:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Undo the last change made from the Finder")
    GameTooltip:AddLine("Steps back through changes you have not saved yet.", 1, 1, 1); GameTooltip:Show()
  end)
  UI.undo:SetScript("OnLeave", GameTooltip_Hide)
  UI.help:SetWordWrap(false)
  local function FitHelp() UI.help:SetWidth(math.max(120, (search:GetWidth() or 330) - 190)) end
  FitHelp(); search:HookScript("OnSizeChanged", FitHelp)
  local uf = CreateFrame("Frame")
  for _, e2 in ipairs({"TRANSMOGRIFY_SUCCESS", "TRANSMOGRIFY_CLOSE", "TRANSMOGRIFY_OPEN", "VIEWED_TRANSMOG_OUTFIT_CHANGED"}) do pcall(uf.RegisterEvent, uf, e2) end
  uf:SetScript("OnEvent", function() wipe(undo); undo.outfit = nil; UI.undoRefresh() end)
  UI.undoRefresh()

  ------------------------------------------------------------ palette from the whole outfit
  local function Cluster(pool, maxN)
    table.sort(pool, function(a, b) return a[4] > b[4] end)
    local cl = {}
    for _, c in ipairs(pool) do
      local hit
      for _, k in ipairs(cl) do
        if math.sqrt((k[1]-c[1])^2 + (k[2]-c[2])^2 + (k[3]-c[3])^2) < 14 then k.w = k.w + c[4]; hit = true; break end
      end
      if not hit then cl[#cl+1] = {c[1], c[2], c[3], r = c[5], g = c[6], b = c[7], w = c[4]} end
    end
    table.sort(cl, function(a, b) return a.w > b.w end)
    local total = 0; for _, k in ipairs(cl) do total = total + k.w end
    local out = {}
    for i = 1, math.min(maxN, #cl) do
      if cl[i].w >= total * 0.08 then out[#out+1] = {cl[i].r, cl[i].g, cl[i].b} end
    end
    return out
  end
  function UI.OutfitPalette()
    local pool, pieces = {}, 0
    for _, inv in ipairs(AllInvs()) do
      local slot, sf = BlizzSlot(inv)
      if slot then
        local ok, info = pcall(OIx.GetViewedOutfitSlotInfo, slot, APPEARANCE, WOpt(sf))
        if ok and info and info.transmogID and info.transmogID ~= 0 and (info.displayType == DT.Assigned or info.displayType == DT.Equipped) then
          local okS, si = pcall(C_TransmogCollection.GetSourceInfo, info.transmogID)
          local cd = okS and si and si.visualID and CM.get(si.visualID)
          if cd then
            pieces = pieces + 1
            for _, c in ipairs(cd) do if c[4] >= 2 then pool[#pool+1] = {c[1], c[2], c[3], c[4], c[5], c[6], c[7]} end end
          end
        end
      end
    end
    return Cluster(pool, 4), pieces
  end
  function UI.UseOutfitPalette()
    local list, pieces = UI.OutfitPalette()
    if not list or #list == 0 then
      UIErrorsFrame:AddMessage("Open the transmogrifier and set a few pieces on this outfit first.", 1, 0.3, 0.3)
      return false
    end
    local f = search.f
    f.multi = list; f.themeName = "My outfit"; f.multiNeed = 0.5
    f.color = nil; f.paletteItem = nil; f.paletteName = nil; f.mode = "items"; f.page = 1
    SearchUpdate()
    return true
  end

  ------------------------------------------------------------ text dialog (export / import / names)
  local function BuildDialog()
    if UI.dlg then return UI.dlg end
    local d = CreateFrame("Frame", "TransmogKitDialog", UIParent, "BackdropTemplate"); Skin(d, 1)
    d:SetSize(440, 250); d:SetPoint("CENTER"); d:SetFrameStrata("FULLSCREEN_DIALOG"); d:SetToplevel(true); d:EnableMouse(true)
    d:SetMovable(true); d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving); d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:Hide(); tinsert(UISpecialFrames, "TransmogKitDialog")
    d.title = Label(d, "", "GameFontNormal"); d.title:SetPoint("TOP", 0, -10)
    d.note = Label(d, "", "GameFontDisableSmall"); d.note:SetPoint("TOPLEFT", 14, -30); d.note:SetWidth(412); d.note:SetJustifyH("LEFT")
    d.scroll = CreateFrame("ScrollFrame", "TransmogKitDialogScroll", d, "UIPanelScrollFrameTemplate")
    d.scroll:SetPoint("TOPLEFT", 14, -66); d.scroll:SetPoint("BOTTOMRIGHT", -34, 46)
    d.edit = CreateFrame("EditBox", nil, d.scroll); d.edit:SetMultiLine(true); d.edit:SetAutoFocus(false)
    d.edit:SetFontObject(ChatFontNormal); d.edit:SetWidth(385); d.edit:SetHeight(120)
    d.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    d.edit:SetScript("OnEnterPressed", function(self) if d.single then d.ok:Click() else self:Insert("\n") end end)
    d.scroll:SetScrollChild(d.edit)
    d.ok = FlatButton(d, "OK", 100, 22); d.ok:SetPoint("BOTTOMRIGHT", -14, 12)
    d.cancel = FlatButton(d, "Close", 100, 22); d.cancel:SetPoint("RIGHT", d.ok, "LEFT", -8, 0)
    d.cancel:SetScript("OnClick", function() d:Hide() end)
    d.ok:SetScript("OnClick", function()
      if d.onOK and d.onOK(d.edit:GetText()) == false then return end
      d:Hide()
    end)
    UI.dlg = d
    return d
  end
  function UI.Dialog(title, note, text, okLabel, onOK, selectAll, single)
    local d = BuildDialog()
    d.title:SetText(title); d.note:SetText(note or ""); d.onOK = onOK; d.single = single
    d.ok:SetLabel(okLabel or "OK"); d.ok:SetShown(onOK ~= nil)
    d.edit:SetText(text or "")
    d:Show(); d:Raise(); d.edit:SetFocus()
    if selectAll then d.edit:HighlightText() else d.edit:SetCursorPosition(#(text or "")) end
  end

  ------------------------------------------------------------ export / import an outfit's picks
  local PICK_KEYS = {{"g", "ground"}, {"f", "flying"}, {"s", "swimming"}, {"h", "hearth"}}
  local function PicksToString(kit)
    local parts = {"TMK1"}
    for _, d in ipairs(PICK_KEYS) do
      local v = kit and kit[d[2]]
      if v and v.id then parts[#parts+1] = d[1].."="..v.id end
    end
    if kit and type(kit.title) == "number" then parts[#parts+1] = "t="..kit.title end
    return table.concat(parts, ";")
  end
  function UI.ExportPicks()
    local id = ViewedOutfitID()
    local kit = id and FindKit(id)
    local str = PicksToString(kit)
    if str == "TMK1" then Print("Nothing is set for that outfit yet, so there is nothing to export.") return end
    UI.Dialog("Export picks: "..tostring(OutfitName(id)), "Copy this text (Ctrl+C) and send it to a friend, or keep it as a backup. Anyone using TransmogKit can import it.", str, nil, nil, true)
  end
  local function DoImport(text, id)
    if not text:match("^%s*TMK1") then Print("That doesn't look like a TransmogKit string (it should start with TMK1).") return false end
    local got = {}
    for k, v in text:gmatch("(%a)=(-?%d+)") do got[k] = tonumber(v) end
    local kit = Kit(id)
    local done, skipped = {}, {}
    for _, d in ipairs(PICK_KEYS) do
      local v = got[d[1]]
      if v then
        local name, icon
        if d[2] == "hearth" then local _, n, ic = C_ToyBox.GetToyInfo(v); name, icon = n, ic
        else local n, _, ic = C_MountJournal.GetMountInfoByID(v); name, icon = n, ic end
        if name then kit[d[2]] = {id = v, name = name, icon = icon}; done[#done+1] = d[2]
        else skipped[#skipped+1] = d[2] end
      end
    end
    if got.t then kit.title = got.t; done[#done+1] = "title" end
    if #done == 0 then Print("Nothing in that string could be used by this game version.") return false end
    StripRefresh(); TitleRefresh()
    if id == ActiveOutfitID() then ApplyActiveOutfit(true) end
    Print("Imported "..table.concat(done, ", ").." for "..tostring(OutfitName(id))..(#skipped > 0 and ("  (skipped, not found: "..table.concat(skipped, ", ")..")") or "")..".")
    return true
  end
  function UI.ImportPicks()
    local id = ViewedOutfitID()
    if not id then Print("Open the transmogrifier and select an outfit first.") return end
    UI.Dialog("Import picks", "Paste a TMK1 string below. It replaces the mounts, hearth and title for \""..tostring(OutfitName(id)).."\".", "", "Import", function(t) return DoImport(t, id) end)
  end

  ------------------------------------------------------------ copy picks from another character
  local function CopyPick(v) return v and {id = v.id, name = v.name, icon = v.icon} or nil end
  local function HasPicks(k) return k and (k.ground or k.flying or k.swimming or k.hearth or k.title) end
  local function OtherChars()
    local list = {}
    for key, ent in pairs(TransmogKitAccountDB.chars) do
      if key ~= DB.charKey and ent.kits then
        local n = 0
        for _, k in pairs(ent.kits) do if HasPicks(k) then n = n + 1 end end
        if n > 0 then list[#list+1] = {key, (ent.charName or ("Character ..."..tostring(key):sub(-6))).."  ("..n.." outfits)"} end
      end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    return list
  end
  local function MyOutfitsByName()
    local map = {}
    for id = 1, 300 do
      local ok, info = pcall(OIx.GetOutfitInfo, id)
      if ok and type(info) == "table" and info.name and info.name ~= "" then map[info.name:lower()] = id end
    end
    return map
  end
  local function CopyByName(srcKey)
    local src = TransmogKitAccountDB.chars[srcKey]
    if not src then return "Pick a character first." end
    local mine, n, missed = MyOutfitsByName(), 0, 0
    for _, k in pairs(src.kits or {}) do
      if HasPicks(k) and k.name then
        local target = mine[k.name:lower()]
        if target then
          local d = Kit(target)
          d.ground, d.flying, d.swimming, d.hearth, d.title = CopyPick(k.ground), CopyPick(k.flying), CopyPick(k.swimming), CopyPick(k.hearth), k.title
          n = n + 1
        else missed = missed + 1 end
      end
    end
    StripRefresh(); TitleRefresh(); ApplyActiveOutfit(true)
    return ("Copied picks to %d outfit(s) with matching names. %d of theirs had no outfit with that name here."):format(n, missed)
  end
  local function CopyDefault(srcKey)
    local src = TransmogKitAccountDB.chars[srcKey]
    if not src then return "Pick a character first." end
    local lp = src.lastPicks
    if not HasPicks(lp) then for _, k in pairs(src.kits or {}) do if HasPicks(k) then lp = k; break end end end
    if not HasPicks(lp) then return "That character has no picks to copy." end
    DB.lastPicks = {ground = CopyPick(lp.ground), flying = CopyPick(lp.flying), swimming = CopyPick(lp.swimming), hearth = CopyPick(lp.hearth)}
    ApplyActiveOutfit(true)
    return "Now using their mounts and hearth for any outfit that has none of its own."
  end

  ------------------------------------------------------------ saved looks (appearances shared by every character)
  local function CaptureLook()
    local look = {slots = {}, ill = {}}
    for _, inv in ipairs(AllInvs()) do
      local slot, sf = BlizzSlot(inv)
      if slot then
        local opt = WOpt(sf)
        local ok, info = pcall(OIx.GetViewedOutfitSlotInfo, slot, APPEARANCE, opt)
        if ok and info and info.transmogID and info.transmogID ~= 0 and (info.displayType == DT.Assigned or info.displayType == DT.Hidden) then
          look.slots[#look.slots+1] = {inv = inv, id = info.transmogID, dt = info.displayType}
        end
        if inv == 16 or inv == 17 then
          local loc = IllusionLoc(sf)
          if loc then
            local ok2, i2 = pcall(OIx.GetViewedOutfitSlotInfo, loc:GetSlot(), loc:GetType(), opt)
            if ok2 and i2 and i2.transmogID and i2.transmogID ~= 0 and (i2.displayType == DT.Assigned or i2.displayType == DT.Hidden) then
              look.ill[#look.ill+1] = {inv = inv, id = i2.transmogID, dt = i2.displayType}
            end
          end
        end
      end
    end
    return look
  end
  local function LoadLook(look)
    if not (_G.TransmogFrame and _G.TransmogFrame:IsShown()) then return "Open a transmogrifier first." end
    local snaps, ok, bad = {}, 0, 0
    local function apply(slot, typ, opt, id, dt)
      local sn = Snapshot(slot, typ, opt); if sn then snaps[#snaps+1] = sn end
      if pcall(OIx.SetPendingTransmog, slot, typ, opt, id, dt) then ok = ok + 1 else bad = bad + 1 end
    end
    for _, s in ipairs(look.slots) do
      local slot, sf = BlizzSlot(s.inv)
      if slot then apply(slot, APPEARANCE, WOpt(sf), s.id, s.dt) else bad = bad + 1 end
    end
    for _, s in ipairs(look.ill) do
      local slot, sf = BlizzSlot(s.inv)
      local loc = slot and IllusionLoc(sf)
      if loc then apply(loc:GetSlot(), loc:GetType(), WOpt(sf), s.id, s.dt) else bad = bad + 1 end
    end
    UI.PushUndoGroup(snaps)
    C_Timer.After(0.2, function() if UI.ev and UI.ev:IsShown() then UI.ev.Render() end end)
    return ("Applied %d piece(s) (pending until you save the outfit)%s."):format(ok, bad > 0 and ("; "..bad.." couldn't be used by this character") or "")
  end

  ------------------------------------------------------------ settings view
  local sv = CreateFrame("Frame", "TransmogKitSettingsView", search); UI.sv = sv
  sv:SetPoint("TOPLEFT", 12, -30); sv:SetPoint("BOTTOMRIGHT", -12, 26); sv:Hide()
  sv.srcKey = nil; sv.lookPage = 1; sv.rows = {}
  local function Header(text, y)
    local h = Label(sv, text, "GameFontNormal"); h:SetPoint("TOPLEFT", 0, y); return h
  end
  local function Check(text, y, get, set)
    local cb = CreateFrame("CheckButton", nil, sv, "UICheckButtonTemplate"); cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 0, y)
    local t = Label(sv, text, "GameFontHighlightSmall"); t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb.Refresh = function() cb:SetChecked(get() and true or false) end
    return cb
  end
  Header("Options", 0)
  sv.cb1 = Check("Show confirmation messages in chat", -20, function() return TransmogKitAccountDB.opts.verbose end,
    function(v) TransmogKitAccountDB.opts.verbose = v end)
  sv.cb2 = Check("Open the Finder tab when the transmog window opens", -44, function() return TransmogKitAccountDB.opts.autoOpen ~= false end,
    function(v) TransmogKitAccountDB.opts.autoOpen = v end)

  Header("Share an outfit's mounts, hearth and title", -78)
  sv.export = FlatButton(sv, "Export this outfit's picks", 190, 22); sv.export:SetPoint("TOPLEFT", 0, -98)
  sv.export:SetScript("OnClick", function() UI.ExportPicks() end)
  sv.import = FlatButton(sv, "Import picks...", 130, 22); sv.import:SetPoint("LEFT", sv.export, "RIGHT", 8, 0)
  sv.import:SetScript("OnClick", function() UI.ImportPicks() end)

  Header("Copy picks from another character", -134)
  sv.char = FlatButton(sv, "Character: none", 328, 22); sv.char:SetPoint("TOPLEFT", 0, -154); AddArrow(sv.char)
  sv.char:SetScript("OnClick", function(self)
    local items = OtherChars()
    if #items == 0 then sv.msg:SetText("No other character has saved picks yet. Log in on them once after updating.") return end
    OpenMenu(self, items, function(k) return k == sv.srcKey end, function(k) sv.srcKey = k; sv.Refresh() end)
  end)
  sv.copyName = FlatButton(sv, "Copy to outfits with the same name", 328, 22); sv.copyName:SetPoint("TOPLEFT", 0, -180)
  sv.copyName:SetScript("OnClick", function() sv.msg:SetText(CopyByName(sv.srcKey)) end)
  sv.copyDef = FlatButton(sv, "Use their picks for outfits with none", 328, 22); sv.copyDef:SetPoint("TOPLEFT", 0, -206)
  sv.copyDef:SetScript("OnClick", function() sv.msg:SetText(CopyDefault(sv.srcKey)) end)
  sv.msg = Label(sv, "", "GameFontHighlightSmall"); sv.msg:SetPoint("TOPLEFT", 0, -234); sv.msg:SetWidth(328); sv.msg:SetJustifyH("LEFT")

  Header("Saved looks (shared by all your characters)", -272)
  sv.saveLook = FlatButton(sv, "Save this outfit's look...", 328, 22); sv.saveLook:SetPoint("TOPLEFT", 0, -292)
  sv.saveLook:SetScript("OnClick", function()
    if not (_G.TransmogFrame and _G.TransmogFrame:IsShown()) then sv.msg:SetText("Open a transmogrifier first.") return end
    local look = CaptureLook()
    if #look.slots == 0 then sv.msg:SetText("Nothing is set on this outfit yet.") return end
    UI.Dialog("Save look", "Name this look. It will be available on every character.", "", "Save", function(name)
      name = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n", " ")
      if name == "" then return false end
      look.name = name
      table.insert(TransmogKitAccountDB.looks, look)
      sv.msg:SetText("Saved \""..name.."\" ("..#look.slots.." pieces).")
      sv.Refresh()
    end, false, true)
  end)
  local ROWS = 6
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, sv); r:SetSize(328, 22); r:SetPoint("TOPLEFT", 0, -320 - (i - 1) * 24)
    r.name = Label(r, "", "GameFontHighlightSmall"); r.name:SetPoint("LEFT", 2, 0); r.name:SetWidth(190); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.load = FlatButton(r, "Load", 56, 20); r.load:SetPoint("RIGHT", -28, 0)
    r.del = FlatButton(r, "X", 22, 20); r.del:SetPoint("RIGHT", 0, 0)
    r.load:SetScript("OnClick", function() if r.look then sv.msg:SetText(LoadLook(r.look)) end end)
    r.del:SetScript("OnClick", function()
      for idx, l in ipairs(TransmogKitAccountDB.looks) do if l == r.look then table.remove(TransmogKitAccountDB.looks, idx); break end end
      sv.Refresh()
    end)
    sv.rows[i] = r
  end
  sv.prev = FlatButton(sv, "<", 24, 20); sv.next = FlatButton(sv, ">", 24, 20)
  sv.pageT = Label(sv, "", "GameFontHighlightSmall")
  sv.next:SetPoint("TOPRIGHT", 0, -320 - ROWS * 24); sv.pageT:SetPoint("RIGHT", sv.next, "LEFT", -6, 0); sv.prev:SetPoint("RIGHT", sv.pageT, "LEFT", -6, 0)
  sv.prev:SetScript("OnClick", function() sv.lookPage = math.max(1, sv.lookPage - 1); sv.Refresh() end)
  sv.next:SetScript("OnClick", function() sv.lookPage = sv.lookPage + 1; sv.Refresh() end)
  function sv.Refresh()
    sv.cb1.Refresh(); sv.cb2.Refresh()
    local chars = OtherChars()
    local found
    for _, c in ipairs(chars) do if c[1] == sv.srcKey then found = c end end
    if not found then sv.srcKey = chars[1] and chars[1][1] or nil; found = chars[1] end
    sv.char:SetLabel("Character: "..(found and found[2] or "none yet"))
    local has = sv.srcKey ~= nil
    sv.copyName:SetEnabled(has); sv.copyDef:SetEnabled(has)
    sv.copyName:SetAlpha(has and 1 or 0.45); sv.copyDef:SetAlpha(has and 1 or 0.45)
    local looks = TransmogKitAccountDB.looks
    local pages = math.max(1, math.ceil(#looks / ROWS))
    if sv.lookPage > pages then sv.lookPage = pages end
    sv.pageT:SetText("Page "..sv.lookPage.." / "..pages)
    for i = 1, ROWS do
      local l = looks[(sv.lookPage - 1) * ROWS + i]
      local r = sv.rows[i]
      r.look = l
      if l then r.name:SetText(l.name.."  |cff888888("..#l.slots.." pieces)|r"); r:Show() else r:Hide() end
    end
  end
  sv:SetScript("OnShow", function() sv.Refresh() end)

  ------------------------------------------------------------ weapon sheathing (side / back / default), like Blizzard's dropdown
  UI.sheath = FlatButton(search, "Sheathing", 190, 22); AddArrow(UI.sheath)
  UI.sheath:SetPoint("BOTTOMLEFT", 12, 3); UI.sheath:Hide()
  UI.bottomLeft = {}
  local function PlaceHelp()
    local x = math.max(UI.bottomLeft.sheath or 0, UI.bottomLeft.shoulder or 0)
    UI.help:ClearAllPoints()
    if x > 0 then
      UI.help:SetPoint("BOTTOMLEFT", x, 10); UI.help:SetJustifyH("LEFT")
      UI.help:SetWidth(math.max(100, (search:GetWidth() or 330) - x - 94))
    else
      UI.help:SetPoint("BOTTOM", 0, 10); UI.help:SetJustifyH("CENTER")
      UI.help:SetWidth(math.max(120, (search:GetWidth() or 330) - 190))
    end
  end
  function UI.RefreshSheath()
    local f = search.f
    local show = false
    if search:IsShown() and f.mode == "items" and f.cat and f.cat >= 12 then
      local ci = CatInfo(f.cat)
      local inv = ci and EffectiveHand(ci)
      local slot, sf = BlizzSlot(inv or 16)
      if inv and slot then
        local wo = sf.slotData.currentWeaponOptionInfo
        local opt = (wo and wo.weaponOption) or NONE
        local ok, info = pcall(OIx.GetViewedOutfitSlotInfo, slot, APPEARANCE, opt)
        if ok and info and info.transmogID and info.transmogID ~= Constants.Transmog.NoTransmogID and info.displayType ~= DT.Unassigned then
          local okC, cats = pcall(OIx.GetAllTransmogOutfitOptionSheatheCategoryInfo, info.transmogID)
          if okC and type(cats) == "table" and #cats > 1 then
            show = true
            local name
            for _, c in ipairs(cats) do if c.sheatheCategory == info.sheatheCategory then name = c.categoryName end end
            UI.sheath.cats, UI.sheath.cur, UI.sheath.slot, UI.sheath.opt = cats, info.sheatheCategory, slot, opt
            UI.sheath:SetLabel(name or "Sheathing")
          end
        end
      end
    end
    UI.sheath:SetShown(show)
    UI.bottomLeft.sheath = show and 212 or 0
    PlaceHelp()
  end
  UI.sheath:SetScript("OnClick", function(self)
    local cats = self.cats
    if not cats then return end
    local items = {}
    for _, c in ipairs(cats) do items[#items+1] = {c.sheatheCategory, c.categoryName} end
    OpenMenu(self, items, function(v) return v == self.cur end, function(v)
      if v ~= self.cur then
        local ok, err = pcall(OIx.SetPendingTransmogSheatheCategory, self.slot, self.opt, v)
        if not ok then UIErrorsFrame:AddMessage("Blizzard rejected the sheathing change: "..tostring(err), 1, 0.3, 0.3) end
        C_Timer.After(0.1, UI.RefreshSheath)
      end
    end)
  end)
  UI.sheath:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Where this weapon is worn when sheathed"); GameTooltip:Show()
  end)
  UI.sheath:SetScript("OnLeave", GameTooltip_Hide)

  ------------------------------------------------------------ "Transmog shoulders differently"
  UI.shoulder = CreateFrame("Frame", nil, search); UI.shoulder:SetSize(300, 24); UI.shoulder:SetPoint("BOTTOMLEFT", 10, 2); UI.shoulder:Hide()
  UI.shoulder.cb = CreateFrame("CheckButton", nil, UI.shoulder, "UICheckButtonTemplate"); UI.shoulder.cb:SetSize(24, 24); UI.shoulder.cb:SetPoint("LEFT", 0, 0)
  UI.shoulder.label = Label(UI.shoulder, "Transmog shoulders differently", "GameFontHighlightSmall"); UI.shoulder.label:SetPoint("LEFT", UI.shoulder.cb, "RIGHT", 2, 0)
  UI.shoulder.sides = {}
  for i, def in ipairs({{"ShoulderRight", "Right"}, {"ShoulderLeft", "Left"}}) do
    local b = FlatButton(UI.shoulder, def[2], 50, 20)
    b.slotKey = def[1]
    UI.shoulder.sides[i] = b
  end
  local function ShoulderPrimary()
    local f = search.f
    if not (search:IsShown() and f.mode == "items" and f.cat) then return end
    local ci = CatInfo(f.cat)
    if not ci or ci[1] >= 12 then return end
    local slot, sf = BlizzSlot(ci[2])
    if slot and slot == Enum.TransmogOutfitSlot.ShoulderRight and OIx.SlotHasSecondary and OIx.SlotHasSecondary(slot) then return slot, sf end
  end
  function UI.RefreshShoulder()
    local slot = ShoulderPrimary()
    local sh = UI.shoulder
    if not slot then sh:Hide(); UI.bottomLeft.shoulder = 0; PlaceHelp(); return end
    local on = OIx.GetSecondarySlotState and OIx.GetSecondarySlotState(slot) and true or false
    sh.cb:SetChecked(on)
    sh.label:SetTextColor(on and 1 or 1, on and 1 or 0.82, on and 1 or 0)
    local ES = Enum.TransmogOutfitSlot
    local cur = (iv.shoulder == ES.ShoulderLeft) and ES.ShoulderLeft or ES.ShoulderRight
    local x = 24 + sh.label:GetStringWidth() + 10
    for i, b in ipairs(sh.sides) do
      b:SetShown(on)
      b:ClearAllPoints(); b:SetPoint("LEFT", sh, "LEFT", x + (i - 1) * 54, 0)
      local mine = ES[b.slotKey] == cur
      b:SetBackdropColor(mine and 0.35 or 0.06, mine and 0.27 or 0.06, mine and 0.1 or 0.08, 1)
    end
    sh:SetWidth(x + (on and 108 or 0)); sh:Show()
    UI.bottomLeft.shoulder = 10 + x + (on and 108 or 0) + 10
    PlaceHelp()
  end
  UI.shoulder.cb:SetScript("OnClick", function(self)
    local slot = ShoulderPrimary()
    if not slot then return end
    local want = self:GetChecked() and true or false
    local ES = Enum.TransmogOutfitSlot
    -- like Blizzard's checkbox, act on the shoulder that is currently selected
    local target = (not want and iv.shoulder == ES.ShoulderLeft) and ES.ShoulderLeft or slot
    local ok, err = pcall(OIx.SetSecondarySlotState, target, want)
    if not ok then UIErrorsFrame:AddMessage("Blizzard rejected the shoulder change: "..tostring(err), 1, 0.3, 0.3) end
    if not want then iv.shoulder = ES.ShoulderRight end
    C_Timer.After(0.1, function() UI.RefreshShoulder(); if search:IsShown() and search.f.mode == "items" then iv.Render() end end)
  end)
  for _, b in ipairs(UI.shoulder.sides) do
    b:SetScript("OnClick", function()
      local ES = Enum.TransmogOutfitSlot
      local want = ES[b.slotKey]
      iv.shoulder = want
      local tf = _G.TransmogFrame; local cp = tf and tf.CharacterPreview
      local okF, sf = pcall(cp.GetSlotFrame, cp, want, Enum.TransmogType.Appearance)
      if okF and sf and tf.SelectSlot then iv.selfSelect = true; pcall(tf.SelectSlot, tf, sf); iv.selfSelect = false end
      UI.RefreshShoulder()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Apply to the "..(self.slotKey == "ShoulderLeft" and "left" or "right").." shoulder"); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
  end
  search:HookScript("OnHide", function() UI.sheath:Hide(); UI.shoulder:Hide() end)
end

---------------------------------------------------------------- attach to Blizzard's window
local function Host() return _G.TransmogFrame or _G.WardrobeFrame end
local dockedByUs = false
---------------------------------------------------------------- reskin
-- One dark, flat window: Blizzard's outfit list + preview + collection, with the Set Finder built in as a fourth column.
local skin = CreateFrame("Frame", "TransmogKitSkin", UIParent, "BackdropTemplate")
skin:Hide()
skin:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=2})
skin:SetBackdropColor(0.035, 0.035, 0.05, 0.97); skin:SetBackdropBorderColor(0.72, 0.58, 0.25, 1)
skin.header = skin:CreateTexture(nil, "BORDER"); skin.header:SetColorTexture(0.10, 0.08, 0.05, 1)
skin.header:SetPoint("TOPLEFT", 2, -2); skin.header:SetPoint("TOPRIGHT", -2, -2); skin.header:SetHeight(22)
skin.headerLine = skin:CreateTexture(nil, "ARTWORK"); skin.headerLine:SetColorTexture(0.72, 0.58, 0.25, 0.8)
skin.headerLine:SetPoint("TOPLEFT", skin.header, "BOTTOMLEFT"); skin.headerLine:SetPoint("TOPRIGHT", skin.header, "BOTTOMRIGHT"); skin.headerLine:SetHeight(1)
skin.title = skin:CreateFontString(nil, "OVERLAY", "GameFontNormal"); skin.title:SetPoint("TOPLEFT", 12, -6)
skin.title:SetText("TRANSMOG|cffffffffKIT|r")
skin.panels = {}

local function Panel(target, key)
  local p = skin.panels[key]
  if not p then
    p = {}
    p.bg = skin:CreateTexture(nil, "BORDER"); p.bg:SetColorTexture(0.07, 0.07, 0.09, 0.95)
    p.edges = {}
    for i = 1, 4 do p.edges[i] = skin:CreateTexture(nil, "ARTWORK"); p.edges[i]:SetColorTexture(0.35, 0.29, 0.15, 0.9) end
    skin.panels[key] = p
  end
  p.bg:ClearAllPoints(); p.bg:SetPoint("TOPLEFT", target, "TOPLEFT", -2, 2); p.bg:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 2, -2)
  local e = p.edges
  for i = 1, 4 do e[i]:ClearAllPoints() end
  e[1]:SetPoint("TOPLEFT", p.bg); e[1]:SetPoint("TOPRIGHT", p.bg); e[1]:SetHeight(1)
  e[2]:SetPoint("BOTTOMLEFT", p.bg); e[2]:SetPoint("BOTTOMRIGHT", p.bg); e[2]:SetHeight(1)
  e[3]:SetPoint("TOPLEFT", p.bg); e[3]:SetPoint("BOTTOMLEFT", p.bg); e[3]:SetWidth(1)
  e[4]:SetPoint("TOPRIGHT", p.bg); e[4]:SetPoint("BOTTOMRIGHT", p.bg); e[4]:SetWidth(1)
end

local hidden = {}
local function Fade(obj)
  if obj and obj.SetAlpha and not hidden[obj] then hidden[obj] = obj:GetAlpha(); obj:SetAlpha(0) end
end
local function Unfade()
  for obj, a in pairs(hidden) do pcall(obj.SetAlpha, obj, a) end
  wipe(hidden)
end

local function ApplySkin(host)
  local wc = host.WardrobeCollection
  local tc = wc and wc.TabContent
  -- Blizzard chrome off
  for _, r in ipairs({host:GetRegions()}) do if r:GetObjectType() == "Texture" then Fade(r) end end
  Fade(host.NineSlice); Fade(host.PortraitContainer); Fade(host.TopTileStreaks); Fade(host.Bg)
  if host.HelpPlateButton then host.HelpPlateButton:Hide() end
  if wc then Fade(wc.Background) end
  if tc then Fade(tc.Background); Fade(tc.Border) end
  if tc and tc.ItemsFrame then Fade(tc.ItemsFrame.Divider) end
  if host.TitleContainer then Fade(host.TitleContainer) end
  -- our frame behind it, stretched to include the finder column
  skin:SetParent(host); skin:SetFrameStrata(host:GetFrameStrata())
  skin:SetFrameLevel(math.max(0, host:GetFrameLevel() - 1))
  skin:ClearAllPoints(); skin:SetPoint("TOPLEFT", host, "TOPLEFT", -2, 2)
  skin:SetPoint("BOTTOMRIGHT", skin.sideFinder and search or host, "BOTTOMRIGHT", skin.sideFinder and 4 or 2, -2)
  -- section cards
  if host.OutfitCollection then Panel(host.OutfitCollection, "outfits") end
  if host.CharacterPreview then Panel(host.CharacterPreview, "preview") end
  if wc then Panel(wc, "collection") end
  if skin.sideFinder then Panel(search, "finder") elseif skin.panels.finder then
    skin.panels.finder.bg:Hide(); for _, e in ipairs(skin.panels.finder.edges) do e:Hide() end end
  if skin.sideFinder and skin.panels.finder then
    skin.panels.finder.bg:Show(); for _, e in ipairs(skin.panels.finder.edges) do e:Show() end end
  skin:Show()
  -- close button moves to the far right of the combined window
  if host.CloseButton then host.CloseButton:ClearAllPoints(); host.CloseButton:SetPoint("TOPRIGHT", skin, "TOPRIGHT", 2, 2) end
end

local function RemoveSkin(host)
  Unfade(); skin:Hide()
  if host and host.HelpPlateButton then host.HelpPlateButton:Show() end
  if host and host.CloseButton then host.CloseButton:ClearAllPoints(); host.CloseButton:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0) end
end

local function LayoutFinder(host, embedded)
  search:SetParent(embedded and host or UIParent)
  if not embedded then search:SetFrameStrata("DIALOG") end
  search:ClearAllPoints()
  if embedded then
    search:SetFrameLevel(host:GetFrameLevel() + 10)
    search:SetPoint("TOPLEFT", host, "TOPRIGHT", 6, -28)
    search:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", 6, 6)
    search:SetWidth(330)
    search:SetBackdropColor(0, 0, 0, 0); search:SetBackdropBorderColor(0, 0, 0, 0)
    sTitle:SetText("|cffc9a24aFINDER|r"); sClose:Hide()
  else
    search:SetSize(330, 600)
    if host and host:IsShown() then search:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0) else search:SetPoint("CENTER") end
    search:SetBackdropColor(0.06, 0.06, 0.08, 0.92); search:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.9)
    sTitle:SetText("TransmogKit  |cffaaaaaaFinder|r"); sClose:Show()
  end
  SROWS = math.max(6, math.min(MAX_ROWS, math.floor((search:GetHeight() - 152) / SROW_H)))
end

---------------------------------------------------------------- Finder tab (next to Situations)
local PAGES = {"ItemsFrame", "SetsFrame", "CustomSetsFrame", "SituationsFrame"}
local finderTab, finderActive, tabsHooked
local restorePage

local function TabLabel(b) return (b.GetText and b:GetText()) or (b.Text and b.Text.GetText and b.Text:GetText()) end

local function RealTabs(wc)
  local out = {}
  local function scan(f, d)
    if d > 3 or not f or not f.GetChildren then return end
    for _, c in ipairs({f:GetChildren()}) do
      if c ~= finderTab and c:IsObjectType("Button") and TabLabel(c) and c:IsShown() then out[#out+1] = c
      else scan(c, d + 1) end
    end
  end
  scan(wc.TabHeaders, 0)
  table.sort(out, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
  return out
end

local pagesHooked
local function SetFinderActive(host, on)
  local tc = host.WardrobeCollection.TabContent
  finderActive = on
  if not pagesHooked then
    pagesHooked = true
    -- clicking a character slot makes Blizzard re-open its Items page; keep it closed while the Finder is up
    for _, k in ipairs(PAGES) do
      local page = tc[k]
      if page and page.HookScript then
        page:HookScript("OnShow", function(self)
          if finderActive then
            self:Hide()
            C_Timer.After(0, function() if finderActive and self:IsShown() then self:Hide() end end)
          end
        end)
      end
    end
  end
  if on then
    restorePage = nil
    for _, k in ipairs(PAGES) do
      local page = tc[k]
      if page and page:IsShown() then restorePage = restorePage or page; page:Hide() end
    end
    search:SetParent(tc); search:SetFrameLevel(tc:GetFrameLevel() + 5)
    search:ClearAllPoints(); search:SetPoint("TOPLEFT", tc, "TOPLEFT", 6, -6); search:SetPoint("BOTTOMRIGHT", tc, "BOTTOMRIGHT", -6, 6)
    search:SetBackdropColor(0, 0, 0, 0); search:SetBackdropBorderColor(0, 0, 0, 0)
    sTitle:SetText("|cffc9a24aFINDER|r"); sClose:Hide()
    SROWS = math.max(6, math.min(MAX_ROWS, math.floor(((tc:GetHeight() or 600) - 164) / SROW_H)))
    search:Show(); SearchUpdate()
  else
    search:Hide()
    local anyShown = false
    for _, k in ipairs(PAGES) do local pg = tc[k]; if pg and pg:IsShown() then anyShown = true end end
    if not anyShown and restorePage then restorePage:Show() end
  end
  if finderTab then finderTab.sel:SetShown(on); finderTab.text:SetTextColor(on and 1 or 0.8, on and 0.82 or 0.7, on and 0.3 or 0.5) end
end

local function BuildFinderTab(host)
  local wc = host.WardrobeCollection
  if not (wc and wc.TabHeaders and wc.TabContent) then return false end
  local tabs = RealTabs(wc)
  local last = tabs[#tabs]
  if not last then return false end
  if not finderTab then
    finderTab = CreateFrame("Button", "TransmogKitFinderTab", wc.TabHeaders)
    finderTab.text = finderTab:CreateFontString(nil, "OVERLAY")
    local fo = last.Text and last.Text.GetFontObject and last.Text:GetFontObject()
    finderTab.text:SetFontObject(fo or GameFontNormal); finderTab.text:SetPoint("CENTER", 0, 1)
    finderTab.text:SetText("Finder")
    finderTab.sel = finderTab:CreateTexture(nil, "ARTWORK"); finderTab.sel:SetColorTexture(0.9, 0.72, 0.3, 1)
    finderTab.sel:SetPoint("BOTTOMLEFT", 6, 0); finderTab.sel:SetPoint("BOTTOMRIGHT", -6, 0); finderTab.sel:SetHeight(2); finderTab.sel:Hide()
    finderTab:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    finderTab:GetHighlightTexture():SetAlpha(0.25)
    finderTab:SetScript("OnClick", function() SetFinderActive(host, true) end)
  end
  finderTab:SetParent(wc.TabHeaders)
  finderTab:SetSize(last:GetWidth(), last:GetHeight())
  finderTab:ClearAllPoints(); finderTab:SetPoint("LEFT", last, "RIGHT", 2, 0)
  finderTab:Show()
  if not tabsHooked then
    for _, t in ipairs(tabs) do
      -- switch the Finder off before Blizzard opens the page, so the page guard lets it through
      if t:HasScript("PreClick") then t:HookScript("PreClick", function() if finderActive then SetFinderActive(host, false) end end) end
      t:HookScript("OnClick", function()
        if finderActive then
          SetFinderActive(host, false)
          -- Blizzard may think this tab was already open; make sure its page is visible again
          C_Timer.After(0, function()
            local anyShown = false
            for _, k in ipairs(PAGES) do local pg = wc.TabContent[k]; if pg and pg:IsShown() then anyShown = true end end
            if not anyShown and restorePage then restorePage:Show() end
          end)
        end
      end)
    end
    tabsHooked = true
  end
  return true
end

local function AttachToTransmog()
  local host = Host(); if not host or not host:IsShown() then return end
  if DB.scale then host:SetScale(DB.scale) end
  strip:SetParent(host); strip:SetFrameLevel(host:GetFrameLevel() + 20)
  strip:ClearAllPoints(); strip:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 14, 96)
  strip:Show()
  local cp = host.CharacterPreview
  -- sit above everything in the character preview (its model scene uses high frame levels)
  local top = host:GetFrameLevel()
  local function scan(f, d)
    if not f or d > 4 or not f.GetChildren then return end
    top = math.max(top, f:GetFrameLevel() or 0)
    for _, c in ipairs({f:GetChildren()}) do scan(c, d + 1) end
  end
  scan(cp, 0)
  titleB:SetParent(host); titleB:SetFrameStrata(host:GetFrameStrata()); titleB:SetFrameLevel(math.min(9000, top + 10))
  titleB:ClearAllPoints()
  if cp then titleB:SetPoint("TOP", cp, "TOP", 0, -76) else titleB:SetPoint("TOP", host, "TOP", 0, -110) end
  titleB:SetAlpha(1); titleB:Show()
  TitleRefresh()
  StripRefresh()
  local embedded = not DB.noSkin
  HookSlotSelect()
  local asTab = DB.finderMode ~= "side" and BuildFinderTab(host)
  if asTab then
    SetFinderActive(host, TransmogKitAccountDB.opts.autoOpen ~= false)
  else
    if finderTab then finderTab:Hide() end
    if not DB.hideSearch or embedded then
      LayoutFinder(host, embedded)
      if not search:IsShown() then search:Show(); dockedByUs = true else SearchUpdate() end
    end
  end
  skin.sideFinder = not asTab
  if embedded then ApplySkin(host) else RemoveSkin(host) end
end

local function DumpFrames()
  local host = Host(); if not host then Print("Open the transmog window first.") return end
  local out = {}
  local function walk(f, depth, path)
    if depth > 4 then return end
    for k, v in pairs(f) do
      if type(v) == "table" and type(k) == "string" and v.GetObjectType and k ~= "parent" then
        local ok, ot = pcall(v.GetObjectType, v)
        if ok then out[#out+1] = path.."."..k.." ("..ot..")"; if v ~= f and v.GetChildren then walk(v, depth + 1, path.."."..k) end end
      end
    end
  end
  walk(host, 1, host:GetName() or "host")
  DB.frameDump = out
  Print("Saved "..#out.." frame names. /reload, then send me WTF\\Account\\<account>\\<realm>\\<character>\\SavedVariables\\TransmogKit.lua")
end

---------------------------------------------------------------- outfit flyout (secure)
-- Blizzard outfits can live on action bars. We find those action slots and point
-- secure buttons at them, so clicking a flyout button = clicking Blizzard's own outfit icon.
local function ScanOutfitActions()
  local found = {}
  for slot = 1, 180 do
    local t, id = GetActionInfo(slot)
    if t and not STD[t] and (t:lower():find("outfit") or t:lower():find("transmog")) then
      found[#found+1] = {slot=slot, id=id, icon=GetActionTexture(slot), name=GetActionText(slot)}
    end
  end
  return found
end

local fly = CreateFrame("Button", "TransmogKitFlyout", UIParent, "BackdropTemplate")
fly:SetSize(40, 40); fly:SetPoint("CENTER", 0, -200)
fly:SetMovable(true); fly:RegisterForDrag("LeftButton"); fly:SetClampedToScreen(true)
fly:RegisterForClicks("LeftButtonUp", "RightButtonUp")
fly.icon = fly:CreateTexture(nil, "ARTWORK"); fly.icon:SetAllPoints(); fly.icon:SetTexture(1723997)
fly:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
fly.list = CreateFrame("Frame", "TransmogKitFlyoutList", fly, "SecureFrameTemplate")
fly.list:SetPoint("BOTTOM", fly, "TOP", 0, 4); fly.list:SetSize(1, 1); fly.list:Hide()
fly.buttons = {}
fly:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
fly:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint(); DB.flyPos = {p, rp, x, y}
end)
fly:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("TransmogKit Outfits")
  GameTooltip:AddLine("Left-click: show/hide outfits", 1,1,1); GameTooltip:AddLine("Right-click: open transmog search", 1,1,1)
  GameTooltip:AddLine("Shift-drag: move", 1,1,1); GameTooltip:Show()
end)
fly:SetScript("OnLeave", GameTooltip_Hide)

local function BuildFlyout()
  if InCombatLockdown() then Print("Can't rebuild the outfit list in combat.") return false end
  for _, b in ipairs(fly.buttons) do b:Hide() end
  local outfits = ScanOutfitActions()
  if #outfits == 0 then
    Print("No outfits found on your action bars. Drag each outfit icon from the transmog window onto any bar slot (a hidden bar works - e.g. Action Bar 8 turned off in Edit Mode), then click this button again.")
    return false
  end
  for i, o in ipairs(outfits) do
    local b = fly.buttons[i]
    if not b then
      b = CreateFrame("Button", "TransmogKitOutfit"..i, fly.list, "SecureActionButtonTemplate")
      b:SetSize(36, 36); b:RegisterForClicks("AnyUp", "AnyDown")
      b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
      b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetAction(self:GetAttribute("action")); GameTooltip:Show()
      end)
      b:SetScript("OnLeave", GameTooltip_Hide)
      b:HookScript("PostClick", function() C_Timer.After(0.3, QueueTransmogCheck) end)
      fly.buttons[i] = b
    end
    b:SetAttribute("type", "action"); b:SetAttribute("action", o.slot)
    b:ClearAllPoints(); b:SetPoint("BOTTOM", fly.list, "BOTTOM", 0, (i-1)*38)
    b.icon:SetTexture(o.icon or QMARK)
    b:Show()
  end
  return true
end
fly:SetScript("OnClick", function(_, btn)
  if btn == "RightButton" then SlashCmdList.TRANSMOGKIT("") return end
  if InCombatLockdown() then return end
  if fly.list:IsShown() then fly.list:Hide() elseif BuildFlyout() then fly.list:Show() end
end)

local function Probe()
  if not OI then Print("C_TransmogOutfitInfo not found.") return end
  local names = {}
  for k in pairs(OI) do names[#names+1] = k end
  table.sort(names); Print("Outfit API: "..table.concat(names, ", "))
  Print("Active outfit: "..tostring(ActiveOutfitID()).."  Viewed outfit: "..tostring(ViewedOutfitID()))
  for slot = 1, 180 do
    local t, id = GetActionInfo(slot)
    if t and not STD[t] then Print("Action slot "..slot..": type="..tostring(t).." id="..tostring(id)) end
  end
end

---------------------------------------------------------------- events
TK:RegisterEvent("ADDON_LOADED")
TK:RegisterEvent("PLAYER_LOGIN")
TK:RegisterEvent("PLAYER_REGEN_ENABLED")
TK:RegisterEvent("TRANSMOGRIFY_OPEN")
TK:RegisterEvent("TRANSMOGRIFY_CLOSE")
TK:RegisterEvent("TRANSMOGRIFY_SUCCESS")
for _, ev in ipairs({"TRANSMOG_DISPLAYED_OUTFIT_CHANGED", "TRANSMOG_OUTFITS_CHANGED", "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_SETS_UPDATE_FAVORITE", "VIEWED_TRANSMOG_OUTFIT_SECONDARY_SLOTS_CHANGED"}) do
  pcall(TK.RegisterEvent, TK, ev)
end
TK:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    TransmogKitDB = TransmogKitDB or {}            -- old per-character file (migration source only)
    TransmogKitAccountDB = TransmogKitAccountDB or {}
    TransmogKitAccountDB.chars = TransmogKitAccountDB.chars or {}
    TransmogKitAccountDB.opts = TransmogKitAccountDB.opts or {}
    if TransmogKitAccountDB.opts.autoOpen == nil then TransmogKitAccountDB.opts.autoOpen = true end
    TransmogKitAccountDB.looks = TransmogKitAccountDB.looks or {}
    TransmogKitAccountDB.effectFavs = TransmogKitAccountDB.effectFavs or {}
    BindDB()
    DB.kits = DB.kits or {}
    -- migrate v0.1-0.3 "looks" onto their outfit slots
    if DB.looks then
      for _, look in ipairs(DB.looks) do
        if look.outfitID and not DB.kits[look.outfitID] then
          DB.kits[look.outfitID] = {ground=look.ground, flying=look.flying, swimming=look.swimming, hearth=look.hearth, title=look.title}
        end
      end
      DB.looks = nil
    end
    if DB.flyPos then fly:ClearAllPoints(); fly:SetPoint(DB.flyPos[1], UIParent, DB.flyPos[2], DB.flyPos[3], DB.flyPos[4]) end
    fly:SetShown(not DB.hideFly)
  elseif event == "PLAYER_LOGIN" then
    if TransmogKitAccountDB and (not DB or DB.charKey ~= CharKey()) then BindDB(); DB.kits = DB.kits or {} end
    C_Timer.After(6, function() pcall(ScanMounts); pcall(GetHearthList) end)
    C_Timer.After(3, function()
      pcall(ValidateOwner); ApplyActiveOutfit(true)
      if DB and TransmogKitAccountDB.opts.verbose then
        local aid = ActiveOutfitID(); local k = aid and FindKit(aid)
        local n = 0; for _ in pairs(DB.kits) do n = n + 1 end
        local ver = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version")
        Print(("v%s | %s: worn outfit %s (%s) - %s. %d outfit(s) saved. Last save in file: %s. File owner ...%s, this character ...%s."):format(
          tostring(ver), tostring(UnitName("player")), tostring(aid), tostring(aid and OutfitName(aid)),
          (k and (k.ground or k.flying or k.swimming or k.hearth)) and "mounts/hearth found" or "nothing saved for it", n,
          tostring(DB.lastSave or "none"), tostring(DB.owner and DB.owner:sub(-6)), tostring((UnitGUID("player") or "?"):sub(-6))))
        Print(("storage check - character file: %s | account file: %s"):format(tostring(TransmogKitDB and TransmogKitDB.probe or "none"),
          tostring(TransmogKitAccountDB and TransmogKitAccountDB.probe or "none")))
      end
    end)
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pendingMacro then pendingMacro = false; ApplyActiveOutfit(true) end
  elseif event == "TRANSMOGRIFY_OPEN" then
    iv.weapons = nil
    C_Timer.After(0.1, AttachToTransmog)
  elseif event == "TRANSMOGRIFY_CLOSE" then
    strip:Hide()
    search:Hide(); dockedByUs = false
    LayoutFinder(nil, false)
    QueueTransmogCheck()
  elseif event == "TRANSMOG_COLLECTION_UPDATED" or event == "TRANSMOG_SETS_UPDATE_FAVORITE" then
    search.cache = nil
    if search:IsShown() and not TK.refreshQueued then
      TK.refreshQueued = true
      C_Timer.After(0.2, function() TK.refreshQueued = false; if search:IsShown() then SearchUpdate() end end)
    end
  else
    QueueTransmogCheck()
    if strip:IsShown() then StripRefresh() end
    if UI.ev and UI.ev:IsShown() then C_Timer.After(0.15, function() if UI.ev:IsShown() then UI.ev.Render() end end) end
    if UI.RefreshSheath then C_Timer.After(0.15, UI.RefreshSheath) end
    if UI.RefreshShoulder then C_Timer.After(0.15, UI.RefreshShoulder) end
  end
end)

SLASH_TRANSMOGKIT1, SLASH_TRANSMOGKIT2 = "/tmk", "/transmogkit"
SlashCmdList.TRANSMOGKIT = function(msg)
  msg = (msg or ""):lower()
  if msg == "verbose" or msg == "quiet" then
    local o = TransmogKitAccountDB.opts
    o.verbose = not o.verbose
    Print(o.verbose and "confirmation messages on" or "confirmation messages off")
  elseif msg == "kits" then
    Print(("character=%s  file owner matches=%s  transmog window open=%s"):format(tostring(UnitName("player")), tostring(DB.owner == UnitGUID("player")),
      tostring(_G.TransmogFrame and _G.TransmogFrame:IsShown() and true or false)))
    local n = 0
    for _ in pairs(DB.kits) do n = n + 1 end
    Print(("active outfit=%s (%s)  viewed outfit=%s (%s)  saved outfits=%d"):format(tostring(ActiveOutfitID()), tostring(OutfitName(ActiveOutfitID())),
      tostring(ViewedOutfitID()), tostring(OutfitName(ViewedOutfitID())), n))
    for oid, k in pairs(DB.kits) do
      Print(("  [%s] %s  ground=%s fly=%s swim=%s hearth=%s title=%s exists=%s"):format(tostring(oid), tostring(k.name),
        tostring(k.ground and k.ground.name), tostring(k.flying and k.flying.name), tostring(k.swimming and k.swimming.name),
        tostring(k.hearth and k.hearth.name), tostring(k.title), tostring(OutfitExists(oid))))
    end
  elseif msg == "probe" then Probe()
  elseif msg == "frames" then DumpFrames()
  elseif msg == "title" then
    local p, rel, rp, x, y = titleB:GetPoint(1)
    Print(("title box: shown=%s visible=%s strata=%s level=%d parent=%s anchor=%s %s %s"):format(
      tostring(titleB:IsShown()), tostring(titleB:IsVisible()), titleB:GetFrameStrata(), titleB:GetFrameLevel(),
      titleB:GetParent() and (titleB:GetParent():GetName() or "?") or "none", tostring(p), tostring(rel and rel.GetName and rel:GetName()), tostring(rp)))
  elseif msg == "button" then DB.hideFly = not DB.hideFly; fly:SetShown(not DB.hideFly)
  elseif msg == "skin" then
    DB.noSkin = not DB.noSkin; Print("Reskin: "..(DB.noSkin and "off (Blizzard look)" or "on"))
    if Host() and Host():IsShown() then AttachToTransmog() end
  elseif msg:match("^scale") then
    local v = tonumber(msg:match("scale%s+([%d%.]+)"))
    if v and v >= 0.5 and v <= 1.5 then DB.scale = v; if Host() then Host():SetScale(v) end; Print("Transmog window scale: "..v)
    else Print("Usage: /tmk scale 0.85  (0.5 - 1.5)") end
  elseif msg == "side" or msg == "tab" then
    DB.finderMode = msg; Print("Set Finder shown as: "..(msg == "side" and "side column" or "tab next to Situations"))
    if Host() and Host():IsShown() then search:Hide(); AttachToTransmog() end
  elseif msg == "dock" then DB.hideSearch = not DB.hideSearch; Print("Set Finder auto-open: "..(DB.hideSearch and "off" or "on"))
  elseif msg == "macros" then ApplyActiveOutfit(true); Print("Macros refreshed for "..OutfitName(ActiveOutfitID()))
  else
    if search:IsShown() then search:Hide() else
      if not (Host() and Host():IsShown()) then LayoutFinder(nil, false) end
      search:Show()
    end
  end
end
