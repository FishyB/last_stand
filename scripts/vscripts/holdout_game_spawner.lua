--[[
	CHoldoutGameSpawner - A single unit spawner for Holdout.
]]
if CHoldoutGameSpawner == nil then
	CHoldoutGameSpawner = class({})
end


function CHoldoutGameSpawner:ReadConfiguration( name, kv, gameRound )

	self._gameRound = gameRound
	self._dependentSpawners = {}
	
	self._szChampionNPCClassName = kv.ChampionNPCName or ""
	self._szGroupWithUnit = kv.GroupWithUnit or ""
	self._szName = name
	self._szNPCClassName = kv.NPCName or ""
	self._szSpawnerName = kv.SpawnerName or ""
	self._szWaitForUnit = kv.WaitForUnit or ""
	self._szWaypointName = kv.Waypoint or ""
	self._waypointEntity = nil

	self._nChampionLevel = tonumber( kv.ChampionLevel or 1 )
	self._nChampionMax = tonumber( kv.ChampionMax or 1 )
	self._nCreatureLevel = tonumber( kv.CreatureLevel or 1 )
	self._nTotalUnitsToSpawn = tonumber( kv.TotalUnitsToSpawn or 0 )
	self._nUnitsPerSpawn = tonumber( kv.UnitsPerSpawn or 0 )
	self._nUnitsPerSpawn = tonumber( kv.UnitsPerSpawn or 1 )

	self._flChampionChance = tonumber( kv.ChampionChance or 0 )
	self._flInitialWait = tonumber( kv.WaitForTime or 0 )
	self._flSpawnInterval = tonumber( kv.SpawnInterval or 0 )

	self._bDontGiveGoal = ( tonumber( kv.DontGiveGoal or 0 ) ~= 0 )
	self._bDontOffsetSpawn = ( tonumber( kv.DontOffsetSpawn or 0 ) ~= 0 )
end


function CHoldoutGameSpawner:PostLoad( spawnerList )
	self._waitForUnit = spawnerList[ self._szWaitForUnit ]
	if self._szWaitForUnit ~= "" and not self._waitForUnit then
		print( self._szName .. " has a wait for unit " .. self._szWaitForUnit .. " that is missing from the round data." )
	elseif self._waitForUnit then
		table.insert( self._waitForUnit._dependentSpawners, self )
	end

	self._groupWithUnit = spawnerList[ self._szGroupWithUnit ]
	if self._szGroupWithUnit ~= "" and not self._groupWithUnit then
		print ( self._szName .. " has a group with unit " .. self._szGroupWithUnit .. " that is missing from the round data." )
	elseif self._groupWithUnit then
		table.insert( self._groupWithUnit._dependentSpawners, self )
	end
end


function CHoldoutGameSpawner:Precache()
	PrecacheUnitByNameAsync( self._szNPCClassName, function( sg ) self._sg = sg end )
	if self._szChampionNPCClassName ~= "" then
		PrecacheUnitByNameAsync( self._szChampionNPCClassName, function( sg ) self._sgChampion = sg end )
	end
end


function CHoldoutGameSpawner:Begin()
	self._nUnitsSpawnedThisRound = 0
	self._nChampionsSpawnedThisRound = 0
	self._nUnitsCurrentlyAlive = 0
	
	self._vecSpawnLocation = nil
	if self._szSpawnerName ~= "" then
		local entSpawner = Entities:FindByName( nil, self._szSpawnerName )
		if not entSpawner then
			print( string.format( "Failed to find spawner named %s for %s\n", self._szSpawnerName, self._szName ) )
		end
		self._vecSpawnLocation = entSpawner:GetAbsOrigin()
	end
	self._entWaypoint = nil
	if self._szWaypointName ~= "" and not self._bDontGiveGoal then
		self._entWaypoint = Entities:FindByName( nil, self._szWaypointName )
		if not self._entWaypoint then
			print( string.format( "Failed to find waypoint named %s for %s", self._szWaypointName, self._szName ) )
		end
	end

	if self._waitForUnit ~= nil or self._groupWithUnit ~= nil then
		self._flNextSpawnTime = nil
	else
		self._flNextSpawnTime = GameRules:GetGameTime() + self._flInitialWait
	end
end


function CHoldoutGameSpawner:End()
	if self._sg ~= nil then
		UnloadSpawnGroupByHandle( self._sg )
		self._sg = nil
	end
	if self._sgChampion ~= nil then
		UnloadSpawnGroupByHandle( self._sgChampion )
		self._sgChampion = nil
	end
end


function CHoldoutGameSpawner:ParentSpawned( parentSpawner )
	if parentSpawner == self._groupWithUnit then
		-- Make sure we use the same spawn location as parentSpawner.
		self:_DoSpawn()
	elseif parentSpawner == self._waitForUnit then
		if parentSpawner:IsFinishedSpawning() and self._flNextSpawnTime == nil then
			self._flNextSpawnTime = parentSpawner._flNextSpawnTime + self._flInitialWait
		end
	end
