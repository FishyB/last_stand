function AddBaseStatAgility( event )
    
    local hero = event.caster
    local ability = event.ability
    local statBonus = event.stack_size

    --casterUnit:SetBaseAgility( casterUnit:GetBaseAgility() + 1 )
    --casterUnit:ModifyAgility(statBonus)

    -- Make sure it isn't an Illusion, or Bear. If not, then make sure the hero is the owner of this bear.
    if hero:IsRealHero() == false then
    	hero = hero:GetPlayerOwner():GetAssignedHero()
    end

    if hero:HasModifier("modifier_item_add_agility") == false then
        print("hero has no AGI modifier yet, assigning them one")
        ability:ApplyDataDrivenModifier( hero, hero, "modifier_item_add_agility", nil)
        hero:SetModifierStackCount("modifier_item_add_agility", hero, statBonus)
    else
         print("Already has modifier, adding to existing one")
        hero:SetModifierStackCount("modifier_item_add_agility", hero, (hero:GetModifierStackCount("modifier_item_add_agility", hero) + statBonus) )
    end

end


function AddBaseStatIntelligence( event )
    
    local hero = event.caster
    local ability = event.ability
    local statBonus = event.stack_size

    --casterUnit:SetBaseAgility( casterUnit:GetBaseAgility() + 1 )
    --casterUnit:ModifyAgility(statBonus)

    -- Make sure it isn't an Illusion, or Bear. If not, then make sure the hero is the owner of this bear.
    if hero:IsRealHero() == false then
        hero = hero:GetPlayerOwner():GetAssignedHero()
    end

    if hero:HasModifier("modifier_item_add_intelligence") == false then
        print("hero has no INT modifier yet, assigning them one")
        ability:ApplyDataDrivenModifier( hero, hero, "modifier_item_add_intelligence", nil)
        hero:SetModifierStackCount("modifier_item_add_intelligence", hero, statBonus)
    else
         print("Already has modifier, adding to existing one")
        hero:SetModifierStackCount("modifier_item_add_intelligence", hero, (hero:GetModifierStackCount("modifier_item_add_intelligence", hero) + statBonus) )
    end

end


function AddBaseStatStrength( event )
    
    local hero = event.caster
    local ability = event.ability
    local statBonus = event.stack_size

    --casterUnit:SetBaseAgility( casterUnit:GetBaseAgility() + 1 )
    --casterUnit:ModifyAgility(statBonus)

    -- Make sure it isn't an Illusion, or Bear. If not, then make sure the hero is the owner of this bear.
    if hero:IsRealHero() == false then
        hero = hero:GetPlayerOwner():GetAssignedHero()
    end

    if hero:HasModifier("modifier_item_add_strength") == false then
        print("hero has no STR modifier yet, assigning them one")
        ability:ApplyDataDrivenModifier( hero, hero, "modifier_item_add_strength", nil)
        hero:SetModifierStackCount("modifier_item_add_strength", hero, statBonus)
    else
         print("Already has modifier, adding to existing one")
        hero:SetModifierStackCount("modifier_item_add_strength", hero, (hero:GetModifierStackCount("modifier_item_add_strength", hero) + statBonus) )
    end

end