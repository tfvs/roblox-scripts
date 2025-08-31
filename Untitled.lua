-- ===== CONFIG =====
local displayAssetId = 116155168863313
local timerAssetId   = 128607699299345

-- Services
local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ===== GLOBAL ASSET TEMPLATES =====
local DisplayTemplate
local TimerTemplate

local function safeLoadAsset(assetId)
    local ok, obj = pcall(function()
        return game:GetObjects("rbxassetid://"..assetId)[1]
    end)
    if not ok or not obj then
        return nil
    end
    return obj
end

DisplayTemplate = safeLoadAsset(displayAssetId)
TimerTemplate   = safeLoadAsset(timerAssetId)

-- ===== MONEY PARSING =====
local suffixes = {K=1e3, M=1e6, B=1e9, T=1e12, Qa=1e15, Qi=1e18}
local function parseGeneration(text)
    if not text then return 0 end
    text = text:match("^%$(.+)") or text
    text = text:gsub("/S$", ""):gsub(",", "")
    local numberStr = text:match("^[%d%.]+")
    local suffix = text:match("[%a]+")
    local number = tonumber(numberStr) or 0
    if suffix and suffixes[suffix] then number = number * suffixes[suffix] end
    return number
end

-- ===== HELPERS =====
local function stripPossessive(s)
    if not s then return nil end
    s = s:gsub("%s+$","")
    s = s:gsub("[’']s$","")
    return s:gsub("%s+$","")
end

local function ieq(a,b)
    if not a or not b then return false end
    return string.lower(a) == string.lower(b)
end

local function anchorAllBaseParts(root)
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
        end
    end
end

-- ===== GLOBAL STATE =====
local currentHighestOverhead = nil
local currentBillboard = nil
local currentModelHighlight = nil
local currentPartHighlight = nil
local currentMaxVal = -1
local currentTopOwnerName = nil
local plotToTimer = {}
local playerHighlights = {}

-- ===== CLEANUP =====
local function clearCurrentVisuals()
    if currentBillboard then currentBillboard:Destroy() currentBillboard = nil end
    if currentModelHighlight then currentModelHighlight:Destroy() currentModelHighlight = nil end
    if currentPartHighlight then currentPartHighlight:Destroy() currentPartHighlight = nil end
end

local function resetCurrentHighest(setMaxToZero)
    clearCurrentVisuals()
    currentHighestOverhead = nil
    currentTopOwnerName = nil
    currentMaxVal = setMaxToZero and 0 or -1
end

-- ===== HIGHEST GENERATION DISPLAY =====
local function getOwnerFromPlot(plot)
    local multiplierPart = plot:FindFirstChild("Multiplier", true)
    local parentForSign = multiplierPart and multiplierPart.Parent or plot
    local plotSign = parentForSign:FindFirstChild("PlotSign") or parentForSign:FindFirstChild("PlotSign", true)
    if not plotSign then plotSign = plot:FindFirstChild("PlotSign", true) end
    if not plotSign then return nil end
    local label = plotSign:FindFirstChildWhichIsA("TextLabel", true)
    return label and stripPossessive(label.Text) or nil
end

local function updateHighestDisplay()
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return end

    resetCurrentHighest(true)
    local bestVal, bestOverhead, bestPlot = -1, nil, nil

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if plot:IsA("Model") or plot:IsA("Folder") then
            local plotBestVal, plotBestOverhead = -1, nil
            for _, obj in ipairs(plot:GetDescendants()) do
                if obj.Name == "AnimalOverhead" and obj:IsA("BillboardGui") then
                    local genLabel = obj:FindFirstChild("Generation")
                    if genLabel and genLabel:IsA("TextLabel") then
                        local val = parseGeneration(genLabel.Text)
                        if val > plotBestVal then
                            plotBestVal, plotBestOverhead = val, obj
                        end
                    end
                end
            end
            if plotBestOverhead and plotBestVal > bestVal then
                bestVal, bestOverhead, bestPlot = plotBestVal, plotBestOverhead, plot
            end
        end
    end

    if not bestOverhead then return end

    currentTopOwnerName = getOwnerFromPlot(bestPlot)
    currentHighestOverhead, currentMaxVal = bestOverhead, bestVal

    local originalDisplayName = bestOverhead:FindFirstChild("DisplayName")
    if not originalDisplayName then return end

    local baseParent = bestOverhead.Parent
    for _=1,4 do if baseParent then baseParent = baseParent.Parent end end
    local nameToFind, foundTargetChild = originalDisplayName.Text, nil

    for extra=0,2 do
        local candidate = baseParent
        for _=1,extra do if candidate then candidate = candidate.Parent end end
        if candidate then
            local child = candidate:FindFirstChild(nameToFind)
            if child then foundTargetChild = child break end
        end
    end
    if not foundTargetChild then return end

    local modelHighlight = Instance.new("Highlight")
    modelHighlight.Adornee, modelHighlight.FillTransparency, modelHighlight.FillColor =
        foundTargetChild, 0.75, Color3.fromRGB(255,0,0)
    modelHighlight.OutlineTransparency, modelHighlight.OutlineColor = 0, Color3.fromRGB(255,0,0)
    modelHighlight.Parent = foundTargetChild
    currentModelHighlight = modelHighlight

    local billboardParentPart = foundTargetChild:IsA("BasePart") and foundTargetChild
        or foundTargetChild:FindFirstChildWhichIsA("BasePart", true)
    if not billboardParentPart then return end

    if DisplayTemplate then
        local displayBillboard = DisplayTemplate:FindFirstChild("BillboardGui", true)
        if displayBillboard then
            local clone = displayBillboard:Clone()
            clone.AlwaysOnTop, clone.MaxDistance, clone.StudsOffset = true, 0, Vector3.new(0,3,0)
            clone.Parent = billboardParentPart
            local cloneDisplay = clone:FindFirstChild("DisplayName", true)
            if cloneDisplay then cloneDisplay.Text = originalDisplayName.Text end
            local origGen, cloneGen = bestOverhead:FindFirstChild("Generation"), clone:FindFirstChild("Generation", true)
            if cloneGen and origGen then cloneGen.Text = origGen.Text end
            currentBillboard = clone
        end
    end

    local partHighlight = Instance.new("Highlight")
    partHighlight.Adornee, partHighlight.FillTransparency, partHighlight.FillColor =
        billboardParentPart, 0.75, Color3.fromRGB(255,0,0)
    partHighlight.OutlineTransparency, partHighlight.OutlineColor = 0, Color3.fromRGB(255,0,0)
    partHighlight.Parent = Workspace
    currentPartHighlight = partHighlight
