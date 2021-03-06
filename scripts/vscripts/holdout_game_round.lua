--[[
	CHoldoutGameRound - A single round of Holdout
	When the map is initialized.
	It makes one of these for each of the rounds in the map txt. 

]]

if CHoldoutGameRound == nil then
	CHoldoutGameRound = class({})
end


function CHoldoutGameRound:ReadConfiguration( kv, gameMode, roundNumber )
	self._gameMode = gameMode
	self._nRoundNumber = roundNumber
	self._szRoundQuestTitle = kv.round_quest_title or "#DOTA_Quest_Holdout_Round"
	self._szRoundTitle = kv.round_title or string.format( "Round%d", roundNumber )
				
	self._nMaxGold = tonumber( kv.MaxGold or 0 )
	self._nBagCount = tonumber( kv.BagCount or 0 )
	self._nBagVariance = tonumber( kv.BagVariance or 0 )
	self._nFixedXP = tonumber( kv.FixedXP or 0 )

	self._vSpawners = {}
	for k, v in pairs( kv ) do
		if type( v ) == "table" and v.NPCName then
			local spawner = CHoldoutGameSpawner()
			spawner:ReadConfiguration( k, v, self )
			self._vSpawners[ k ] = spawner
		end
	end

	for _, spawner in pairs( self._vSpawners ) do
		spawner:PostLoad( self._vSpawners )
	end
end


function CHoldoutGameRound:Precache()
	for _, spawner in pairs( self._vSpawners ) do
		spawner:Precache()
	end
end

function CHoldoutGameRound:Begin()
	self._vEnemiesRemaining = {}
	self._vEventHandles = {
		ListenToGameEvent( "npc_spawned", Dynamic_Wrap( CHoldoutGameRound, "OnNPCSpawned" ), self ),
		ListenToGameEvent( "entity_killed", Dynamic_Wrap( CHoldoutGameRound, "OnEntityKilled" ), self ),
		ListenToGameEvent( "dota_item_picked_up", Dynamic_Wrap( CHoldoutGameRound, 'OnItemPickedUp' ), self ),
		ListenToGameEvent( "dota_holdout_revive_complete", Dynamic_Wrap( CHoldoutGameRound, 'OnHoldoutReviveComplete' ), self )
	}

	self._vPlayerStats = {}
	for nPlayerID = 0, DOTA_MAX_TEAM_PLAYERS-1 do
		self._vPlayerStats[ nPlayerID ] = {
			nCreepsKilled = 0,
			nGoldBagsCollected = 0,
			nPriorRoundDeaths = PlayerResource:GetDeaths( nPlayerID ),
			nPlayersResurrected = 0
		}
	end

	self._nGoldRemainingInRound = self._nMaxGold
	self._nGoldBagsRemaining = self._nBagCount
	self._nGoldBagsExpired = 0
	self._nCoreUnitsTotal = 0
	for _, spawner in pairs( self._vSpawners ) do
		spawner:Begin()
		self._nCoreUnitsTotal = self._nCoreUnitsTotal + spawner:GetTotalUnitsToSpawn()
	end
	self._nCoreUnitsKilled = 0

--[[
	self._entQuest = SpawnEntityFromTableSynchronous( "quest", {
		name = self._szRoundTitle,
		title =  self._szRoundQuestTitle
	})
	self._entQuest:SetTextReplaceValue( QUEST_TEXT_REPLACE_VALUE_ROUND, self._nRoundNumber )
	self._entQuest:SetTextReplaceString( self._gameMode:GetDifficultyString() )

	 self._entKillCountSubquest = SpawnEntityFromTableSynchronous( "subquest_base", {
	 	show_progress_bar = true,
	 	progress_bar_hue_shift = -119
	 } )

	self._entQuest:AddSubquest( self._entKillCountSubquest )
	self._entKillCountSubquest:SetTextReplaceValue( SUBQUEST_TEXT_REPLACE_VALUE_TARGET_VALUE, self._nCoreUnitsTotal )
--]]
	-- Load up the event "laststand_round_title" (in customevents.txt) with the beginning round information
	-- "Roundinfo is just a kv pair container that is oppened up and the values replace those that exist in the custom events txt"
	
	local roundInfo = {
		nRoundNumber = self._nRoundNumber,
		roundQuestTitle = self._szRoundQuestTitle,
		roundName = self._szRoundTitle
	}

	CustomGameEventManager:Send_ServerToAllClients( "start_round_info", roundInfo )
	CustomGameEventManager:Send_ServerToAllClients( "round_start", nil )

	end