end


function CHoldoutGameSpawner:Think()
	if not self._flNextSpawnTime then
		return
	end
	
	if GameRules:GetGameTime() >= self._flNextSpawnTime then
		self:_DoSpawn()
		for _,s in pairs( self._dependentSpawners ) do
			s:ParentSpawned( self )
		end

		if self:IsFinishedSpawning() then
			self._flNextSpawnTime = nil
		else
			self._flNextSpawnTime = self._flNextSpawnTime + self._flSpawnInterval
		end
	end
end


function CHoldoutGameSpawner:GetTotalUnitsToSpawn()
	return self._nTotalUnitsToSpawn
end


function CHoldoutGameSpawner:IsFinishedSpawning()
	return ( self._nTotalUnitsToSpawn <= self._nUnitsSpawnedThisRound ) or ( self._groupWithUnit ~= nil )
end


function CHoldoutGameSpawner:_GetSpawnLocation()
	if self._groupWithUnit then
		return self._groupWithUnit:_GetSpawnLocation()
	else
		return self._vecSpawnLocation
	end
end


function CHoldoutGameSpawner:_GetSpawnWaypoint()
	if self._groupWithUnit then
		return self._groupWithUnit:_GetSpawnWaypoint()
	else
		return self._entWaypoint
	end
end


function CHoldoutGameSpawner:_UpdateRandomSpawn()
	self._vecSpawnLocation = Vector( 0, 0, 0 )
	self._entWaypoint = nil

	local spawnInfo = self._gameRound:ChooseRandomSpawnInfo()
	if spawnInfo == nil then
		print( string.format( "Failed to get random spawn info for spawner %s.", self._szName ) )
		return
	end
	
	local entSpawner = Entities:FindByName( nil, spawnInfo.szSpawnerName )
	if not entSpawner then
		print( string.format( "Failed to find spawner named %s for %s.", spawnInfo.szSpawnerName, self._szName ) )
		return
	end
	self._vecSpawnLocation = entSpawner:GetAbsOrigin()

	if not self._bDontGiveGoal then
		self._entWaypoint = Entities:FindByName( nil, spawnInfo.szFirstWaypoint )
		if not self._entWaypoint then
			print( string.format( "Failed to find a waypoint named %s for %s.", spawnInfo.szFirstWaypoint, self._szName ) )
			return
		end
	end
end


