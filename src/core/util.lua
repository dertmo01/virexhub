-- src/core/util.lua -- character lookups and the shared knockback stripper.
local Players = game:GetService("Players")
local Player  = Players.LocalPlayer

local M = {}

function M.humanoid()
    local c = Player.Character
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end

function M.root()
    local c = Player.Character
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end

local PUSHBACK_NAMES = {
    "Pushback","PushBack","AntiPushback","KnockbackController",
    "Knockback","StunController","Stunned","Stun","Freeze","Frozen",
}

-- Strips any per-frame velocity the game applies to push us off base. Called on
-- every frame of a walk and after each hop; without it the game wins.
function M.stripPushBack()
    local c = Player.Character
    if not c then return false end
    local hit = false
    for _, name in ipairs(PUSHBACK_NAMES) do
        for _, obj in ipairs(c:GetChildren()) do
            if obj.Name == name then
                hit = true
                pcall(function()
                    if obj:IsA("BodyVelocity") or obj:IsA("BodyGyro") then
                        obj.Velocity = Vector3.zero
                    end
                    if obj:IsA("LinearVelocity") then obj.Force = Vector3.zero end
                    if obj:IsA("AlignPosition") then obj.Position = Vector3.zero end
                end)
            end
        end
    end
    return hit
end

return M
