/*****************************
*
*	HIVE BUFFS	- XENOMORPH ENDGAME
*	Contains all the class definitons and code for applying hivebuffs to xeno hives.
*	Each buff consists of a /datum/hivebuff
*	And associated on_engage and on_cease procs to handle behaviour of activating and ending the buffs
*	Buffs are divided into 2 tiers, minor and major.
*
*****************************/

///GLOBAL DEFINES///

#define HIVE_STARTING_BUFFPOINTS 10
#define BUFF_POINTS_NAME "Royal resin"

///LOCAL DEFINES///

#define HIVEBUFF_TIER_MINOR "Minor"
#define HIVEBUFF_TIER_MAJOR "Major"


/////////////////////////////

/datum/hivebuff
	/// Timer id to call on_cease() if neccessary to end the effects.
	var/_timer_id
	/// The hive that this buff is applied to.
	var/datum/hive_status/hive
	/// List of pylons sustaining the hive buff, can be one or two pylons
	var/list/sustained_pylons
	///Name of the buff, short and to the point
	var/name = "Hivebuff"
	/// Description of what the buff does.
	var/desc = "Base hivebuff"
	/// Path to .dmi with hivebuff radial icons
	var/hivebuff_radial_dmi = 'icons/ui_icons/hivebuff_radial.dmi'
	/// Image to display on radial menu
	var/radial_icon = "health"
	/// Round time before the buff becomes available to purchase
	var/roundtime_to_enable = 0 HOURS

	/// Flavour message to announce to the hive on buff application. Narrated to all players in the hive.
	var/engage_flavourmessage = "The qween has purchased a buff UwU!"
	/// Flavour message to announce to the hive on buff expiry. Narrated to all players in the hive.
	var/cease_flavourmessage = "Oh noes! =>.<= our buff has expired!!"

	/// Minor or Major buff. Governs announcements made and importance.
	var/tier = HIVEBUFF_TIER_MINOR
	/// Number of pylons required to buy the buff
	var/number_of_required_pylons = 1
	///If this buff can be used with others
	var/is_unique = TRUE
	///If this buff can be used more than once a round.
	var/is_reusable = FALSE
	///Cooldown before the buff can be used again.
	var/cooldown
	/// Time that the buff is active for if it is a timed buff.
	var/duration
	/// Cost of the buff
	var/cost = 1

	/// Message to send to the user and queen if we fail for any reason during on_engage()
	var/engage_failure_message

	/// TRUE when buff has been ended via sustained_pylon Pylon qdeletion
	var/ended_via_qdeletion = FALSE

	/// Flavour message to give to the marines on buff engage
	var/marine_flavourmessage


/datum/hivebuff/New(datum/hive_status/xenohive)
	. = ..()
	if(!xenohive || !istype(xenohive))
		stack_trace("Hivebuff created without correct hive_status passed.")
		return FALSE
	hive = xenohive

	return TRUE

/datum/hivebuff/Destroy(force, ...)
	LAZYREMOVE(hive.active_hivebuffs, name)
	hive = null
	sustained_pylons = null
	. = ..()

/// If the pylon sustaining this hive buff is destroyed for any reason
/datum/hivebuff/proc/on_pylon_deletion(obj/effect/alien/resin/special/pylon/sustained_pylon)
	SIGNAL_HANDLER
	ended_via_qdeletion = TRUE
	if(_timer_id)
		deltimer(_timer_id)
	UnregisterSignal(sustained_pylon, COMSIG_PARENT_QDELETING)
	announce_buff_loss(sustained_pylon)
	sustained_pylons =- src
	// If this is also being sustained by the other pylon(s) clear any references to this
	if(LAZYLEN(sustained_pylons))
		for(var/obj/effect/alien/resin/special/pylon/endgame/pylon in sustained_pylons)
			pylon.sustained_buff = null
	_on_cease()

/datum/hivebuff/proc/announce_buff_loss(obj/effect/alien/resin/special/pylon/sustained_pylon)
	xeno_announcement("Our pylon at [sustained_pylon.loc] has been destroyed!! Our hive buff [name] has waned...", hive.hivenumber, "Hive Buff Wanes!")

