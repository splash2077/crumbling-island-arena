Dash = Dash or class({})

function Dash:constructor(hero, to, speed, params)
    self.hero = hero
    self.to = to
    self.velocity = speed / 30

    self.from = hero:GetPos()
    self.zStart = hero:GetGroundHeight(self.from)

    self.findClearSpace = params.findClearSpace or true
    self.radius = params.radius or 128
    self.modifier = params.modifier
    self.arrivalSound = params.arrivalSound
    self.loopingSound = params.loopingSound

    self.PositionFunction = params.positionFunction or self.PositionFunction
    self.heightFunction = params.heightFunction
    self.arrivalFunction = params.arrivalFunction
    self.hitParams = params.hitParams
    self.hitGroup = {}

    self.destroyed = false

    if self.loopingSound then
        self.hero:EmitSound(self.loopingSound)
    end

    if params.forceFacing then
        local facing = self.to - self.from

        if facing:Length2D() == 0 then
            facing = self.hero:GetFacing()
        end
        
        self.hero:SetFacing(facing:Normalized() * Vector(1, 1, 0))
    end

    if self.modifier then
        self.hero:AddNewModifier(self.modifier.source or self.hero, self.modifier.ability, self.modifier.name, {})
    end

    hero.round.spells:AddDash(self)
end

function Dash:Update()
    local origin = self.hero:GetPos()
    local result = self:PositionFunction(origin)

    result.z = self.zStart + self:HeightFunction(origin)
    self.hero:SetPos(result)

    if self.hitParams then
        local params = vlua.clone(self.hitParams)

        local function groupFilter(target)
            return not self.hitGroup[target]
        end

        params.filter = Filters.And(Filters.Line(origin, result, self.hero:GetRad()), groupFilter)

        local hurt = self.hero:AreaEffect(params)

        for _, target in ipairs(hurt or {}) do
            self.hitGroup[target] = true
        end
    end

    if (self.to - origin):Length2D() <= self.velocity then
        if self.findClearSpace then
            GridNav:DestroyTreesAroundPoint(result, self.radius, true)
            self.hero:FindClearSpace(result, false)
        end

        self:OnArrival()
        self.destroyed = true
    end

    return result
end

function Dash:PositionFunction(current)
    local diff = self.to - current
    return current + (diff:Normalized() * self.velocity)
end

function Dash:HeightFunction(current)
    if self.heightFunction then
        return self:heightFunction(current)
    end

    return 0
end

function Dash:OnArrival()
    if self.modifier then
        self.hero:RemoveModifier(self.modifier.name)
    end

    if self.arrivalSound then
        self.hero:EmitSound(self.arrivalSound)
    end

    if self.loopingSound then
        self.hero:StopSound(self.loopingSound)
    end

    if self.arrivalFunction then
        self:arrivalFunction()
    end
end