function CHoldoutGameRound:End()
	for _, eID in pairs( self._vEventHandles ) do
		StopListeningToGameEvent( eID )
	end
	self._vEventHandles = {}

	for _,unit in pairs( FindUnitsInRadius( DOTA_TEAM_BADGUYS, Vector( 0, 0, 0 ), nil, FIND_UNITS_EVERYWHERE, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_ALL, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false )) do
		if not unit:IsTower() then
			UTIL_RemoveImmediate( unit )
		end
	end

	for _,spawner in pairs( self._vSpawners ) do
		spawner:End()
	end
--[[
	if self._entQuest then
		UTIL_RemoveImmediate( self._entQuest )
		self._entQuest = nil
		self._entKillCountSubquest = nil
	end
--]]
	CustomGameEventManager:Send_ServerToAllClients( "round_end", nil )

	local nTowers = 0
	local nTowersStanding = 0
	for _,unit in pairs( FindUnitsInRadius( DOTA_TEAM_GOODGUYS, Vector( 0, 0, 0 ), nil, FIND_UNITS_EVERYWHERE, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_BUILDING, DOTA_UNIT_TARGET_FLAG_DEAD, FIND_ANY_ORDER, false ) ) do
		if unit:IsTower() then
			nTowers = nTowers + 1
			if unit:IsAlive() then
				nTowersStanding = nTowersStanding + 1
			end
		end
	end
	local nTowersStandingGoldReward = self._gameMode:ComputeTowerBonusGold( nTowers, nTowersStanding )
	for nPlayerID = 0, DOTA_MAX_TEAM_PLAYERS-1 do
		if PlayerResource:HasSelectedHero( nPlayerID ) then
			PlayerResource:ModifyGold( nPlayerID, nTowersStandingGoldReward, true, DOTA_ModifyGold_Unspecified )
		end
	end

	local roundEndSummary = {
		nRoundNumber = self._nRoundNumber - 1,
		nRoundDifficulty = GameRules:GetCustomGameDifficulty(),
		roundName = self._szRoundTitle,
		nTowers = nTowers,
		nTowersStanding = nTowersStanding,
		nTowersStandingGoldReward = nTowersStandingGoldReward,
		nGoldBagsExpired = self._nGoldBagsExpired
	}

	local playerSummaryCount = 0
	for i = 1, DOTA_MAX_TEAM_PLAYERS do
		local nPlayerID = i-1
		if PlayerResource:HasSelectedHero( nPlayerID ) then
			local szPlayerPrefix = string.format( "Player_%d_", playerSummaryCount)
			playerSummaryCount = playerSummaryCount + 1
			local playerStats = self._vPlayerStats[ nPlayerID ]
			roundEndSummary[ szPlayerPrefix .. "HeroName" ] = PlayerResource:GetSelectedHeroName( nPlayerID )
			roundEndSummary[ szPlayerPrefix .. "CreepKills" ] = playerStats.nCreepsKilled
			roundEndSummary[ szPlayerPrefix .. "GoldBagsCollected" ] = playerStats.nGoldBagsCollected
			roundEndSummary[ szPlayerPrefix .. "Deaths" ] = PlayerResource:GetDeaths( nPlayerID ) - playerStats.nPriorRoundDeaths
			roundEndSummary[ szPlayerPrefix .. "PlayersResurrected" ] = playerStats.nPlayersResurrected
		end
	end
	-- FireGameEvent( "holdout_show_round_end_summary", roundEndSummary )
end


function CHoldoutGameRound:Think()
	for _, spawner in pairs( self._vSpawners ) do
		spawner:Think()
	end
end


function CHoldoutGameRound:ChooseRandomSpawnInfo()
	return self._gameMode:ChooseRandomSpawnInfo()
end