///Wrapper for on_engage(), handles checking if the buff can be actually purchased as well as adding buff to the active_hivebuffs and used_hivebuffs for the hive.
/datum/hivebuff/proc/_on_engage(mob/living/carbon/xenomorph/purchasing_mob, obj/effect/alien/resin/special/pylon/endgame/purchased_pylon)
	var/list/pylons_to_use = list()

	if(!roundtime_check())
		to_chat(purchasing_mob, SPAN_XENONOTICE("Our hive is not mature enough yet to purchase this!"))
		return

	if(!check_num_required_pylons(purchased_pylon))
		to_chat(purchasing_mob, SPAN_XENONOTICE("Our hive does not have the required number of available pylons! We require [number_of_required_pylons]"))
		return FALSE
	//Add purchasing pylon to list of pylons to use.
	pylons_to_use += purchased_pylon
	//If we need more pylons then add them to the list to handle setting up the buffs later
	if(number_of_required_pylons > 1)
		for(var/obj/effect/alien/resin/special/pylon/endgame/potential_pylon in hive.active_endgame_pylons)
			// Already in the list, move onto the next pylon
			if(potential_pylon == purchased_pylon)
				continue
			// We have enough pylons already break the loop
			if(length(pylons_to_use) == number_of_required_pylons)
				break
			// Add the pylon to the list
			pylons_to_use += potential_pylon

	if(!check_can_afford_buff())
		to_chat(purchasing_mob, SPAN_XENONOTICE("Our hive cannot afford [name]! [hive.buff_points] / [cost] points."))
		return FALSE

	if(!check_pass_active())
		to_chat(purchasing_mob, SPAN_XENONOTICE("[name] is already active in our hive!"))
		return FALSE

	if(!check_pass_reusable())
		to_chat(purchasing_mob, SPAN_XENONOTICE("Our hive has already used [name] and cannot use it again!"))
		return FALSE

	if(!check_pass_unique())
		var/active_buffs = ""
		for(var/buff in hive.active_hivebuffs)
			active_buffs += buff + " "
		active_buffs = trim_right(active_buffs)
		to_chat(purchasing_mob, SPAN_XENONOTICE("[name] cannot be used with other active buffs! Wait for those to end first. Active buffs: [active_buffs]"))
		return FALSE

	log_admin("[purchasing_mob] of [hive.hivenumber] is attempting to purchase a hive buff: [name].")

	if(!seek_queen_approval(purchasing_mob))
		to_chat(purchasing_mob, SPAN_XENONOTICE("Our queen has not approved the purchase of [name]."))
		return FALSE

	// seek_queen_approval() includes a 20 second timeout so we check that everything still exists that we need.
	if(QDELETED(purchased_pylon) || QDELETED(purchasing_mob) && !purchasing_mob.check_state())
		return FALSE

	// Actually process the buff and apply effects - If the buff succeeds engage_message will return TRUE otherwise it will return a string which will get passed to the purchaser and the queen.
	if(!on_engage())
		if(engage_failure_message && istext(engage_failure_message))
			to_chat(purchasing_mob, SPAN_XENONOTICE(engage_failure_message))
			to_chat(hive.living_xeno_queen, SPAN_XENONOTICE(engage_failure_message))
			return
		else
			stack_trace("[purchasing_mob] attempted to purchase a hive buff: [name] and failed to engage and returned an invalid failure message or no failure message.")
			return

	// All checks have passed.

	// Purchase and deduct funds only after we're sure the buff has engaged
	purchase_and_deduct()
	log_admin("[purchasing_mob] and [hive.living_xeno_queen] of [hive.hivenumber] have purchased a hive buff: [name].")

	// Add to the relevant hive lists.
	LAZYADD(hive.used_hivebuffs, name)
	LAZYADDASSOC(hive.active_hivebuffs, name, src)

	// Register signal to check if the pylon is ever destroyed.

	for(var/obj/effect/alien/resin/special/pylon/endgame/pylon_to_register in pylons_to_use)
		LAZYADD(sustained_pylons, purchased_pylon)
		pylon_to_register.sustained_buff = src
		RegisterSignal(pylon_to_register, COMSIG_PARENT_QDELETING, PROC_REF(on_pylon_deletion))

	// Announce to our hive that we've completed.
	announce_buff_engage()

	// If we need a timer to call _on_cease() we add it here and store the id, used for deleting the timer if we Destroy().
	// If we have no duration to the buff then we call _on_cease() immediately.
	if(duration)
		_timer_id = addtimer(CALLBACK(src, PROC_REF(_on_cease)), duration, TIMER_STOPPABLE)
	else
		_on_cease()
	return TRUE

