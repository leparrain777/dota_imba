--[[	Broccoli
		Date: 15.07.2015.			]]


function ShallowCopy(orig)
    local copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    return copy
end

local base_ability_dual_breath = class({})

function base_ability_dual_breath:GetCastRange(Location, Target)
	if IsServer() then
		return 0
	else
		return self:GetSpecialValueFor("range")
	end
end

function base_ability_dual_breath:OnUpgrade()

	if IsServer() then
		local caster = self:GetCaster()

		if IsStolenSpell(caster) then
			return nil
		end

		local ability_other_breath_name = self.ability_other_breath_name

		if not ability_other_breath_name then
			return nil
		end

		-- Prevent death lock updating each other
		local ability_level = self:GetLevel()
		if not caster.breath_level or caster.breath_level ~= ability_level then
			caster.breath_level = ability_level
			SetAbilityLevelIfPresent(caster, ability_other_breath_name, ability_level)
		end
	end
	
end

function base_ability_dual_breath:OnSpellStart()

	if IsServer() then
		local caster = self:GetCaster()
		caster:EmitSound("Hero_Jakiro.DualBreath")

		-- Can't bring vectors across
		local breath_target = self:GetCursorPosition()
		local breath_target_x = breath_target.x
		local breath_target_y = breath_target.y
		local breath_target_z = breath_target.z

		caster:AddNewModifier(caster, self, self.modifier_caster_name, { 
			breath_target_x = breath_target_x,
			breath_target_y = breath_target_y,
			breath_target_z = breath_target_z,
			breath_range = self:GetSpecialValueFor("range") + GetCastRangeIncrease(caster)
		})
	end
end

local base_modifier_dual_breath_caster = class({
	IsHidden 						= function(self) return true end,
	IsPurgable 						= function(self) return false end,
	IsDebuff 						= function(self) return false end,
	RemoveOnDeath 					= function(self) return true end,
	AllowIllusionDuplicate			= function(self) return false end,
	GetOverrideAnimation 			= function(self) return ACT_DOTA_FLAIL end,
	GetActivityTranslationModifiers = function(self) return "forcestaff_friendly" end,
	GetOverrideAnimationRate 		= function(self) return 0.5 end,
	GetModifierDisableTurning 		= function(self) return 1 end
})

function base_modifier_dual_breath_caster:DeclareFunctions()
	local funcs = {
		MODIFIER_PROPERTY_DISABLE_TURNING,
		MODIFIER_PROPERTY_OVERRIDE_ANIMATION,
		MODIFIER_PROPERTY_OVERRIDE_ANIMATION_RATE,
		MODIFIER_PROPERTY_TRANSLATE_ACTIVITY_MODIFIERS 
	}
 
	return funcs
end

function base_modifier_dual_breath_caster:OnCreated( kv )

	if IsServer() then

		if self:ApplyHorizontalMotionController() == false then 
			self:Destroy()
		else

			local caster = self:GetCaster()
			local ability = self:GetAbility()
			local caster_pos = caster:GetAbsOrigin()
			local ability_level = ability:GetLevel() - 1
			local target = Vector( kv.breath_target_x, kv.breath_target_y, kv.breath_target_z)
			local range = kv.breath_range
			local particle_breath = self.particle_breath
			
			self.caster = caster
			self.ability = ability
			self.path_radius = ability:GetSpecialValueFor("path_radius")
			self.debuff_duration = ability:GetSpecialValueFor("duration")

			local caster_pos = caster:GetAbsOrigin()
			local breath_direction = ( target - caster_pos ):Normalized()
			if ( target - caster_pos ):Length2D() > range then
				target = caster_pos + breath_direction * range
			end
			local breath_distance = ( target - caster_pos ):Length2D()
			
			local breath_speed = ability:GetLevelSpecialValueFor("speed", ability_level)
			
			-- Ability variables
			self.breath_direction = breath_direction
			self.breath_distance = breath_distance
			-- Tick rate is 30 per sec
			self.breath_speed = breath_speed * 1/30
			self.breath_traveled = 0
			self.affected_unit_list = {}
			
			-- Destroy existing particle if it exist
			if self.existing_breath_particle then
				local destroy_existing_breath_particle = self.existing_breath_particle
				-- Delay before destroying particle
				Timers:CreateTimer(0.4, function()
					ParticleManager:DestroyParticle(destroy_existing_breath_particle, false)
					ParticleManager:ReleaseParticleIndex( destroy_existing_breath_particle )
				end)
			end

			local breath_pfx = ParticleManager:CreateParticle(particle_breath, PATTACH_ABSORIGIN, caster)
			ParticleManager:SetParticleControl(breath_pfx, 0, caster_pos )
			ParticleManager:SetParticleControl(breath_pfx, 1, breath_direction * breath_speed)
			ParticleManager:SetParticleControl(breath_pfx, 3, Vector(0,0,0) )
			ParticleManager:SetParticleControl(breath_pfx, 9, caster_pos )

			self.existing_breath_particle = breath_pfx
		end

	end