function CHoldoutGameRound:IsFinished()
	for _, spawner in pairs( self._vSpawners ) do
		if not spawner:IsFinishedSpawning() then
			return false
		end
	end
	local nEnemiesRemaining = #self._vEnemiesRemaining
	if nEnemiesRemaining == 0 then
		return true
	end

	if not self._lastEnemiesRemaining == nEnemiesRemaining then
		self._lastEnemiesRemaining = nEnemiesRemaining
		print ( string.format( "%d enemies remaining in the round...", #self._vEnemiesRemaining ) )
	end
	return false
end


-- Rather than use the xp granting from the units keyvalues file,
-- we let the round determine the xp per unit to grant as a flat value.
-- This is done to make tuning of rounds easier.
function CHoldoutGameRound:GetXPPerCoreUnit()
	if self._nCoreUnitsTotal == 0 then
		return 0
	else
		return math.floor( self._nFixedXP / self._nCoreUnitsTotal )
	end
end

-- This function is for regular creatures spawned. e.g. Kobolds, Ghosties, Gnolls. etc.. 
function AutoSetCreatureLevelToRound(unit, roundnumber, players)
	print (string.format( "----------  %s  ----------- \n AutoSetCreatureLevelToRound ( %d )", unit:GetUnitName(), roundnumber ) )
	unit:CreatureLevelUp(roundnumber-1)
	AutoAdjustUnitMaxHealthToPlayerCount(unit, players)
	AutoAdjustUnitDamageToPlayerCount(unit, players)
	AutoAdjustUnitBountyToPlayerCount(unit, players)
	print ("--------- Finished ------------ \n")
end

-- This function is for creatures that are considered heros e.g. Furion, Corpselords, creeps that use hero models etc....
function AutoSetHeroLevelToRound(unit, roundnumber, players)
	print (string.format( "----------  %s  ----------- \n AutoSetHeroLevelToRound ( %d )", unit:GetUnitName(), roundnumber ) )
	-- Set the level, but this does nothing except make it look like level(x)
	unit:CreatureLevelUp(roundnumber-1)
	SetHeroCreepHealth(unit, roundnumber)
	SetHeroCreepDamage(unit, roundnumber)
	AutoAdjustUnitMaxHealthToPlayerCount(unit, players)
	AutoAdjustUnitDamageToPlayerCount(unit, players)
	AutoAdjustUnitBountyToPlayerCount(unit, players)
	print ("--------- Finished ------------ \n")
end

-- This function is for creeps that are spawned as part of an ability. e.g. Furion's treants.
function AutoSetAbilityCreepLevelToRound(unit, roundnumber, players)
	print (string.format( "----------  %s  ----------- \n AutoSetAbilityCreepLevelToRound ( %d )", unit:GetUnitName(), roundnumber ) )
	-- Set the level, but this does nothing except make it look like level(x)
	SetHeroCreepHealth(unit, roundnumber)
	SetHeroCreepDamage(unit, roundnumber)
	AutoAdjustUnitMaxHealthToPlayerCount(unit, players)
	AutoAdjustUnitDamageToPlayerCount(unit, players)
	print ("--------- Finished ------------ \n")
end

function SetHeroCreepHealth(unit, level)

	-- Get existing health values
	local getHealth = unit:GetHealth()
	local getBaseMaxHealth = unit:GetBaseMaxHealth() 
	local baseUnitHP = unit:GetMaxHealth()

	-- Set Health according to level. This is an overriding function.
	local scalarPerLevel = 0.1
	local flHPPerLevel = (getBaseMaxHealth * scalarPerLevel)
	
	local newUnitHP = math.ceil(baseUnitHP + ( flHPPerLevel * level ))

	-- Apply this health to the hero creep. For this level/round 
	-- This is the HP before any player adjustment is made!
	unit:SetBaseMaxHealth(newUnitHP)
	unit:SetMaxHealth(newUnitHP) 

	print (string.format( "SetHeroCreepHealth: \n HP Per Level = %g @ %g %% (for %d levels), Base HP of unit = %d ==> New HP = %d", flHPPerLevel, (scalarPerLevel*100) , level, baseUnitHP, newUnitHP ) )
end

function SetHeroCreepDamage(unit, level)

	local baseUnitDam = unit:GetBaseDamageMin()
	local baseUnitDamSpr = unit:GetBaseDamageMax() - baseUnitDam

	local scalarPerLevel = 0.1
	local flDamPerLevel = baseUnitDam * scalarPerLevel
	local flSprPerLevel =  baseUnitDamSpr * scalarPerLevel 
			
	local newUnitDam = math.ceil( baseUnitDam + ( flDamPerLevel * level ) )
	local newUnitDamSpr = math.ceil( baseUnitDamSpr + ( flSprPerLevel * level ) )
			
	unit:SetBaseDamageMin(newUnitDam)
	unit:SetBaseDamageMax(newUnitDam + newUnitDamSpr)
	
	print (string.format( "SetHeroCreepDamage: \n DAM Per Level = %g @ %g %% (for %d levels), Base DAM of unit = %d / %d ==> New Base DAM = %d / %d ", flDamPerLevel, (scalarPerLevel*100), level, baseUnitDam, baseUnitDam + baseUnitDamSpr , newUnitDam, newUnitDam + newUnitDamSpr ) )

end


function AutoAdjustUnitMaxHealthToPlayerCount(unit, numberofplayers)
	print (string.format( "Balancing HP for %d players.", numberofplayers) )
	local flHPScalar = 0.1 + ( numberofplayers  * 0.2 )  

	-- Get existing health values
	local getHealth = unit:GetHealth()
	local getBaseMaxHealth = unit:GetBaseMaxHealth() 
	local baseUnitHP = unit:GetMaxHealth()
	local newUnitHP = math.ceil(baseUnitHP * flHPScalar)

	-- Set new health
	unit:SetBaseMaxHealth(newUnitHP)
	unit:SetMaxHealth(newUnitHP) 
	print (string.format( "AutoAdjustUnitMaxHealthToPlayerCount:\n Scalar = %g, Base HP of unit = %d, new HP = %d", flHPScalar, baseUnitHP, newUnitHP ) )
					
end

function AutoAdjustUnitDamageToPlayerCount(unit, numberofplayers)
	print (string.format( "Balancing DAM for %d players.", numberofplayers) )
	local flDamageScalar = 0.1 + (numberofplayers  * 0.15 )
	local baseUnitDam = unit:GetBaseDamageMin()
	local baseUnitDamSpr = unit:GetBaseDamageMax() - baseUnitDam
	
	local newUnitDam = math.ceil(baseUnitDam * flDamageScalar)
	local newUnitDamSpr = math.ceil(baseUnitDamSpr * flDamageScalar)
	
	unit:SetBaseDamageMin(newUnitDam)
	unit:SetBaseDamageMax(newUnitDam + newUnitDamSpr)
	print (string.format( "AutoAdjustUnitDamageToPlayerCount:\n Scalar = %g, Base DAM of unit = %d / %d, new Base DAM = %d / %d ", flDamageScalar, baseUnitDam, baseUnitDam + baseUnitDamSpr , newUnitDam, newUnitDam + newUnitDamSpr) )

end

function AutoAdjustUnitBountyToPlayerCount(unit, numberofplayers)

	-- Adjust gold bounty for enemies that have them.
	-- Single player games have better bounties per player
	local flBountyScalar = 0.75 + (numberofplayers  * 0.4 )
	local nOldBounty = unit:GetMaximumGoldBounty()
	if nOldBounty > 0 then
		local nNewBounty = math.ceil(nOldBounty * flBountyScalar)
		unit:SetMinimumGoldBounty(nNewBounty)
		unit:SetMaximumGoldBounty(nNewBounty)
		print (string.format( "Scalar = %g, Base Gold of unit = %d, new Gold = %d ", flBountyScalar, nOldBounty, nNewBounty ) )
	end


end

function CHoldoutGameRound:OnNPCSpawned( event )
	local spawnedUnit = EntIndexToHScript( event.entindex )
	if not spawnedUnit or spawnedUnit:IsPhantom() or spawnedUnit:GetClassname() == "npc_dota_thinker" or spawnedUnit:GetUnitName() == "" then
		return
	end

	if spawnedUnit:GetTeamNumber() == DOTA_TEAM_BADGUYS then
		spawnedUnit:SetMustReachEachGoalEntity(true)
		table.insert( self._vEnemiesRemaining, spawnedUnit )
		
	-- read in the number of players in the game
	local nPlayercount = ( PlayerResource:GetPlayerCountForTeam( DOTA_TEAM_GOODGUYS ) )

		--[[ Any unit/creature that is spawned during a round, we can assume is an ability spawned unit and should not
		give xp or gold since this would be an exploit! However, they cannot be levelled up correctly using creature data
		and must use a discrete system instead!
		]]--
		
		if spawnedUnit:GetDeathXP() == 0 then
			print("This unit has NO XP")
			AutoSetAbilityCreepLevelToRound(spawnedUnit, self._nRoundNumber, nPlayercount)
		else
			-- Any unit being spawned, either by ability, or round map spawn must be given 0 XP for exploit reasons
			print("This unit has initial XP, but resetting it to 0")
			spawnedUnit:SetDeathXP( 0 )
		end
				
			
--[[
			-- Adjust damage of spawned unit according to number of players
			-- E.g. @ [0.1 base & 0.15 per player]  1 player = 25% Damage, 5 players = 85%Damage, 10 Players =  160% Damage
			--spawnedUnit:SetLevel(self._nRoundNumber)
			--print (string.format( "Set unit level to: %d ", self._nRoundNumber) )
			local getHealth = spawnedUnit:GetHealth()
			local getBaseMaxHealth = spawnedUnit:GetBaseMaxHealth() 
			local baseUnitHP = spawnedUnit:GetMaxHealth()

			print (string.format( "HP STATS BEFORE LEVELLING UP: getHealth = %d, getBaseMaxHealth = %d, getMaxHealth = %d", getHealth, getBaseMaxHealth, baseUnitHP ) )
]]--

--[[
			if spawnedUnit:IsCreature() then
				print (string.format("Spawned Creature, levelling up to round number: %d", ( self._nRoundNumber-1 ) ) )
				if spawnedUnit:IsConsideredHero() then
					print ("IS HERO!")
				end
					--spawnedUnit:CreatureLevelUp( self._nRoundNumber-1 ) 
				
			end
]]--

--[[
			local flDamageScalar = 0.10 + (nPlayercount  * 0.15 )
			local baseUnitDam = spawnedUnit:GetBaseDamageMin()
			local baseUnitDamSpr = spawnedUnit:GetBaseDamageMax() - baseUnitDam
			
			local newUnitDam = math.ceil(baseUnitDam * flDamageScalar)
			local newUnitDamSpr = math.ceil(baseUnitDamSpr * flDamageScalar)
			
			spawnedUnit:SetBaseDamageMin(newUnitDam)
			spawnedUnit:SetBaseDamageMax(newUnitDam + newUnitDamSpr)
			print (string.format( "Scalar = %g, Base DAM of unit = %d / %d, new Base DAM = %d / %d ", flDamageScalar, baseUnitDam, baseUnitDam + baseUnitDamSpr , newUnitDam, newUnitDam + newUnitDamSpr) )
]]--

--[[
			-- Adjust the HP of spawned unit according to number of players
			-- E.g. @ [0.1 base & 0.1 per player & 0.1 per player]  1 player = 25% HP, 2 players = 40% HP, 3 = 65 %HP, 4 = 100%  , 5 = 145%, 6 = 200% 10 = 510%
			local flHPScalar = 0.01 + ( nPlayercount  * 0.2 )  
			getHealth = spawnedUnit:GetHealth()
			getBaseMaxHealth = spawnedUnit:GetBaseMaxHealth() 
			baseUnitHP = spawnedUnit:GetMaxHealth()
			local newUnitHP = math.ceil(baseUnitHP * flHPScalar)

			print (string.format( "HP STATS AFTER LEVELLING UP: getHealth = %d, getBaseMaxHealth = %d, getMaxHealth = %d", getHealth, getBaseMaxHealth, baseUnitHP ) )
			
			-- Set BASE max health will change the NPC base health and will not update until there's a state change
			-- So we set MAX health to change the initial state of the Health to the same thing when it's first spawned. 
			-- Otherwise it will spawn with it's old health until it changes state 
			-- (e.g. it attacks something, or receives some state change like being attacked or buff etc.)
			-- It's odd but hey, that's programming/state/interaction quirks for you!
			spawnedUnit:SetBaseMaxHealth(newUnitHP)
			spawnedUnit:SetMaxHealth(newUnitHP) 
			
			--entUnit:SetHealth(newUnitHP)
			print (string.format( "Scalar = %g, Base HP of unit = %d, new HP = %d", flHPScalar, baseUnitHP, newUnitHP ) )
]]--			

		spawnedUnit.unitName = spawnedUnit:GetUnitName()

	end
end


function CHoldoutGameRound:OnEntityKilled( event )
	local killedUnit = EntIndexToHScript( event.entindex_killed )
	if not killedUnit then
		return
	end

	for i, unit in pairs( self._vEnemiesRemaining ) do
		if killedUnit == unit then
			table.remove( self._vEnemiesRemaining, i )
				local roundStatus = {
					nEnemiesLeft = self._nCoreUnitsKilled,
					nEnemiesTotal = self._nCoreUnitsTotal,
					nEnemiesPercentageLeft = ( self._nCoreUnitsKilled/ self._nCoreUnitsTotal )*100
					}
				CustomGameEventManager:Send_ServerToAllClients( "round_status", roundStatus )
				print("enemy killed")
			break
		end
	end	
	if killedUnit.Holdout_IsCore then
		self._nCoreUnitsKilled = self._nCoreUnitsKilled + 1
		self:_CheckForGoldBagDrop( killedUnit )
		self._gameMode:CheckForLootItemDrop( killedUnit )
		if self._entKillCountSubquest then
			self._entKillCountSubquest:SetTextReplaceValue( QUEST_TEXT_REPLACE_VALUE_CURRENT_VALUE, self._nCoreUnitsKilled )
		end
	end

	local attackerUnit = EntIndexToHScript( event.entindex_attacker or -1 )
	if attackerUnit then
		local playerID = attackerUnit:GetPlayerOwnerID()
		local playerStats = self._vPlayerStats[ playerID ]
		if playerStats then
			playerStats.nCreepsKilled = playerStats.nCreepsKilled + 1
		end
	end
end


function CHoldoutGameRound:OnHoldoutReviveComplete( event )
	local castingHero = EntIndexToHScript( event.caster )
	if castingHero then
		local nPlayerID = castingHero:GetPlayerOwnerID()
		local playerStats = self._vPlayerStats[ nPlayerID ]
		if playerStats then
			playerStats.nPlayersResurrected = playerStats.nPlayersResurrected + 1
		end
	end
end


function CHoldoutGameRound:OnItemPickedUp( event )
	if event.itemname == "item_bag_of_gold" then
		local playerStats = self._vPlayerStats[ event.PlayerID ]
		if playerStats then
			playerStats.nGoldBagsCollected = playerStats.nGoldBagsCollected + 1
		end
	end
end


function CHoldoutGameRound:_CheckForGoldBagDrop( killedUnit )
	if self._nGoldRemainingInRound <= 0 then
		return
	end

	local nGoldToDrop = 0
	local nCoreUnitsRemaining = self._nCoreUnitsTotal - self._nCoreUnitsKilled
	if nCoreUnitsRemaining <= 0 then
		nGoldToDrop = self._nGoldRemainingInRound
	else
		local flCurrentDropChance = self._nGoldBagsRemaining / (1 + nCoreUnitsRemaining)
		if RandomFloat( 0, 1 ) <= flCurrentDropChance then
			if self._nGoldBagsRemaining <= 1 then
				nGoldToDrop = self._nGoldRemainingInRound
			else
				nGoldToDrop = math.floor( self._nGoldRemainingInRound / self._nGoldBagsRemaining )
				nCurrentGoldDrop = math.max(1, RandomInt( nGoldToDrop - self._nBagVariance, nGoldToDrop + self._nBagVariance  ) )
			end
		end
	end
	
	nGoldToDrop = math.min( nGoldToDrop, self._nGoldRemainingInRound )
	if nGoldToDrop <= 0 then
		return
	end
	self._nGoldRemainingInRound = math.max( 0, self._nGoldRemainingInRound - nGoldToDrop )
	self._nGoldBagsRemaining = math.max( 0, self._nGoldBagsRemaining - 1 )

	local newItem = CreateItem( "item_bag_of_gold", nil, nil )
	newItem:SetPurchaseTime( 0 )
	
	-- Adjust gold dropped in a bag by the amount of players in the game 
	-- May need to remove as this is given to all players so it's self balancing!
	local nPlayers = PlayerResource:GetPlayerCountForTeam( DOTA_TEAM_GOODGUYS )
	local nAdjustGoldToDrop = nGoldToDrop + ( nGoldToDrop * ( (nPlayers - 1) * (0.6 - ((nPlayers - 1) * 0.1) ) ) )
	newItem:SetCurrentCharges( math.floor(nAdjustGoldToDrop) )
	print (string.format( "Gold dropped: Base = %d | Adjusted = %d", nGoldToDrop, nAdjustGoldToDrop ) )
	
	-- newItem:SetCurrentCharges( nGoldToDrop )
	
	local drop = CreateItemOnPositionSync( killedUnit:GetAbsOrigin(), newItem )
	local dropTarget = killedUnit:GetAbsOrigin() + RandomVector( RandomFloat( 50, 350 ) )
	newItem:LaunchLoot( true, 300, 0.75, dropTarget )
end


function CHoldoutGameRound:StatusReport( )
	print( string.format( "Enemies remaining: %d", #self._vEnemiesRemaining ) )
	for _,e in pairs( self._vEnemiesRemaining ) do
		if e:IsNull() then
			print( string.format( "<Unit %s Deleted from C++>", e.unitName ) )
		else
			print( e:GetUnitName() )
		end
	end
	print( string.format( "Spawners: %d", #self._vSpawners ) )
	for _,s in pairs( self._vSpawners ) do
		s:StatusReport()
	end
end