function CHoldoutGameSpawner:_DoSpawn()
	local nUnitsToSpawn = math.min( self._nUnitsPerSpawn, self._nTotalUnitsToSpawn - self._nUnitsSpawnedThisRound )

	if nUnitsToSpawn <= 0 then
		return
	elseif self._nUnitsSpawnedThisRound == 0 then
		print( string.format( "Started spawning %s at %.2f", self._szName, GameRules:GetGameTime() ) )
	end

	if self._szSpawnerName == "" then
		self:_UpdateRandomSpawn()
	end

	local vBaseSpawnLocation = self:_GetSpawnLocation()
	if not vBaseSpawnLocation then return end
	for iUnit = 1,nUnitsToSpawn do
		local bIsChampion = RollPercentage( self._flChampionChance )
		if self._nChampionsSpawnedThisRound >= self._nChampionMax then
			bIsChampion = false
		end

		local szNPCClassToSpawn = self._szNPCClassName
		if bIsChampion and self._szChampionNPCClassName ~= "" then
			szNPCClassToSpawn = self._szChampionNPCClassName
		end

		local vSpawnLocation = vBaseSpawnLocation
		if not self._bDontOffsetSpawn then
			vSpawnLocation = vSpawnLocation + RandomVector( RandomFloat( 0, 200 ) )
		end

		local entUnit = CreateUnitByName( szNPCClassToSpawn, vSpawnLocation, true, nil, nil, DOTA_TEAM_BADGUYS )
		if entUnit then
			if entUnit:IsCreature() then
				if bIsChampion then
					self._nChampionsSpawnedThisRound = self._nChampionsSpawnedThisRound + 1
					entUnit:CreatureLevelUp( ( self._nChampionLevel - 1 ) )
					entUnit:SetChampion( true )
					local nParticle = ParticleManager:CreateParticle( "heavens_halberd", PATTACH_ABSORIGIN_FOLLOW, entUnit )
					ParticleManager:ReleaseParticleIndex( nParticle )
					entUnit:SetModelScale( 1.1, 0 )
				else
				 	entUnit:CreatureLevelUp( self._nCreatureLevel - 1 )
				 	-- level up by 0 (apparently this is required?)
				end
			end

			local entWp = self:_GetSpawnWaypoint()
			if entWp ~= nil then
				entUnit:SetInitialGoalEntity( entWp )
			end
			
			-- read in the number of players in the game
			local nPlayercount = ( PlayerResource:GetPlayerCountForTeam( DOTA_TEAM_GOODGUYS ) )
			
			if entUnit:IsCreature() then
				if entUnit:IsConsideredHero() then
					print("SPAWNER - IS HERO")
					AutoSetHeroLevelToRound(entUnit, self._gameRound._nRoundNumber, nPlayercount)
				else
					print("SPAWNER - IS CREATURE" )
					AutoSetCreatureLevelToRound(entUnit, self._gameRound._nRoundNumber, nPlayercount)
				end
				
			end

			--[[
			// THIS CODE HAS BEEN MOVED TO THE ONSPAWN EVENT IN HOLDOUT_GAME_ROUND.LUA
			// As this make more sense to do the health and damage changes to everything spawned including abilities that spawn creatures
			
			-- Adjust damage of spawned unit according to number of players
			
			local flDamageScalar = 0.1 + (nPlayercount  * 0.2 )
			local baseUnitDam = entUnit:GetBaseDamageMin()
			local baseUnitDamSpr = entUnit:GetBaseDamageMax() - baseUnitDam
			
			local newUnitDam = math.ceil(baseUnitDam * flDamageScalar)
			local newUnitDamSpr = math.ceil(baseUnitDamSpr * flDamageScalar)
			
			entUnit:SetBaseDamageMin(newUnitDam)
			entUnit:SetBaseDamageMax(baseUnitDam + newUnitDamSpr)
			print (string.format( "Scalar = %g, Base DAM of unit = %d / %d, new Base DAM = %d / %d ", flDamageScalar, baseUnitDam, baseUnitDam + baseUnitDamSpr , newUnitDam, newUnitDam + newUnitDamSpr) )
			
			
			-- Adjust the HP of spawned unit according to number of players
			local flHPScalar = 0.1 + (nPlayercount  * 0.2 )
			local baseUnitHP = entUnit:GetMaxHealth()
			local newUnitHP = math.ceil(baseUnitHP * flHPScalar)
			
			-- Set BASE max health will change the NPC base health and will not update until there's a state change
			-- So we set MAX health to change the initial state of the Health to the same thing when it's first spawned. 
			-- Otherwise it will spawn with it's old health until it changes state 
			-- (e.g. it attacks something, or receives some state change like being attacked or buff etc.)
			-- It's odd but hey, that's programming/state/interaction quirks for you!
			entUnit:SetBaseMaxHealth(newUnitHP)
			entUnit:SetMaxHealth(newUnitHP) 
			
			--entUnit:SetHealth(newUnitHP)
			print (string.format( "Scalar = %g, Base HP of unit = %d, new HP = %d ", flHPScalar, baseUnitHP, newUnitHP ) )
			
			]]

			-- In order to use the correct creature level up data, the creature needs to be levelled up here.

--[[
			entUnit:CreatureLevelUp( self._gameRound._nRoundNumber - 1 )

			if entUnit:IsConsideredHero() then
				print("is hero")
				entUnit:SetBaseStrength(self._gameRound._nRoundNumber -1)
			end
]]--

--[[			
			-- Adjust gold bounty for enemies that have them.
			-- Single player games have better bounties per player
			local flBountyScalar = 0.5 + (nPlayercount  * 0.25 )
			local nOldBounty = entUnit:GetMaximumGoldBounty()
			if nOldBounty > 0 then
				local nNewBounty = math.ceil(nOldBounty * flBountyScalar)
				entUnit:SetMinimumGoldBounty(nNewBounty)
				entUnit:SetMaximumGoldBounty(nNewBounty)
				print (string.format( "Scalar = %g, Base Gold of unit = %d, new Gold = %d ", flBountyScalar, nOldBounty, nNewBounty ) )
			end
]]--

			-- Keep track of how many units have been spawned
			self._nUnitsSpawnedThisRound = self._nUnitsSpawnedThisRound + 1
			self._nUnitsCurrentlyAlive = self._nUnitsCurrentlyAlive + 1
			
			entUnit.Holdout_IsCore = true
			
			-- Adjust XP on death to the amount set in the "map.txt" file / number of units spawned
		
			local flXPScalar = 0.4 + (nPlayercount  * 0.8 )
			local nOldXP = self._gameRound:GetXPPerCoreUnit()
			local nNewXP = math.ceil(nOldXP * flXPScalar)
			entUnit:SetDeathXP( nNewXP )
			print (string.format( "Scalar = %g, Base XP of unit = %d, new XP = %d \n", flXPScalar, nOldXP, nNewXP ) )

			
		end
	end
end


function CHoldoutGameSpawner:StatusReport()
	print( string.format( "** Spawner %s", self._szNPCClassName ) )
	print( string.format( "%d of %d spawned", self._nUnitsSpawnedThisRound, self._nTotalUnitsToSpawn ) )
end