end

function base_modifier_dual_breath_caster:_DualBreathApplyModifier( radius )
	
	local caster = self.caster
	local ability = self.ability
	local modifier_debuff_name = self.modifier_debuff_name
	local affected_unit_list = self.affected_unit_list
	local debuff_duration = self.debuff_duration

	local caster_pos = caster:GetAbsOrigin()

	local target_vector = caster_pos + ( self.breath_direction * radius ) / 2

	-- Apply Breath modifier on enemies
	local enemies = FindUnitsInRadius(caster:GetTeamNumber(), target_vector, nil, radius, ability:GetAbilityTargetTeam(), ability:GetAbilityTargetType(), ability:GetAbilityTargetFlags(), FIND_ANY_ORDER, false)
	for _,enemy in pairs(enemies) do
		--Apply Debuff only once per unit
		if not affected_unit_list[enemy] then
			affected_unit_list[enemy] = true
			enemy:AddNewModifier(caster, ability, modifier_debuff_name, { duration = debuff_duration })
		end
	end

	-- Destroy trees
	GridNav:DestroyTreesAroundPoint(target_vector, radius, false)
end


function base_modifier_dual_breath_caster:UpdateHorizontalMotion()

	if IsServer() then
		local caster = self.caster
		local ability = self.ability
		local breath_speed = self.breath_speed
		local breath_traveled = self.breath_traveled

		if breath_traveled < self.breath_distance and not IsHardDisabled(caster) then
			caster:SetAbsOrigin(caster:GetAbsOrigin() + self.breath_direction * breath_speed)
			self.breath_traveled = breath_traveled + breath_speed

			self:_DualBreathApplyModifier( self.path_radius )
		else
			caster:InterruptMotionControllers( true )
			if not IsStolenSpell(caster) then
				-- Switch breath abilities
				caster:SwapAbilities(ability:GetAbilityName(), self.ability_other_breath_name, false, true)
			end

			self:_DualBreathApplyModifier( ability:GetSpecialValueFor("spill_radius") )

			self:Destroy()
		end
	end
end

function base_modifier_dual_breath_caster:CheckState()
	local state = {
		[MODIFIER_STATE_ROOTED] = true,
	}
 
	return state
end

function base_modifier_dual_breath_caster:OnHorizontalMotionInterrupted()

	if self.existing_breath_particle then
		local destroy_existing_breath_particle = self.existing_breath_particle
		self.existing_breath_particle = nil
		-- Delay before destroying particle
		Timers:CreateTimer(0.4, function()
			ParticleManager:DestroyParticle(destroy_existing_breath_particle, false)
			ParticleManager:ReleaseParticleIndex( destroy_existing_breath_particle )
		end)
	end

	self:Destroy()
end

local base_modifier_dot_debuff = class({
	IsHidden		= function(self) return false end,
	IsPurgable	  	= function(self) return true end,
	IsDebuff	  	= function(self) return true end
})

function base_modifier_dot_debuff:_UpdateDebuffLevelValues()
	local ability = self.ability
	local ability_level = ability:GetLevel() - 1
	local damage = ability:GetLevelSpecialValueFor("damage", ability_level)
	self.tick_damage = damage * self.damage_interval

	if self._UpdateSubClassLevelValues then
		self:_UpdateSubClassLevelValues()
	end
end

function base_modifier_dot_debuff:OnCreated()
	if IsServer() then
		self.caster 			= self:GetCaster()
		self.parent 			= self:GetParent()

		local ability 			= self:GetAbility()
		local damage_interval 	= ability:GetSpecialValueFor("damage_interval")

		self.ability 			= ability
		self.ability_dmg_type 	= ability:GetAbilityDamageType()
		self.damage_interval	= damage_interval

		if self._SubClassOnCreated then
			self:_SubClassOnCreated()
		end

		self:_UpdateDebuffLevelValues()

		self:StartIntervalThink(damage_interval)
	end
end

function base_modifier_dot_debuff:OnRefresh()
	if IsServer() then
		self:_UpdateDebuffLevelValues()
	end
end

