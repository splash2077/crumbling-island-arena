if not Hero then
    Hero = class({}, nil, WearableOwner)
end

function Hero:constructor(data)
    DynamicEntity.constructor(self, round) -- Intended

    self.protected = false
    self.modifierImmune = false
    self.removeOnDeath = false
    self.collisionType = COLLISION_TYPE_RECEIVER

    self.soundsStarted = {}
    self.wearables = {}
    self.wearableParticles = {}
    self.mappedParticles = {}
    self.wearableSlots = {}
    self.mixins = {}
    self.lastKnockbackSource = nil
    self.lastKnockbackTimer = 0
    self.data = data
    self.wearableRemoveTimer = 0
    self.hideOnDeathTimer = 0
end

function Hero:AddMixin(mixin)
    mixin:Init(self)

    self.mixins[mixin] = true
end

function Hero:RemoveMixin(mixin)
    mixin:Dispose()
    
    self.mixins[mixin] = nil
end

function Hero:FindMixin(t)
    for mixin, _ in pairs(self.mixins) do
        if instanceof(mixin, t) then
            return mixin
        end
    end

    return nil
end

function Hero:SetUnit(unit)
    getbase(Hero).SetUnit(self, unit)
    unit.hero = self

    Wrappers.WrapAbilitiesFromHeroData(unit, self.data)
end

function Hero:GetShortName()
    return self:GetName():sub(("npc_dota_hero_"):len() + 1)
end

function Hero:LoadWearables()
    local cosmetics = Cosmetics[self:GetShortName()]
    local result = {}

    self.passEnabled = PlayerResource:HasCustomGameTicketForPlayerID(self.owner.id)

    if cosmetics then
        local function processIgnore(t)
            local ignore = t.ignore

            if ignore then
                for _, item in pairs(tostring(ignore):split(",")) do
                    table.insert(result, { ignore = tonumber(item) })
                end
            end
        end

        if cosmetics.ignore == "all" then
            for _, item in pairs(self:FindDefaultItems()) do
                table.insert(result, { ignore = item.id })
            end
        else
            processIgnore(cosmetics)
        end

        local ordered = {}

        for id, entry in pairs(cosmetics) do
            if type(entry) == "table" then
                ordered[tonumber(id)] = entry
            end
        end

        for _, entry in ipairs(ordered) do
            local t = entry.type
            local passBase = (t == "pass_base" and (self.passEnabled or self.owner.passLevel ~= nil))
            local elite = (t == "elite")

            if elite then
                self.awardEnabled = GameRules.GameMode:IsAwardedForSeason(self.owner.id, entry.season)

                elite = elite and self.awardEnabled
            end

            local passLevel = (t == "pass" and entry.level <= (self.owner.passLevel or 0))

            if passBase or elite or passLevel then
                processIgnore(entry)

                if entry.style then
                    local pair = entry.style:split(":")
                    table.insert(result, { id = tonumber(pair[1]), style = tonumber(pair[2]) })
                end

                if entry.set then
                    table.insert(result, entry.set)
                end

                if entry.item then
                    for _, item in pairs(tostring(entry.item):split(",")) do
                        table.insert(result, tonumber(item))
                    end
                end

                if entry.particles then
                    for original, asset in pairs(entry.particles) do
                        self.mappedParticles[original] = asset
                    end
                end

                if entry.emote then
                    self:GetUnit():RemoveAbility("placeholder_emote")
                    self:GetUnit():AddAbility("emote"):SetLevel(1)
                end

                if entry.taunt then
                    self:GetUnit():RemoveAbility("placeholder_taunt")

                    local ability = entry.taunt.type == "static" and "taunt_static" or "taunt_moving"
                    local taunt = self:GetUnit():AddAbility(ability)
                    local length = entry.taunt.length

                    if length == nil then
                        length = 1.5
                    end

                    taunt:SetLevel(1)
                    taunt.length = length
                    taunt.activity = entry.taunt.activity
                    taunt.sound = entry.taunt.sound
                    taunt.translate = entry.taunt.translate
                end
            end
        end
    end

    self:LoadItems(unpack(result))
end

function Hero:EmitSound(sound, location)
    getbase(Hero).EmitSound(self, sound, location)

    table.insert(self.soundsStarted, sound)
end

function Hero:SetOwner(owner)
    local c = GameRules.GameMode.TeamColors[owner.team]
    local name = IsInToolsMode() and "Player" or PlayerResource:GetPlayerName(owner.id)

    self.owner = owner
    self.unit:SetControllableByPlayer(owner.id, true)
    self.unit:SetCustomHealthLabel(name, c[1], c[2], c[3])
    PlayerResource:SetOverrideSelectionEntity(owner.id, self.unit)

    if #self.wearables == 0 then
        self:LoadWearables()
    end
end

function Hero:IsAwardEnabled()
    return self.awardEnabled
end

function Hero:GetPos()
    return self.unit:GetAbsOrigin()
end

function Hero:GetRad()
    return 64
end

function Hero:TestFalling()
    return Spells.TestCircle(self:GetPos(), 80)
end

function Hero:GetHealth()
    return math.floor(self.unit:GetHealth())
end

function Hero:Alive()
    return IsValidEntity(self.unit) and self.unit:IsAlive()
end

function Hero:SetPos(pos)
    self.unit:SetAbsOrigin(pos)
end

function Hero:SetHealth(health)
    self.unit:SetHealth(math.floor(health))
end

function Hero:SwapAbilities(from, to)
    self.unit:SwapAbilities(from, to, false, true)
end

