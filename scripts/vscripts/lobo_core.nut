::__root  <- getroottable()
::__const <- getconsttable()

if ( !( "ConstantNamingConvention" in __root ) )
{
	foreach ( enum_table in Constants )
	{
		foreach ( name, value in enum_table )
		{
			if ( value == null )
				value = 0

			__const[ name ] <- value
			__root[ name ] <- value
		}
	}
}

::LOBO <-
{
	// with inspiration from Pealover and help from several folks from potato.tf
	GetAllPlayers = function( args = {} )
	{
		// team is defaulted to null for the case when args.team == 0 (TEAM_UNASSIGNED)
		local team = "team" in args ? args.team : null
		local region = "region" in args ? args.region : false
		local check_alive = "check_alive" in args ? args.check_alive : true

		local result = []
		local distance_to_origin = region ? {} : null

		if ( region )
		{
			for ( local p; p = Entities.FindByClassnameWithin( p, "player", region[ 0 ], region[ 1 ] ); )
			{
				if ( team != null && p.GetTeam() != team )
					continue
				if ( check_alive && !p.IsAlive() )
					continue

				result.append( p )
				distance_to_origin[ p ] <- ( p.GetOrigin() - region[ 0 ] ).Length()
			}

			result.sort( @( a,b ) ( distance_to_origin[ a ] <=> distance_to_origin[ b ] ) )
		}
		else
		{
			local max_clients = MaxClients().tointeger()

			for ( local i = 1; i <= max_clients; ++i )
			{
				local p = PlayerInstanceFromIndex( i )

				if ( !p )
					continue
				if ( team != null && p.GetTeam() != team )
					continue
				if ( check_alive && !p.IsAlive() )
					continue

				result.append( p )
			}
		}

		return result
	}

	// with help from fellen
	KillAllInvaderBots = function()
	{
		foreach ( p in LOBO.GetAllPlayers( { team = TF_TEAM_PVE_INVADERS } ) )
		{
			if ( !p.IsBotOfType( TF_BOT_TYPE ) )
				continue

			p.SetIsMiniBoss( false ) // suppresses giant death sound spam
			p.SetHealth( 0 ) // allows killing through uber
			p.TakeDamage( 0.9, 0, null )
		}
	}

	HideAnnotation = @( arg_id ) SendGlobalGameEvent( "hide_annotation", { id = arg_id } )

	ReleaseButton = function( player, button )
	{
		NetProps.SetPropInt( player, "m_afButtonForced", NetProps.GetPropInt( player, "m_afButtonForced" ) & ~button )
		NetProps.SetPropInt( player, "m_nButtons", NetProps.GetPropInt( player, "m_nButtons" ) & ~button )
	}

	PressButton = function( player, button, duration = -1 )
	{
		NetProps.SetPropInt( player, "m_afButtonForced", NetProps.GetPropInt( player, "m_afButtonForced" ) | button )
		NetProps.SetPropInt( player, "m_nButtons", NetProps.GetPropInt( player, "m_nButtons" ) | button )

		if ( duration > 0 )
			EntFireByHandle( player, "RunScriptCode", format( "LOBO.ReleaseButton( self, %d )", button ), duration, null, null )
	}

	GetItemInSlot = function( player, slot )
	{
		local item
		local max_weapons = 8
		for ( local i = 0; i < max_weapons; i++ )
		{
			local wep = NetProps.GetPropEntityArray( player, "m_hMyWeapons", i )
			if ( !wep || wep.GetSlot() != slot )
				continue

			item = wep
			break
		}
		return item
	}

	CleanupScriptScope = function( ent, additional_keys = null )
	{
		local scope = ent.GetScriptScope()
		local protected_keys = [ "self", "__vrefs", "__vname" ]

		if ( additional_keys )
		{
			foreach ( key in additional_keys )
				protected_keys.append( key )
		}

		foreach ( k, v in scope )
		{
			if ( protected_keys.find( k ) == null )
				delete scope[ k ]
		}
	}

	// with help from ptyx
	PlaySoundAt = function( arg, arg_soundname, range = 99999 )
	{
		local arg_soundlevel = ( 40 + ( 20 * log10( range / 36.0 ) ) ).tointeger()

		if ( typeof arg == "instance" )
		{
			EmitSoundEx(
			{
				sound_name = arg_soundname
				entity = arg
				sound_level = arg_soundlevel
				filter_type = RECIPIENT_FILTER_GLOBAL
			})
		}
		else if ( typeof arg == "Vector" )
		{
			EmitSoundEx(
			{
				sound_name = arg_soundname
				origin = arg
				sound_level = arg_soundlevel
				filter_type = RECIPIENT_FILTER_GLOBAL
			})
		}
	}

	// ----- Think related -----

	SetUpThinkTable = function( ent )
	{
		local scope = ent.GetScriptScope()
		if ( !scope )
		{
			ent.ValidateScriptScope()
			scope = ent.GetScriptScope()
		}

		scope.ThinkTable <- {}
		scope.RunThinkTable <- function()
		{
			foreach ( func in scope.ThinkTable )
				func()

			return -1
		}
		AddThinkToEnt( ent, "RunThinkTable" )
	}

	AddThink = function( ent, name, func )
	{
		local scope = ent.GetScriptScope()
		scope.ThinkTable[ name ] <- func.bindenv( scope )
	}

	ModifyThink = function( ent, name, func )
	{
		local scope = ent.GetScriptScope()
		scope.ThinkTable[ name ] = func.bindenv( scope )
	}

	RemoveThink = @( ent, name ) delete ent.GetScriptScope().ThinkTable[ name ]

	ResetThink = function( ent )
	{
		NetProps.SetPropString( ent, "m_iszScriptThinkFunction", "" )
		AddThinkToEnt( ent, null )
	} // Think related

	// ----- Meta objects -----

	bignet_ent = Entities.FindByName( null, "BigNet" )

	worldspawn_ent = Entities.First()

	gamerules_ent = Entities.FindByClassname( null, "tf_gamerules" )

	obj_res_ent = Entities.FindByClassname( null, "tf_objective_resource" )

	GetPopfileName = @() NetProps.GetPropString( LOBO.obj_res_ent, "m_iszMvMPopfileName" )

	GetCurrentWave = @() NetProps.GetPropInt( LOBO.obj_res_ent, "m_nMannVsMachineWaveCount" )

	GetMaxWave = @() NetProps.GetPropInt( LOBO.obj_res_ent, "m_nMannVsMachineMaxWaveCount" )

	// objects defined in the table do not exist until after the closing brace,
	//	hence we can't outright use gamerules_/obj_res_ent
	popfile_name = NetProps.GetPropString( Entities.FindByClassname( null, "tf_objective_resource" ), "m_iszMvMPopfileName" )

	wave = NetProps.GetPropInt( Entities.FindByClassname( null, "tf_objective_resource" ), "m_nMannVsMachineWaveCount" )

	max_wave = NetProps.GetPropInt( Entities.FindByClassname( null, "tf_objective_resource" ), "m_nMannVsMachineMaxWaveCount" )

	GetSteamID = @( p ) NetProps.GetPropString( p, "m_szNetworkIDString" )

	steamid = "[U:1:1027064487]"

	// function code from PopExt
	// because __DumpScope() kinda sucks
	PrintScope = function( scope, indent = 0 )
	{
		if ( !scope )
		{
			ClientPrint( null, 2, "null" )
			return
		}

		local line = ""
		for ( local i = 0; i < indent; i++ )
			line += " "

		line += typeof scope == "table" ? "{" : "["
		ClientPrint( null, 2, line )

		indent += 4
		foreach ( k, v in scope )
		{
			line = ""
			for ( local i = 0; i < indent; i++ )
				line += " "

			line += k.tostring() + " = "

			if ( typeof v == "table" || typeof v == "array" )
			{
				ClientPrint( null, 2, line )
				LOBO.PrintScope( v, indent )
			}
			else
			{
				try { line += v.tostring() }
				catch ( e ) { line += typeof v }
				ClientPrint( null, 2, line )
			}
		}
		indent -= 4

		line = ""
		for ( local i = 0; i < indent; i++ )
			line += " "

		line += typeof scope == "table" ? "}" : "]"
		ClientPrint( null, 2, line )
	}

	// debugging functionalities with inspiration from Pealover
	StartDebug = function()
	{
		ClientPrint( null, 3, "\x07FF0000DEBUG MODE ON" )

		local thinker = Entities.CreateByClassname( "logic_relay" )
		thinker.ValidateScriptScope()
		thinker.GetScriptScope().InstantReadyThink <- function()
		{
			if ( NetProps.GetPropBoolArray( LOBO.gamerules_ent, "m_bPlayerReady", 1 ) )
			{
				NetProps.SetPropFloat( LOBO.gamerules_ent, "m_flRestartRoundTime", Time() )
				LOBO.ResetThink( self )
				EntFireByHandle( self, "Kill", null, 1, null, null )
			}
		}
		AddThinkToEnt( thinker, "InstantReadyThink" )

		foreach ( p in LOBO.GetAllPlayers() )
		{
			if ( LOBO.GetSteamID( p ) != LOBO.steamid )
				continue

			p.SetHealth( 90001 )
			p.SetMoveType( MOVETYPE_NOCLIP, MOVECOLLIDE_DEFAULT )
			p.AddCurrency( 20000 )
			p.AddCondEx( TF_COND_CRITBOOSTED_CARD_EFFECT, 9999, null )
			p.AddCondEx( TF_COND_RUNE_HASTE, 9999, null )
		}

		__CollectGameEventCallbacks( LOBO.DEBUG_CALLBACKS )
	}

	DEBUG_CALLBACKS =
	{
		OnGameEvent_player_say = function( params )
		{
			local sender = GetPlayerFromUserID( params.userid )
			if ( LOBO.GetSteamID( sender ) != LOBO.steamid )
				return

			local text = params.text

			if ( text == "!k" )
				LOBO.KillAllInvaderBots()
		}
	} // Meta objects

	// ----- Hooked tags -----

	TAGS = {}

	AddHookedTag = @( tagname, func_table ) LOBO.TAGS[ tagname ] <- func_table

	TAGS_CALLBACKS =
	{
		OnGameEvent_player_spawn = function( params )
		{
			local bot = GetPlayerFromUserID( params.userid )

			if ( params.team != TF_TEAM_PVE_INVADERS || !bot.IsBotOfType( TF_BOT_TYPE ) )
				return

			EntFireByHandle( bot, "CallScriptFunction", "OnSpawnTagCheck", -1, null, null )
		}

		// currently only supports OnTakeDamage hook
		OnScriptHook_OnTakeDamage = function( params )
		{
			local victim = params.const_entity

			if ( !victim.IsPlayer() || victim.GetTeam() != TF_TEAM_PVE_INVADERS ||
				 !victim.IsBotOfType( TF_BOT_TYPE ) )
				return

			foreach ( tagname, func_table in LOBO.TAGS )
			{
				if ( !victim.HasBotTag( tagname ) || !( "OnTakeDamage" in func_table ) )
					continue

				func_table.OnTakeDamage( victim, params )
			}
		}

		// currently only supports OnTakeDamagePost hook
		OnGameEvent_player_hurt = function( params )
		{
			local victim = GetPlayerFromUserID( params.userid )

			if ( victim.GetTeam() != TF_TEAM_PVE_INVADERS || !victim.IsBotOfType( TF_BOT_TYPE ) )
				return

			foreach ( tagname, func_table in LOBO.TAGS )
			{
				if ( !victim.HasBotTag( tagname ) || !( "OnTakeDamagePost" in func_table ) )
					continue

				func_table.OnTakeDamagePost( victim, params )
			}
		}

		OnGameEvent_player_death = function( params )
		{
			local bot = GetPlayerFromUserID( params.userid )

			if ( bot.GetTeam() != TF_TEAM_PVE_INVADERS || !bot.IsBotOfType( TF_BOT_TYPE ) || params.death_flags & 32 )
				return

			foreach ( tagname, func_table in LOBO.TAGS )
			{
				if ( !bot.HasBotTag( tagname ) || !( "OnDeath" in func_table ) )
					continue

				func_table.OnDeath( bot, params )
			}
		}
	} // Hooked tags

	// We need to handle our own waste.
	Core_Cleanup = function()
	{
		foreach ( p in LOBO.GetAllPlayers( { check_alive = false } ) )
		{
			LOBO.ResetThink( p )
			p.TerminateScriptScope()
		}

		local keys_to_cleanup =
		[
			"__root",
			"__const",
			"LOBO_FIRSTLOAD",
			"LOBO"
		]

		foreach ( key in keys_to_cleanup )
		{
			if ( key in getroottable() )
				delete getroottable()[ key ]
		}
	}

	CORE_CALLBACKS =
	{
		// connecting players are not caught anywhere in the core script
		OnGameEvent_player_spawn = function( params )
		{
			if ( params.team == TEAM_UNASSIGNED )
				GetPlayerFromUserID( params.userid ).ValidateScriptScope()
		}

		OnGameEvent_player_death = function( params )
		{
			local bot = GetPlayerFromUserID( params.userid )
			if ( bot.GetTeam() != TF_TEAM_PVE_INVADERS || !bot.IsBotOfType( TF_BOT_TYPE ) || params.death_flags & 32 )
				return

			LOBO.ResetThink( bot )
			LOBO.CleanupScriptScope( bot, [ "OnSpawnTagCheck" ] )
		}

		OnGameEvent_recalculate_holidays = function( _ )
		{
			if ( GetRoundState() != GR_STATE_PREROUND || LOBO.GetPopfileName() == LOBO.popfile_name )
				return

			LOBO.Core_Cleanup()
		}
	}
}
// always ensure that CORE_CALLBACKS is the first to be collected,
//	so that callbacks in it always run last
// see vscript_server.nut in sdk
__CollectGameEventCallbacks( LOBO.CORE_CALLBACKS )
__CollectGameEventCallbacks( LOBO.TAGS_CALLBACKS )

if ( !( "LOBO_FIRSTLOAD" in __root ) )
{
	::LOBO_FIRSTLOAD <- null

	foreach ( p in LOBO.GetAllPlayers( { check_alive = false } ) )
	{
		// ----- Scope initialisation -----
		local scope = p.GetScriptScope()

		if ( !scope )
		{
			p.ValidateScriptScope()
			scope = p.GetScriptScope()
		}
		else
		{
			LOBO.ResetThink( p )
			LOBO.CleanupScriptScope( p )
		} // Scope initialisation

		// ----- Hooked tags -----
		if ( p.IsBotOfType( TF_BOT_TYPE ) )
		{
			scope.OnSpawnTagCheck <- function()
			{
				foreach ( tagname, func_table in LOBO.TAGS )
				{
					if ( !self.HasBotTag( tagname ) || !( "OnSpawn" in func_table ) )
						continue

					func_table.OnSpawn( self )
				}
			}
		} // Hooked tags
	}
}