end

-- ===== TIMER LOOP =====
task.spawn(function()
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return end
    if not TimerTemplate then return end

    while true do
        for _, plot in ipairs(plotsFolder:GetChildren()) do
            if not plotToTimer[plot] then
                local multiplierPart = plot:FindFirstChild("Multiplier", true)
                if multiplierPart and multiplierPart:IsA("BasePart") then
                    local timerClone = TimerTemplate:Clone()
                    timerClone.Parent = plot
                    anchorAllBaseParts(timerClone)

                    if timerClone:IsA("Model") then
                        if not timerClone.PrimaryPart then
                            for _, d in ipairs(timerClone:GetDescendants()) do
                                if d:IsA("BasePart") then timerClone.PrimaryPart = d break end
                            end
                        end
                        if timerClone.PrimaryPart then
                            timerClone:SetPrimaryPartCFrame(multiplierPart.CFrame)
                        end
                    elseif timerClone:IsA("BasePart") then
                        timerClone.CFrame = multiplierPart.CFrame
                    else
                        local anyBase = timerClone:FindFirstChildWhichIsA("BasePart", true)
                        if anyBase then anyBase.CFrame = multiplierPart.CFrame end
                    end

                    local timerBillboard = timerClone:FindFirstChild("BillboardGui", true)
                    local timerTextLabel = timerBillboard and timerBillboard:FindFirstChild("Timer", true)
                    if timerBillboard and timerTextLabel and timerTextLabel:IsA("TextLabel") then
                        timerBillboard.AlwaysOnTop = true
                        plotToTimer[plot] = {timerClone = timerClone, targetTextLabel = timerTextLabel}
                    else
                        timerClone:Destroy()
                    end
                end
            end

            local entry = plotToTimer[plot]
            if entry and entry.targetTextLabel then
                local remainingTimeLabel
                for _, obj in ipairs(plot:GetDescendants()) do
                    if obj.Name == "RemainingTime" and obj:IsA("TextLabel") then
                        remainingTimeLabel = obj break
                    end
                end
                local sourceText = remainingTimeLabel and remainingTimeLabel.Text or ""
                if sourceText == "0" or ieq(sourceText,"0s") then
                    entry.targetTextLabel.Text, entry.targetTextLabel.TextColor3 = "UNLOCKED", Color3.fromRGB(0,255,0)
                elseif sourceText == "" then
                    entry.targetTextLabel.Text, entry.targetTextLabel.TextColor3 = "60s", Color3.fromRGB(255,255,255)
                else
                    entry.targetTextLabel.Text, entry.targetTextLabel.TextColor3 = sourceText, Color3.fromRGB(255,255,255)
                end
            end
        end
        task.wait(1)
    end
end)

-- ===== PLAYER ESP =====
local function addPlayerHighlight(plr)
    local function highlightCharacter(char)
        if playerHighlights[plr] then playerHighlights[plr]:Destroy() end
        local highlight = Instance.new("Highlight")
        highlight.Adornee = char
        highlight.FillColor = Color3.fromRGB(173, 216, 230) -- Light blue
        highlight.FillTransparency = 0.75
        highlight.OutlineTransparency = 0
        highlight.OutlineColor = Color3.fromRGB(173, 216, 230)
        highlight.Parent = char
        playerHighlights[plr] = highlight
    end

    if plr.Character then
        highlightCharacter(plr.Character)
    end

    plr.CharacterAdded:Connect(function(char)
        highlightCharacter(char)
    end)
end

-- Continuously override transparency
RunService.RenderStepped:Connect(function()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= Players.LocalPlayer and plr.Character then
            for _, part in ipairs(plr.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.LocalTransparencyModifier = 0
                end
            end
        end
    end
end)

-- Add ESP for all existing and future players
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= Players.LocalPlayer then
        addPlayerHighlight(plr)
    end
end
Players.PlayerAdded:Connect(function(plr)
    if plr ~= Players.LocalPlayer then
        addPlayerHighlight(plr)
    end
end)

-- ===== INITIAL EXECUTION =====
updateHighestDisplay()
task.spawn(function()
    while true do
        updateHighestDisplay()
        task.wait(2)
    end
end)
Players.PlayerAdded:Connect(updateHighestDisplay)
Players.PlayerRemoving:Connect(function(player)
    clearCurrentVisuals()
    for plot, entry in pairs(plotToTimer) do
        if entry.timerClone then entry.timerClone:Destroy() end
        plotToTimer[plot] = nil
    end
    resetCurrentHighest(true)
    updateHighestDisplay()
end)

loadstring(game:HttpGet('https://raw.githubusercontent.com/Lucasfin000/SpaceHub/main/UESP'))()
