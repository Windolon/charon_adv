try { IncludeScript( "lobo_core.nut" ) }
catch ( e ) { ClientPrint( null, 3, "Failed to find or run script file lobo_core.nut. This mission will not function correctly. Please make sure the map is on the latest version." ) }

LOBO.AddHookedTag( "testtag",
{
	OnSpawn = function( bot )
	{
		printl( bot + " with tag testtag has spawned" )
	}

	OnTakeDamage = function( bot, params )
	{
		local attacker = params.attacker
		if ( attacker )
			printl( bot + " is about to take damage from " + attacker )

		params.damage *= 0.2
	}

	OnTakeDamagePost = function( bot, params )
	{
		printl( bot + " took " params.damageamount + " damage, now at " + params.health + " HP" )
	}

	OnDeath = function( bot, params )
	{
		printl( bot + " died, the crit type was " + params.crit_type )
	}
})