function Hero:IsInvulnerable()
    for _, modifier in pairs(self:AllModifiers()) do
        if modifier.IsInvulnerable then
            local result = modifier:IsInvulnerable(self)

            if result == true then
                return true
            end
        end
    end

    return self.invulnerable
end

function Hero:Damage(...)
    getbase(Hero).Damage(self, ...)
    GameRules.GameMode:OnDamageDealt(self, ...)
end

function Hero:OnDeath()
    for mixin, _ in pairs(self.mixins) do
        mixin:Dispose()
    end

    self.mixins = {}

    if self.data and self.data.removeWearablesOnDeath then
        self.wearableRemoveTimer = 1

        if self.data.removeWearablesDelay then
            self.wearableRemoveTimer = math.floor(self.data.removeWearablesDelay * 30)
        end
    end

    if self.data and self.data.hideOnDeathDelay then
        self.hideOnDeathTimer = math.floor(self.data.hideOnDeathDelay * 30)
    end
end

function Hero:Heal(amount)
    if amount == nil then
        amount = 3
    end

    if self.unit:IsAlive() then
        self.unit:SetHealth(self.unit:GetHealth() + amount)

        local sign = ParticleManager:CreateParticle("particles/msg_fx/msg_heal.vpcf", PATTACH_CUSTOMORIGIN, mode)
        ParticleManager:SetParticleControl(sign, 0, self:GetPos())
        ParticleManager:SetParticleControl(sign, 1, Vector(10, amount, 0))
        ParticleManager:SetParticleControl(sign, 2, Vector(2, 2, 0))
        ParticleManager:SetParticleControl(sign, 3, Vector(100, 255, 50))
        ParticleManager:ReleaseParticleIndex(sign)

        self.round.statistics:IncreaseHealingReceived(self.owner)
    end
end

function Hero:RestoreMana()
    if self.unit:IsAlive() then
        self.unit:SetMana(self.unit:GetMana() + 1)

        local sign = ParticleManager:CreateParticle("particles/msg_fx/msg_mana_add.vpcf", PATTACH_CUSTOMORIGIN, mode)
        ParticleManager:SetParticleControl(sign, 0, self:GetPos())
        ParticleManager:SetParticleControl(sign, 1, Vector(10, 1, 0))
        ParticleManager:SetParticleControl(sign, 2, Vector(2, 2, 0))
        ParticleManager:SetParticleControl(sign, 3, Vector(0, 248, 255))
        ParticleManager:ReleaseParticleIndex(sign)
    end
end

function Hero:FindAbility(name)
    return self.unit:FindAbilityByName(name)
end

function Hero:EnableUltimate(ultimate)
    self.unit:FindAbilityByName(ultimate):SetLevel(1)
end

function Hero:Hide()
    if IsValidEntity(self.unit) then
        self.unit:SetAbsOrigin(Vector(0, 0, 10000))
        self.unit:AddNoDraw()
        self:AddNewModifier(self, nil, "modifier_hidden", {})
    end
end

function Hero:CanFall()
    return not self:IsAirborne()
end

function Hero:IsAirborne()
    for _, modifier in pairs(self.unit:FindAllModifiers()) do
        if modifier.Airborne and modifier:Airborne() then
            return true
        end
    end

    return false
end

function Hero:AddKnockbackSource(source)
    self.lastKnockbackSource = source
    self.lastKnockbackTimer = 45
end

function Hero:AddNewModifier(source, ability, name, params)
    if name ~= "modifier_falling" then
        for _, modifier in pairs(self:AllModifiers()) do
            if modifier.OnModifierAdded then
                local result = modifier:OnModifierAdded(source, ability, name, params)

                if result == false then
                    return
                end
            end
        end
    end

    return getbase(Hero).AddNewModifier(self, source, ability, name, params)
end

function Hero:Update()
    getbase(Hero).Update(self)

    if self.wearableRemoveTimer > 0 then
        self.wearableRemoveTimer = self.wearableRemoveTimer - 1

        if self.wearableRemoveTimer == 0 then
            self:CleanParticles()
            self:CleanWearables()
        end
    end

    if self.hideOnDeathTimer > 0 then
        self.hideOnDeathTimer = self.hideOnDeathTimer - 1

        if self.hideOnDeathTimer == 0 then
            self:CleanParticles()
            self:SetHidden(true)
        end
    end

    if not self.falling then
        if self.lastKnockbackTimer > 0 then
            self.lastKnockbackTimer = self.lastKnockbackTimer - 1
        else
            self.lastKnockbackSource = nil
        end
    end

    if self.owner and self.unit and self.owner:IsConnected() and PlayerResource:GetPlayer(self.owner.id) then
        local assigned = PlayerResource:GetPlayer(self.owner.id):GetAssignedHero()

        if assigned then
            assigned:SetAbsOrigin(self:GetPos())
        end
    end
end

function Hero:Setup()
    self:AddNewModifier(self, nil, "modifier_hero", {})
    self.unit:SetAbilityPoints(0)

    local count = self.unit:GetAbilityCount() - 1
    for i = 0, count do
        local ability = self.unit:GetAbilityByIndex(i)

        if ability ~= nil and not ability:IsAttributeBonus() and not ability:IsHidden()  then
            local name = ability:GetName()

            if string.find(name, "sub") then
                ability:SetHidden(true)
            end

            ability:SetLevel(1)
        end
    end
end

function Hero:Remove()
    for _, modifier in pairs(self:AllModifiers()) do
        if modifier.GetName and modifier:GetName() ~= "modifier_falling" then
            modifier:Destroy()
        end
    end

    for _, sound in pairs(self.soundsStarted) do
        getbase(Hero).StopSound(self, sound)
    end

    getbase(Hero).Remove(self)
end