/// Behaviour for the buff goes in here.
/// IMPORTANT: If you buff has any kind of conditions which can fail. Return a string with details to be passed to the purchaser.
/// If your buff succeeds you must return TRUE
/datum/hivebuff/proc/on_engage()
	return

/// Wrapper for on_cease(), calls qdel(src) after on_cease() behaviour.
/datum/hivebuff/proc/_on_cease()
	announce_buff_cease()
	/// Clear refernces to this buff and unregister signal
	on_cease()
	if(!ended_via_qdeletion)
		for(var/obj/effect/alien/resin/special/pylon/endgame/pylon_to_clear in sustained_pylons)
			pylon_to_clear.sustained_buff = null
			UnregisterSignal(pylon_to_clear, COMSIG_PARENT_QDELETING)
		qdel(src)


/// Checks the number of pylons required and if the hive posesses them
/datum/hivebuff/proc/check_num_required_pylons(obj/effect/alien/resin/special/pylon/endgame/purchased_pylon)
	var/list/viable_pylons = list()
	if(number_of_required_pylons > 1)
		for(var/obj/effect/alien/resin/special/pylon/endgame/potential_pylon in hive.active_endgame_pylons)
			if(potential_pylon == purchased_pylon)
				continue

			// Pylons can only sustain one buff at a time
			if(potential_pylon.sustained_buff)
				continue
			viable_pylons += potential_pylon

		if(length(viable_pylons) >= (number_of_required_pylons - 1))
			return TRUE
		return FALSE
	return TRUE

/datum/hivebuff/proc/roundtime_check()
	if(!(ROUND_TIME > SSticker.round_start_time + roundtime_to_enable))
		return TRUE
	return FALSE

/// Checks if the hive can afford to purchase the buff returns TRUE if they can purchase and FALSE if not.
/datum/hivebuff/proc/check_can_afford_buff()
	if(hive.buff_points < cost)
		return FALSE

	return TRUE

/// Checks if this buff is already active in the hive. Returns TRUE if passed FALSE if not.
/datum/hivebuff/proc/check_pass_active()
	if(LAZYISIN(hive.active_hivebuffs, name))
		return FALSE

	return TRUE

/// Checks if the buff is unique if other buffs are already in use. Return TRUE if passed FALSE if not.
/datum/hivebuff/proc/check_pass_unique()
	if(!is_unique)
		return TRUE

	if(LAZYLEN(hive.active_hivebuffs))
		return FALSE

	return TRUE

/// Checks if the buff is reusable and if it's already been used. Returns TRUE if passed, FALSE if not.
/datum/hivebuff/proc/check_pass_reusable()
	if(is_reusable)
		return TRUE

	if(LAZYISIN(name, hive.used_hivebuffs))
		return FALSE

	return TRUE

/// Deducts points from the hive buff points equal to the cost of the buff
/datum/hivebuff/proc/purchase_and_deduct()

	hive.buff_points -= cost
	return TRUE

/datum/hivebuff/proc/seek_queen_approval(mob/living/purchasing_mob)
	if(!hive.living_xeno_queen)
		return FALSE

	var/mob/living/queen = hive.living_xeno_queen
	var/queen_response = tgui_alert(queen, "[purchasing_mob] is trying to Purchase [name] at a cost of [cost] [BUFF_POINTS_NAME]. Our hive has [hive.buff_points] [BUFF_POINTS_NAME]. Do you want to approve it?", "Approve Hive Buff", list("Yes", "No"), 20 SECONDS)

	if(queen_response && queen_response == "Yes")
		return TRUE
	else
		return FALSE

/// Any effects which need to be ended or ceased gracefully, called when a buff expires.
/datum/hivebuff/proc/on_cease()
	return

/datum/hivebuff/proc/announce_buff_engage()
	if(engage_flavourmessage)
		if(tier > HIVEBUFF_TIER_MINOR)
			xeno_announcement(engage_flavourmessage, hive.hivenumber, "Buff Purchased")
		for(var/mob/xenomorph as anything in hive.totalXenos)
			if(!xenomorph.client)
				continue
			xenomorph.play_screen_text(engage_flavourmessage, override_color = "#740064")
			if(tier <= HIVEBUFF_TIER_MINOR)
				to_chat(xenomorph, SPAN_XENO(engage_flavourmessage))
	if(marine_flavourmessage)
		marine_announcement(marine_flavourmessage, COMMAND_ANNOUNCE, 'sound/AI/bioscan.ogg')