function base_modifier_dot_debuff:OnIntervalThink()
	if IsServer() then
		local caster = self.caster
		local victim = self.parent

		local final_tick_damage = self.tick_damage

		if victim:FindModifierByNameAndCaster("modifier_imba_ice_path_freeze_debuff", caster) then
			local ability_ice_path = caster:FindAbilityByName("imba_jakiro_ice_path")
			if ability_ice_path then
				local ability_level = ability_ice_path:GetLevel() - 1
				local damage_amp = ability_ice_path:GetLevelSpecialValueFor("damage_amp", ability_level)
				final_tick_damage = final_tick_damage * ( 1 + damage_amp/100 )
			end
		end

		ApplyDamage({attacker = caster, victim = victim, ability = self.ability, damage = final_tick_damage, damage_type = self.ability_dmg_type })
	end
end

 -- CreateEmptyTalents("jakiro")

-----------------------------
--		Fire Breath        --
-----------------------------

imba_jakiro_fire_breath = ShallowCopy( base_ability_dual_breath )
imba_jakiro_fire_breath.ability_other_breath_name = "imba_jakiro_ice_breath"
imba_jakiro_fire_breath.modifier_caster_name = "modifier_imba_fire_breath_caster"
LinkLuaModifier("modifier_imba_fire_breath_debuff", "hero/hero_jakiro", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_fire_breath_caster", "hero/hero_jakiro", LUA_MODIFIER_MOTION_HORIZONTAL)

function imba_jakiro_fire_breath:GetTexture()
	return "custom/jakiro_fire_breath"
end

modifier_imba_fire_breath_debuff = ShallowCopy( base_modifier_dot_debuff )

function modifier_imba_fire_breath_debuff:_SubClassOnCreated()
	self.move_slow = self:GetAbility():GetSpecialValueFor("move_slow")
end

function modifier_imba_fire_breath_debuff:DeclareFunctions()
	local funcs = {
		MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE
	}

	return funcs
end

function modifier_imba_fire_breath_debuff:GetModifierMoveSpeedBonus_Percentage() return self.move_slow end

modifier_imba_fire_breath_caster = ShallowCopy( base_modifier_dual_breath_caster )
modifier_imba_fire_breath_caster.modifier_debuff_name = "modifier_imba_fire_breath_debuff"
modifier_imba_fire_breath_caster.ability_other_breath_name = "imba_jakiro_ice_breath"
modifier_imba_fire_breath_caster.particle_breath = "particles/units/heroes/hero_jakiro/jakiro_dual_breath_fire.vpcf"

-----------------------------
--		Ice Breath         --
-----------------------------

imba_jakiro_ice_breath = ShallowCopy( base_ability_dual_breath )
imba_jakiro_ice_breath.ability_other_breath_name = "imba_jakiro_fire_breath"
imba_jakiro_ice_breath.modifier_caster_name = "modifier_imba_ice_breath_caster"
LinkLuaModifier("modifier_imba_ice_breath_debuff", "hero/hero_jakiro", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_ice_breath_caster", "hero/hero_jakiro", LUA_MODIFIER_MOTION_HORIZONTAL)

function imba_jakiro_ice_breath:GetTexture()
	return "custom/jakiro_ice_breath"
end

modifier_imba_ice_breath_debuff = ShallowCopy( base_modifier_dot_debuff )

function modifier_imba_ice_breath_debuff:_SubClassOnCreated()
	local ability = self:GetAbility()
	self.attack_slow = ability:GetSpecialValueFor("attack_slow")
	self.move_slow = ability:GetSpecialValueFor("move_slow")
end

function modifier_imba_ice_breath_debuff:DeclareFunctions()
	local funcs = {
		MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE,
		MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT
	}
 
	return funcs
end

function modifier_imba_ice_breath_debuff:GetModifierMoveSpeedBonus_Percentage() return self.move_slow end
function modifier_imba_ice_breath_debuff:GetModifierAttackSpeedBonus_Constant() return self.attack_slow end

modifier_imba_ice_breath_caster = ShallowCopy(base_modifier_dual_breath_caster)
modifier_imba_ice_breath_caster.modifier_debuff_name = "modifier_imba_ice_breath_debuff"
modifier_imba_ice_breath_caster.ability_other_breath_name = "imba_jakiro_fire_breath"
modifier_imba_ice_breath_caster.particle_breath = "particles/units/heroes/hero_jakiro/jakiro_dual_breath_ice.vpcf"


-----------------------------
--		Ice Path           --
-----------------------------

imba_jakiro_ice_path = class({})
LinkLuaModifier("modifier_imba_ice_path_thinker", "hero/hero_jakiro", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_ice_path_freeze_debuff", "hero/hero_jakiro", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_ice_path_slow_debuff", "hero/hero_jakiro", LUA_MODIFIER_MOTION_NONE)

function imba_jakiro_ice_path:OnSpellStart()
	if IsServer() then
		local caster		= self:GetCaster()
		local ability_level = self:GetLevel() - 1
		local path_length 	= self:GetLevelSpecialValueFor("range", ability_level) + GetCastRangeIncrease(caster)
		local start_pos 	= caster:GetAbsOrigin()
		local end_pos 		= start_pos + caster:GetForwardVector() * path_length
		local path_delay 	= self:GetSpecialValueFor("path_delay")

		local kv = {
			path_delay 		= path_delay,
			path_radius 	= self:GetSpecialValueFor("path_radius"),
			path_duration 	= self:GetLevelSpecialValueFor("path_duration", ability_level),
			stun_duration 	= self:GetLevelSpecialValueFor("stun_duration", ability_level),
			path_length 	= path_length
		}

		caster:EmitSound("Hero_Jakiro.IcePath")

		Timers:CreateTimer(0.1, function()
			caster:EmitSound("Hero_Jakiro.IcePath.Cast")
		end)

		-- Create ice_path_a
		local particle_name = "particles/units/heroes/hero_jakiro/jakiro_ice_path.vpcf"
		local pfx_a = ParticleManager:CreateParticle( particle_name, PATTACH_ABSORIGIN, caster )
		ParticleManager:SetParticleControl( pfx_a, 0, start_pos )
		ParticleManager:SetParticleControl( pfx_a, 1, end_pos )
		ParticleManager:SetParticleControl( pfx_a, 2, start_pos )

		-- Destroy particle after delay
		Timers:CreateTimer(path_delay, function()
			ParticleManager:DestroyParticle( pfx_a, false )
			ParticleManager:ReleaseParticleIndex( pfx_a )
		end)

		CreateModifierThinker( caster, self, "modifier_imba_ice_path_thinker", kv, caster:GetAbsOrigin(), caster:GetTeamNumber(), false )
	end
end

modifier_imba_ice_path_thinker = class({})
modifier_imba_ice_path_thinker.modifier_freeze 	= "modifier_imba_ice_path_freeze_debuff"
modifier_imba_ice_path_thinker.modifier_slow 	= "modifier_imba_ice_path_slow_debuff"
function modifier_imba_ice_path_thinker:OnCreated( kv )
	if IsServer() then
		local caster				= self:GetCaster()
		local ability				= self:GetAbility()
		local path_delay			= kv.path_delay
		local path_duration			= kv.path_duration
		local path_length 			= kv.path_length

		local start_pos 			= caster:GetAbsOrigin()
		local end_pos 				= start_pos + caster:GetForwardVector() * path_length
		local path_total_duration	= path_delay + path_duration

		self.ice_path_end_time 		= GameRules:GetGameTime() + path_total_duration
		-- Prevent enemy from getting frozen again
		self.frozen_enemy_set 		= {}
		self.ability_target_team 	= ability:GetAbilityTargetTeam()
		self.ability_target_type 	= ability:GetAbilityTargetType()
		self.ability_target_flags 	= ability:GetAbilityTargetFlags()
		self.path_radius			= kv.path_radius
		self.stun_duration 			= kv.stun_duration
		self.start_pos 				= start_pos
		self.end_pos 				= end_pos

		-- Create ice_path_b
		local particle_name = "particles/units/heroes/hero_jakiro/jakiro_ice_path_b.vpcf"
		local pfx_b = ParticleManager:CreateParticle( particle_name, PATTACH_ABSORIGIN, caster )
		ParticleManager:SetParticleControl( pfx_b, 0, start_pos )
		ParticleManager:SetParticleControl( pfx_b, 1, end_pos )
		ParticleManager:SetParticleControl( pfx_b, 2, Vector( path_total_duration, 0, 0 ) )
		ParticleManager:SetParticleControl( pfx_b, 9, start_pos )
		self:AddParticle(pfx_b, false, false, -1, false, false)

		local tick_rate = 0.1

		Timers:CreateTimer(path_delay, function()
			self:StartIntervalThink( tick_rate )
		end)
	end
end

function modifier_imba_ice_path_thinker:OnIntervalThink()
	if IsServer() then
		local current_game_time = GameRules:GetGameTime()
		local ice_path_end_time = self.ice_path_end_time

		if current_game_time >= ice_path_end_time then
			UTIL_Remove( self:GetParent() )
		else

			local stun_duration 	= self.stun_duration
			local frozen_enemy_set 	= self.frozen_enemy_set
			local caster 			= self:GetCaster()
			local ability			= self:GetAbility()
			local modifier_freeze 	= self.modifier_freeze

			local time_diff = ice_path_end_time - current_game_time

			local stun_duration_left
			if time_diff > stun_duration then
				stun_duration_left = stun_duration
			else
				stun_duration_left = time_diff
			end

			-- TODO find out if it is path_radius * 2 or just path_radius

			local enemies = FindUnitsInLine(caster:GetTeamNumber(), self.start_pos, self.end_pos, nil, self.path_radius, self.ability_target_team, self.ability_target_type, self.ability_target_flags)

			for _, enemy in pairs(enemies) do
				if not frozen_enemy_set[enemy] then
					-- Freeze enemy
					frozen_enemy_set[enemy] = true
					enemy:AddNewModifier(caster, ability, modifier_freeze, { duration = stun_duration_left })
				else
					if not enemy:FindModifierByNameAndCaster(modifier_freeze, caster) then
						-- Slow enemy after the freeze expires
						enemy:AddNewModifier(caster, ability, self.modifier_slow, { duration = 1.0 })
					end
				end
			end
		end
	end
end

modifier_imba_ice_path_freeze_debuff = class({
	IsHidden				= function(self) return false end,
	IsPurgable	  			= function(self) return true end,
	IsDebuff	  			= function(self) return true end,
	GetEffectName			= function(self) return "particles/generic_gameplay/generic_stunned.vpcf" end,
	GetEffectAttachType     = function(self) return PATTACH_OVERHEAD_FOLLOW end,
	GetOverrideAnimation 	= function(self) return ACT_DOTA_DISABLED end
})

function modifier_imba_ice_path_freeze_debuff:OnCreated()
	if IsServer() then
		local ability = self:GetAbility()
		ApplyDamage({attacker = self:GetCaster(), victim = self:GetParent(), ability = ability, damage = ability:GetSpecialValueFor("damage"), damage_type = ability:GetAbilityDamageType()})
	end
end

function modifier_imba_ice_path_freeze_debuff:DeclareFunctions()
	local funcs = {
		MODIFIER_PROPERTY_OVERRIDE_ANIMATION
	}
 
	return funcs
end

function modifier_imba_ice_path_freeze_debuff:CheckState()
	local state = {
		[MODIFIER_STATE_STUNNED] = true,
	}
 
	return state
end

modifier_imba_ice_path_slow_debuff = class({
	IsHidden				= function(self) return false end,
	IsPurgable	  			= function(self) return true end,
	IsDebuff	  			= function(self) return true end
})

function modifier_imba_ice_path_slow_debuff:OnCreated()
	local ability = self:GetAbility()
	self.attack_slow = ability:GetSpecialValueFor("attack_slow")
	self.move_slow = ability:GetSpecialValueFor("move_slow")
end

function modifier_imba_ice_path_slow_debuff:DeclareFunctions()
	local funcs = {
		MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE,
		MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT
	}
 
	return funcs
end

function modifier_imba_ice_path_slow_debuff:GetModifierMoveSpeedBonus_Percentage() return self.move_slow end
function modifier_imba_ice_path_slow_debuff:GetModifierAttackSpeedBonus_Constant() return self.attack_slow end

-----------------------------
--		Liquid Fire        --
-----------------------------

imba_jakiro_liquid_fire = class({
	GetIntrinsicModifierName = function(self) return "modifier_imba_liquid_fire_caster" end
})
LinkLuaModifier("modifier_imba_liquid_fire_caster", "hero/hero_jakiro", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_liquid_fire_debuff", "hero/hero_jakiro", LUA_MODIFIER_MOTION_NONE)

function imba_jakiro_liquid_fire:OnCreated()
	self.caster = self:GetCaster()
	self.ability = self:GetAbility()
	self.cast_liquid_fire = false
end

function imba_jakiro_liquid_fire:GetCastRange(Location, Target)
	return self:GetCaster():GetAttackRange() + self:GetSpecialValueFor("extra_cast_range")
end

function imba_jakiro_liquid_fire:OnSpellStart()
	if IsServer() then
		local target = self:GetCursorTarget()
		local caster = self:GetCaster()

		self.cast_liquid_fire = true

		-- Attack the main target
		caster:PerformAttack(target, true, true, true, true, true, false, false)
	end
end

modifier_imba_liquid_fire_caster = class({
	IsHidden				= function(self) return true end,
	IsPurgable	  			= function(self) return false end,
	IsDebuff	  			= function(self) return false end,
	RemoveOnDeath 			= function(self) return false end,
	AllowIllusionDuplicate	= function(self) return false end
})

function modifier_imba_liquid_fire_caster:DeclareFunctions()
	local funcs = {
		MODIFIER_EVENT_ON_ATTACK_START,
		MODIFIER_EVENT_ON_ATTACK,
		MODIFIER_EVENT_ON_ATTACK_FAIL,
		MODIFIER_EVENT_ON_ATTACK_LANDED,
		MODIFIER_EVENT_ON_ORDER
	}

	return funcs
end

function modifier_imba_liquid_fire_caster:OnCreated()
	
	self.parent = self:GetParent()
	self.caster = self:GetCaster()
	self.ability = self:GetAbility()
	self.apply_aoe_modifier_debuff_on_hit = false
	--"particles/units/heroes/hero_jakiro/jakiro_base_attack_fire.vpcf"
	--[[
		"FireSound"
			{
				"EffectName"				"Hero_Jakiro.Attack"
				"Target"					"CASTER"
			}

			"TrackingProjectile"
			{
				"Target"
				{
					"Center"				"TARGET"
					"Teams"					"DOTA_UNIT_TARGET_TEAM_ENEMY"
					"Types"					"DOTA_UNIT_TARGET_HERO | DOTA_UNIT_TARGET_BASIC | DOTA_UNIT_TARGET_BUILDING"
					"Flags"					"DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES"
				}
				"EffectName"				"particles/units/heroes/hero_jakiro/jakiro_base_attack_fire.vpcf"
				"Dodgeable"					"1"
				"ProvidesVision"			"0"
				"VisionRadius"				"0"
				"MoveSpeed"					"%speed"
				"SourceAttachment"			"DOTA_PROJECTILE_ATTACHMENT_ATTACK_1"
			}

	]]--

end

function modifier_imba_liquid_fire_caster:_ShouldAttachLiquidFire( target )
	local ability = self.ability

	if not ability:IsHidden() and not target:IsMagicImmune() then
		return ability.cast_liquid_fire == true or (ability:GetAutoCastState() and ability:IsCooldownReady())
	end

	return false
end

function modifier_imba_liquid_fire_caster:OnAttackStart(keys)
	
	--TODO attach projectile
end

function modifier_imba_liquid_fire_caster:OnAttack(keys)
	if IsServer() then
		local caster = self.caster
		local target = keys.target
		local attacker = keys.attacker

		if caster == attacker and self:_ShouldAttachLiquidFire(target) then
			local ability = self.ability
		
			ability.cast_liquid_fire = false

			self.apply_aoe_modifier_debuff_on_hit = true

			local cooldown = ability:GetCooldown( ability:GetLevel() - 1 ) *  GetCooldownReduction(caster)

			-- Start cooldown
			ability:StartCooldown( cooldown )
		end
	end
end

function modifier_imba_liquid_fire_caster:_ApplyAOELiquidFire( keys )
	

	if IsServer() then

		local caster = self.caster
		local attacker = keys.attacker

		if caster == attacker and self.apply_aoe_modifier_debuff_on_hit == true then
			self.apply_aoe_modifier_debuff_on_hit = false
			local target = keys.target
			local ability = self.ability

			local ability_level = ability:GetLevel() - 1
			local particle_liquid_fire = "particles/units/heroes/hero_jakiro/jakiro_liquid_fire_explosion.vpcf"
			local modifier_liquid_fire_debuff = "modifier_imba_liquid_fire_debuff"
			local duration = ability:GetLevelSpecialValueFor("duration", ability_level)

			-- Parameters
			local radius = ability:GetLevelSpecialValueFor("radius", ability_level)

			-- Play sound
			target:EmitSound("Hero_Jakiro.LiquidFire")

			-- Play explosion particle
			local fire_pfx = ParticleManager:CreateParticle( particle_liquid_fire, PATTACH_ABSORIGIN, target )
			ParticleManager:SetParticleControl( fire_pfx, 0, target:GetAbsOrigin() )
			ParticleManager:SetParticleControl( fire_pfx, 1, Vector(radius * 2,0,0) )

			--TODO destroy particle?

			-- Apply liquid fire modifier to enemies in the area
			local enemies = FindUnitsInRadius(caster:GetTeamNumber(), target:GetAbsOrigin(), nil, radius, ability:GetAbilityTargetTeam(), ability:GetAbilityTargetType(), DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false)
			for _,enemy in pairs(enemies) do
				enemy:AddNewModifier(caster, ability, modifier_liquid_fire_debuff, { duration = duration })
			end
		end
	end
end

function modifier_imba_liquid_fire_caster:OnAttackLanded( keys )
	self:_ApplyAOELiquidFire(keys)
end

function modifier_imba_liquid_fire_caster:OnAttackFail( keys )
	self:_ApplyAOELiquidFire(keys)
end

function modifier_imba_liquid_fire_caster:OnOrder(keys)
	local order_type = keys.order_type	

	-- On any order apart from attacking target, clear the cast_liquid_fire variable.
	if order_type ~= DOTA_UNIT_ORDER_ATTACK_TARGET then
		self.ability.cast_liquid_fire = false
	end
end

modifier_imba_liquid_fire_debuff = ShallowCopy( base_modifier_dot_debuff )

function modifier_imba_liquid_fire_debuff:_UpdateSubClassLevelValues()
	local ability = self.ability
	local ability_level = ability:GetLevel() - 1
	self.attack_slow = ability:GetLevelSpecialValueFor("attack_slow", ability_level)
end

function modifier_imba_liquid_fire_debuff:_SubClassOnCreated()
	self.turn_slow = self.ability:GetSpecialValueFor("turn_slow")
end

function modifier_imba_liquid_fire_debuff:DeclareFunctions()
	local funcs = {
		MODIFIER_PROPERTY_TURN_RATE_PERCENTAGE,
		MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT
	}

	return funcs
end

function modifier_imba_liquid_fire_debuff:GetModifierAttackSpeedBonus_Constant() return self.attack_slow end
function modifier_imba_liquid_fire_debuff:GetModifierTurnRate_Percentage() return self.turn_slow end
function modifier_imba_liquid_fire_debuff:GetEffectName() return "particles/units/heroes/hero_jakiro/jakiro_liquid_fire_debuff.vpcf" end
function modifier_imba_liquid_fire_debuff:GetEffectAttachType() return PATTACH_ABSORIGIN_FOLLOW end

-----------------------------
--		Macropyre          --
-----------------------------

imba_jakiro_macropyre = class({})
LinkLuaModifier("modifier_imba_macropyre_thinker", "hero/hero_jakiro", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_imba_macropyre_debuff", "hero/hero_jakiro", LUA_MODIFIER_MOTION_NONE)

function imba_jakiro_macropyre:OnSpellStart()
	if IsServer() then
		local caster = self:GetCaster()
		local target = self:GetCursorPosition()
	
		-- Unable to bring vector across, need to break it down to values
		local kv = {
			target_x = target.x,
			target_y = target.y,
			target_z = target.z
		}
		CreateModifierThinker( caster, self, "modifier_imba_macropyre_thinker", kv, caster:GetAbsOrigin(), caster:GetTeamNumber(), false )
	end
end

modifier_imba_macropyre_thinker = class({})
function modifier_imba_macropyre_thinker:OnCreated( kv )
	if IsServer() then
		local caster 				= self:GetCaster()
		local ability 				= self:GetAbility()
		local target 				= Vector( kv.target_x, kv.target_y, kv.target_z )
		local ability_level 		= ability:GetLevel() - 1
		local scepter 				= HasScepter(caster)

		local path_radius 			= ability:GetLevelSpecialValueFor("path_radius", ability_level)
		local trail_amount 			= ability:GetLevelSpecialValueFor("trail_amount", ability_level)
		local path_duration
		local path_length
		-- Draw the fire particles (blue fire if the owner has Aghanim's Scepter)
		local particle_name

		-- Play cast sound, and ice sound if owner has Aghanim's Scepter
		caster:EmitSound("Hero_Jakiro.Macropyre.Cast")

		-- If the owner has a scepter, change the cast sound and increase duration
		if scepter then
			caster:EmitSound("Hero_Jakiro.IcePath.Cast")
			path_duration 			= ability:GetLevelSpecialValueFor("duration_scepter", ability_level)
			path_length 			= ability:GetLevelSpecialValueFor("range_scepter", ability_level)
			particle_name			= "particles/hero/jakiro/jakiro_macropyre_blue.vpcf"
		else
			path_duration 			= ability:GetLevelSpecialValueFor("duration", ability_level)
			path_length 			= ability:GetLevelSpecialValueFor("range", ability_level)
			particle_name			= "particles/hero/jakiro/jakiro_macropyre.vpcf"
		end

		path_length 				= path_length + GetCastRangeIncrease(caster)

		-- Initialize effect geometry
		local direction 			= (target - caster:GetAbsOrigin()):Normalized()
		local half_trail_amount 	= ( trail_amount - 1 ) / 2
		local start_pos 			= caster:GetAbsOrigin() + direction * path_radius
		local trail_start 			= ( -1 ) * half_trail_amount
		local trail_end 			= half_trail_amount
		local trail_angle 			= ability:GetLevelSpecialValueFor("trail_angle", ability_level)
		local sound_fire_loop		= "hero_jakiro.macropyre.scepter"
		self.ability_target_team 	= ability:GetAbilityTargetTeam()
		self.ability_target_type 	= ability:GetAbilityTargetType()
		self.ability_target_flags 	= ability:GetAbilityTargetFlags()
		self.debuff_duration 		= ability:GetSpecialValueFor("stickyness")
		self.macropyre_end_time 	= GameRules:GetGameTime() + path_duration
		self.path_radius			= path_radius
		self.sound_fire_loop		= sound_fire_loop
		
		self.start_pos = start_pos

		-- Destroys trees around the target area
		GridNav:DestroyTreesAroundPoint(start_pos, path_radius, false)

		--[[
			-- Create the visibility dummy
			local dummy = CreateUnitByName("npc_dummy_unit", start_pos, false, nil, nil, caster:GetTeamNumber())
			dummy:MakeVisibleToTeam(DOTA_TEAM_GOODGUYS, duration)
			dummy:MakeVisibleToTeam(DOTA_TEAM_BADGUYS, duration)
		]]--

		self:GetParent():EmitSound(sound_fire_loop)

		local common_vector = start_pos + direction * path_length

		-- Calculate thinker position
		-- TODO multiple pos required to destroy trees (find a way to destroy trees without using this spagethi)
		self.thinker_pos_list = {}

		for trail = trail_start, trail_end do
		
			local macropyre_pfx = ParticleManager:CreateParticle( particle_name, PATTACH_ABSORIGIN, caster)

			-- Calculate each trail's end position
			local end_pos = RotatePosition(start_pos, QAngle(0, trail * trail_angle, 0), common_vector)

			ParticleManager:SetParticleAlwaysSimulate(macropyre_pfx)
			ParticleManager:SetParticleControl( macropyre_pfx, 0, start_pos )
			ParticleManager:SetParticleControl( macropyre_pfx, 1, end_pos )
			ParticleManager:SetParticleControl( macropyre_pfx, 2, Vector( path_duration, 0, 0 ) )
			ParticleManager:SetParticleControl( macropyre_pfx, 3, start_pos )
			self:AddParticle(macropyre_pfx, false, false, -1, false, false)

			-- Create thinkers along the trail
			for i = 0, math.floor( path_length / path_radius ) do
				-- Calculate thinker position
				local thinker_pos = start_pos + i * path_radius * ( end_pos - start_pos ):Normalized()
				table.insert(self.thinker_pos_list, thinker_pos)
			end
		end

		self:StartIntervalThink( 0.5 )
	end
end

function modifier_imba_macropyre_thinker:OnIntervalThink()

	if IsServer() then

		if GameRules:GetGameTime() > self.macropyre_end_time then
			--Stop sound before destroy parent
			self:GetParent():StopSound(self.sound_fire_loop)
			UTIL_Remove( self:GetParent() )
		else
			local caster 				= self:GetCaster()
			local ability 				= self:GetAbility()
			local unique_enemy_list 	= {}
			local unique_enemy_set 		= {}
			local thinker_pos_list 		= self.thinker_pos_list
			local path_radius 			= self.path_radius
			local ability_target_team	= self.ability_target_team
			local ability_target_type	= self.ability_target_type
			local ability_target_flags	= self.ability_target_flags
			local debuff_duration		= self.debuff_duration

			--Increase Modifier Duration
			local modifier_list 		= {
				"modifier_imba_liquid_fire_debuff",
				"modifier_imba_fire_breath_debuff",
				"modifier_imba_ice_breath_debuff"
			}

			for _, thinker_pos in pairs(thinker_pos_list) do
				-- Destroys trees around the target area
				GridNav:DestroyTreesAroundPoint(thinker_pos, path_radius, false)

				local enemies = FindUnitsInRadius(caster:GetTeamNumber(), thinker_pos, nil, path_radius, ability_target_team, ability_target_type, ability_target_flags, FIND_ANY_ORDER, false)

				-- Collate enemies into unique list
				for _, enemy in pairs(enemies) do
					if not unique_enemy_set[enemy] then
						unique_enemy_set[enemy] = true
						table.insert(unique_enemy_list, enemy)
					end
				end
			end

			for _, enemy in pairs(unique_enemy_list) do
				-- Applies debuff to enemies found
				enemy:AddNewModifier(caster, ability, "modifier_imba_macropyre_debuff", { duration = debuff_duration } )
				
				-- Increase duration for some modifiers
				for _,modifier_name in pairs(modifier_list) do
					local other_modifier = enemy:FindModifierByNameAndCaster(modifier_name, caster)
					if other_modifier then
						other_modifier:SetDuration(other_modifier:GetRemainingTime() + 0.25, true)
					end
				end
			end
		end
	end
end

modifier_imba_macropyre_debuff = ShallowCopy( base_modifier_dot_debuff )