/datum/hivebuff/proc/announce_buff_cease()
	for(var/mob/living/xenomorph as anything in hive.totalXenos)
		if(!xenomorph.client)
			continue
		xenomorph.play_screen_text(cease_flavourmessage, override_color = "#740064")
		to_chat(xenomorph, SPAN_XENO(cease_flavourmessage))



////////////////////////////////
//		BUFFS
////////////////////////////////

/datum/hivebuff/extra_larva
	name = "Surge of Larva"
	desc = "Provides 5 larva instantly to the hive."
	radial_icon = "larba"

	engage_flavourmessage = "The queen has purchased 5 extra larva to join the hive!"

	is_reusable = FALSE

/datum/hivebuff/extra_larva/on_engage()
	hive.stored_larva += 5
	return TRUE

/datum/hivebuff/extra_life
	name = "Boon of Plenty"
	desc = "Increases all xenomorph health by 10% for 10 seconds"
	tier = HIVEBUFF_TIER_MINOR

	engage_flavourmessage = "The queen has imbued us with greater fortitude."
	duration = 30 SECONDS
	number_of_required_pylons = 2


/datum/hivebuff/extra_life/on_engage()
	for(var/mob/living/carbon/xenomorph/xeno as anything in hive.totalXenos)
		xeno.maxHealth *= 1.05
	return TRUE

/datum/hivebuff/extra_life/on_cease()
	for(var/mob/living/carbon/xenomorph/xeno as anything in hive.totalXenos)
		xeno.maxHealth = initial(xeno.caste.max_health)
	return TRUE

/datum/hivebuff/extra_life/major
	name = "Major Boon of Plenty"
	desc = "Increases all xenomorph health by 10% for 10 seconds"
	tier = HIVEBUFF_TIER_MAJOR

	engage_flavourmessage = "The queen has imbued us with greater fortitude."
	duration = 10 MINUTES
	number_of_required_pylons = 2
	radial_icon = "health_m"


/datum/hivebuff/extra_life/major/on_engage()
	for(var/mob/living/carbon/xenomorph/xeno as anything in hive.totalXenos)
		xeno.maxHealth *= 1.1
	return TRUE

/datum/hivebuff/extra_life/major/on_cease()
	for(var/mob/living/carbon/xenomorph/xeno as anything in hive.totalXenos)
		xeno.maxHealth = initial(xeno.caste.max_health)
	return TRUE

/datum/hivebuff/game_ender_caste
	name = "Boon of Destruction"
	desc = "A huge behemoth of a Xenomorph which can tear its way through defences and flesh alike."
	tier = HIVEBUFF_TIER_MAJOR
	is_unique = TRUE
	is_reusable = FALSE

/datum/hivebuff/game_ender_caste/on_engage()

	/// CODE FOR SPAWNING OF THE DESTROYER HERE.
	return

/datum/hivebuff/defence
	name = "Boon of Defence"
	desc = "Increases all xenomorph armour by 5% for 5 minutes"
	tier = HIVEBUFF_TIER_MINOR

	engage_flavourmessage = "The queen has imbued us with greater chitin."
	duration = 5 MINUTES
	number_of_required_pylons = 1
	radial_icon = "shield"

/datum/hivebuff/defence/major
	name = "Major Boon of Defence"
	desc = "Increases all xenomorph armour by 10% for 10 minutes"
	tier = HIVEBUFF_TIER_MAJOR

	engage_flavourmessage = "The queen has imbued us with even greater chitin."
	duration = 10 MINUTES
	number_of_required_pylons = 2
	radial_icon = "shield_m"

/datum/hivebuff/attack
	name = "Boon of Aggression"
	desc = "Increases all xenomorph damage by 5% for 5 minutes"
	tier = HIVEBUFF_TIER_MINOR

	engage_flavourmessage = "The queen has imbued us with slarp claws."
	duration = 5 MINUTES
	number_of_required_pylons = 1
	radial_icon = "slash"

/datum/hivebuff/attack/major
	name = "Major Boon of Aggression"
	desc = "Increases all xenomorph damage by 10% for 10 minutes"
	tier = HIVEBUFF_TIER_MAJOR

	engage_flavourmessage = "The queen has imbued us with razer sharp claws."
	duration = 10 MINUTES
	number_of_required_pylons = 2
	radial_icon = "slash_m"
