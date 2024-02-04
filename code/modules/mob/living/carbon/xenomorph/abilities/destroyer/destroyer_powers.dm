/*
* TO ADD
*
* CAN NOT HARM CHECKS / DEAD CHECKS?
* PLASMA CHECKS
* STATUS CHECKS
* LOGS
* EARLY RETURNS?
* ATTACK VISUALS FOR ALL ABILITIES
* SOUNDS FOR ALL ABILITIES
* LAST DAMAGE DATA = cause_data
*/



/*
	REND ABILITY
	3x3 aoe damage centred on the destroyer. Basic ability, spammable, low damage.
*/

/datum/action/xeno_action/onclick/rend/use_ability()
	var/mob/living/carbon/xenomorph/xeno = owner
	XENO_ACTION_CHECK_USE_PLASMA(xeno)

	xeno.spin_circle()
	xeno.emote("hiss")
	for(var/mob/living/carbon/carbon in orange(1, xeno) - xeno)

		if(carbon.stat == DEAD)
			continue
		if(xeno.can_not_harm(carbon))
			continue
		carbon.apply_armoured_damage(damage)
		xeno.flick_attack_overlay(carbon, "slash")
		to_chat(carbon, SPAN_DANGER("[xeno] slices into you with its razor sharp talons."))
		log_attack("[key_name(xeno)] hit [key_name(carbon)] with [name]")
		playsound(carbon, pick(slash_sounds), 30, TRUE)

	xeno.visible_message(SPAN_DANGER("[xeno] slices around itself!"), SPAN_NOTICE("We slice around ourself!"))
	apply_cooldown()
	..()



/*
	DOOM ABILITY
	Destroyer channels for a while shrieks which turns off all lights in the vicinity and applies a mild daze
	Medium cooldown soft CC
*/

/datum/action/xeno_action/activable/doom/use_ability(atom/target)
	var/mob/living/carbon/xenomorph/xeno = owner
	XENO_ACTION_CHECK_USE_PLASMA(xeno)

	playsound(xeno.loc, 'sound/voice/deep_alien_screech2.ogg', 75, 0, status = 0)
	xeno.visible_message(SPAN_XENOHIGHDANGER("[xeno] emits an raspy guttural roar!"))
	xeno.create_shriekwave(color = COLOR_RED) //Adds the visual effect. Wom wom wom

	// Turn off lights for items in the area dependant on distance.
	for(var/obj/item/device/potential_lightsource in orange(extinguish_light_range, owner))

		var/time_to_extinguish = get_dist(owner, potential_lightsource) SECONDS

		//Flares
		if(istype(potential_lightsource, /obj/item/device/flashlight/flare))
			var/obj/item/device/flashlight/flare/flare = potential_lightsource
			addtimer(CALLBACK(flare, TYPE_PROC_REF(/obj/item/device/flashlight/flare/, burn_out)), time_to_extinguish)

		//Flashlights
		if(istype(potential_lightsource, /obj/item/device/flashlight))
			var/obj/item/device/flashlight/flashlight = potential_lightsource
			addtimer(CALLBACK(flashlight, TYPE_PROC_REF(/obj/item/device/flashlight, turn_off_light)), time_to_extinguish)

		//Armour lights
		if(istype(potential_lightsource, /obj/item/clothing/suit/storage/marine))
			var/obj/item/clothing/suit/storage/marine/marinearmour = potential_lightsource
			addtimer(CALLBACK(marinearmour, TYPE_PROC_REF(/atom, turn_light), null, FALSE), time_to_extinguish)

	// "Confuse" and slow humans in the area and turn off their armour lights.
	for(var/mob/living/carbon/human/human in orange(extinguish_light_range, owner))
		human.EyeBlur(daze_length_seconds)
		human.Daze(daze_length_seconds)
		human.Superslow(slow_length_seconds)
		to_chat(human, SPAN_HIGHDANGER("[xeno]'s roar overwhelms your entire being!"))
		shake_camera(human, 6, 1)

		var/time_to_extinguish = get_dist(owner, human) SECONDS
		var/obj/item/clothing/suit/suit = human.get_item_by_slot(WEAR_JACKET)
		if(istype(suit, /obj/item/clothing/suit/storage/marine))
			var/obj/item/clothing/suit/storage/marine/armour = suit
			addtimer(CALLBACK(armour, TYPE_PROC_REF(/atom, turn_light), null, FALSE), time_to_extinguish)

	apply_cooldown()
	..()

/*
	BULWARK ABILITY - AoE shield
	Long cooldown defensive ability, provides a shield which caps damage taken to 10% of the xeno's max health per individual source of damage.
*/

/datum/action/xeno_action/onclick/destroyer_shield/use_ability()
	var/mob/living/carbon/xenomorph/xeno = owner

	XENO_ACTION_CHECK_USE_PLASMA(xeno)


	playsound(xeno.loc, 'sound/voice/deep_alien_screech.ogg', 50, 0, status = 0)
	// Add our shield
	start_shield(xeno)

	// Add other xeno's shields in AoE range
	for(var/mob/living/carbon/xenomorph/xeno_in_aoe in range(area_of_effect, xeno))
		if(xeno_in_aoe.stat == DEAD)
			continue
		if(xeno_in_aoe.hivenumber != xeno.hivenumber)
			continue
		start_shield(xeno_in_aoe)
		xeno.beam(xeno_in_aoe, "purple_lightning", time = 4 SECONDS)

	apply_cooldown()
	return ..()

/*
	DESTROY ABILITY
	Destroyer leaps into the air and crashes down damaging cades and mobs in a 3x3 area centred on him.
	Long cooldown high damage ability, massive damage against cades, highly telegraphed.
*/

/datum/action/xeno_action/onclick/destroyer_shield/proc/start_shield(mob/living/carbon/xenomorph/xeno)
	var/datum/xeno_shield/shield = xeno.add_xeno_shield(600, XENO_SHIELD_SOURCE_DESTROYER_LEGIONSPELL, /datum/xeno_shield/destroyer_shield)
	xeno.create_shield(shield.duration, "purple_animated_shield_full")

#define LEAP_HEIGHT 210 //how high up leaps go, in pixels
#define LEAP_DIRECTION_CHANGE_RANGE 5 //the range our x has to be within to not change the direction we slam from

/datum/action/xeno_action/activable/destroy/use_ability(atom/target)
	// TODO: Make sure we're not targetting a space tile or a wall etc!!!

	var/mob/living/carbon/xenomorph/xeno = owner
	XENO_ACTION_CHECK(xeno)

	if(get_dist(owner, target) > range)
		to_chat(xeno, SPAN_XENONOTICE("We cannot leap that far!"))
		return

	var/turf/target_turf = get_turf(target)

	if(istype(target_turf, /turf/closed))
		to_chat(xeno, SPAN_XENONOTICE("We cannot jump into that area!"))
		return

	if(istype(target_turf, /turf/open/space))
		to_chat(xeno, SPAN_XENONOTICE("It would not be wise to try to leap there..."))
		return

	var/list/leap_line = getline2(xeno, target)
	for(var/turf/jump_turf in leap_line)
		if(istype(jump_turf, /turf/closed))
			to_chat(xeno, SPAN_XENONOTICE("We don't have a clear path to leap to that location!"))
			return

	if(!check_and_use_plasma_owner())
	var/turf/template_turf = get_step(target_turf, SOUTHWEST)

	to_chat(xeno, SPAN_XENONOTICE("Our muscles tense as we prepare ourself for a giant leap."))
	xeno.make_jittery(2 SECONDS)
	if(!do_after(xeno, 2 SECONDS, INTERRUPT_ALL, BUSY_ICON_HOSTILE))
		to_chat(xeno, SPAN_XENONOTICE("We relax our muslces and end our leap."))
		return
	if(leaping || !target)
		return
	// stop target movement
	leaping = TRUE
	ADD_TRAIT(owner, TRAIT_UNDENSE, "Destroy")
	ADD_TRAIT(owner, TRAIT_IMMOBILIZED, "Destroy")
	owner.visible_message(SPAN_WARNING("[owner] takes a giant leap into the air!"))

	var/negative
	var/initial_x = owner.x
	if(target.x < initial_x) //if the target's x is lower than ours, go to the left
		negative = TRUE
	else if(target.x > initial_x)
		negative = FALSE
	else if(target.x == initial_x) //if their x is the same, pick a direction
		negative = prob(50)

	owner.face_atom(target)
	owner.emote("roar")

	//Initial visual
	var/obj/effect/temp_visual/destroyer_leap/leap_visual = new(owner.loc, negative, owner.dir)
	new /obj/effect/xenomorph/xeno_telegraph/destroyer_attack_template(template_turf, 20)

	negative = !negative //invert it for the descent later

	var/oldtransform = owner.transform
	owner.alpha = 255
	animate(owner, alpha = 0, transform = matrix()*0.9, time = 3, easing = BOUNCE_EASING)
	for(var/i in 1 to 3)
		sleep(0.1 SECONDS)
		if(QDELETED(owner) || owner.stat == DEAD) //we got hit and died, rip us

			//Initial effect
			qdel(leap_visual)

			if(owner.stat == DEAD)
				leaping = FALSE
				animate(owner, alpha = 255, transform = oldtransform, time = 0, flags = ANIMATION_END_NOW) //reset immediately
			return
	owner.status_flags |= GODMODE

	owner.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	SLEEP_CHECK_DEATH(7, owner)

	while(target && owner.loc != get_turf(target))
		owner.forceMove(get_step(owner, get_dir(owner, target)))
		SLEEP_CHECK_DEATH(0.5, owner)

	animate(owner, alpha = 100, transform = matrix()*0.7, time = 7)
	var/descentTime = 5

	if(negative)
		if(ISINRANGE(owner.x, initial_x + 1, initial_x + LEAP_DIRECTION_CHANGE_RANGE))
			negative = FALSE
	else
		if(ISINRANGE(owner.x, initial_x - LEAP_DIRECTION_CHANGE_RANGE, initial_x - 1))
			negative = TRUE

	//Visuals
	new /obj/effect/temp_visual/destroyer_leap/end(owner.loc, negative, owner.dir)


	SLEEP_CHECK_DEATH(descentTime, owner)
	animate(owner, alpha = 255, transform = oldtransform, descentTime)
	owner.mouse_opacity = initial(owner.mouse_opacity)
	//Sounds
	playsound(owner.loc, 'sound/effects/meteorimpact.ogg', 200, TRUE)

	/// BIRDTALON: MAKE THIS A FOR?
	new /obj/effect/temp_visual/heavy_impact(owner.loc)
	new /obj/effect/temp_visual/heavy_impact(get_step(owner.loc, NORTH))
	new /obj/effect/temp_visual/heavy_impact(get_step(owner.loc, EAST))
	new /obj/effect/temp_visual/heavy_impact(get_step(owner.loc, WEST))
	new /obj/effect/temp_visual/heavy_impact(get_step(owner.loc, SOUTH))
	new /obj/effect/temp_visual/heavy_impact(get_step(owner.loc, SOUTHEAST))
	new /obj/effect/temp_visual/heavy_impact(get_step(owner.loc, SOUTHWEST))
	new /obj/effect/temp_visual/heavy_impact(get_step(owner.loc, NORTHWEST))
	new /obj/effect/temp_visual/heavy_impact(get_step(owner.loc, NORTHEAST))

	/// Actual Damaging Effects - Add stuff for cades - NEED TELEGRAPHS NEED EFFECTS

	for(var/mob/living/carbon/carbon in orange(1, owner) - owner)
		carbon.adjustBruteLoss(75)
		if(!QDELETED(carbon)) // Some mobs are deleted on death
			var/throw_dir = get_dir(owner, carbon)
			if(carbon.loc == owner.loc)
				throw_dir = pick(GLOB.alldirs)
			var/throwtarget = get_edge_target_turf(owner, throw_dir)
			carbon.throw_atom(throwtarget, 2, SPEED_REALLY_FAST, owner, TRUE)
			carbon.KnockDown(0.5)
			xeno.visible_message(SPAN_WARNING("[carbon] is thrown clear of [owner]!"))

	for(var/obj/item/item in orange(1, owner))
		if(!QDELETED(item))
			var/throw_dir = get_dir(owner, item)
			if(item.loc == owner.loc)
				throw_dir = pick(GLOB.alldirs)
			var/throwtarget = get_edge_target_turf(owner, throw_dir)
			item.throw_atom(throwtarget, 2, SPEED_REALLY_FAST, owner, TRUE)

	/// DAMAGING CADES HERE

	for(var/obj/structure/barricade/cade in orange(2, owner))
		cade.add_filter("cluster_stacks", 2, list("type" = "outline", "color" = COLOR_RED, "size" = 1))
		cade.take_damage(250)

	for(var/mob/living in range(7, owner))
		shake_camera(living, 15, 1)

	REMOVE_TRAIT(owner, TRAIT_UNDENSE, "Destroy")
	REMOVE_TRAIT(owner, TRAIT_IMMOBILIZED, "Destroy")

	SLEEP_CHECK_DEATH(1, owner)
	leaping = FALSE
	owner.status_flags &= ~GODMODE
	apply_cooldown()
	..()

/datum/action/xeno_action/activable/destroy/proc/second_template(turf/template_turf)
	new /obj/effect/xenomorph/xeno_telegraph/destroyer_attack_template(template_turf, 10)

/obj/effect/temp_visual/destroyer_leap
	icon = 'icons/mob/xenos/destroyer.dmi'
	icon_state = "Normal Destroyer Charging"
	layer = 4.7
	plane = -4
	pixel_x = -32
	duration = 10
	randomdir = FALSE

/obj/effect/temp_visual/destroyer_leap/Initialize(mapload, negative, dir)
	. = ..()
	setDir(dir)
	INVOKE_ASYNC(src, PROC_REF(flight), negative)

/obj/effect/temp_visual/destroyer_leap/proc/flight(negative)
	if(negative)
		animate(src, pixel_x = -LEAP_HEIGHT*0.1, pixel_z = LEAP_HEIGHT*0.15, time = 3, easing = BOUNCE_EASING)
	else
		animate(src, pixel_x = LEAP_HEIGHT*0.1, pixel_z = LEAP_HEIGHT*0.15, time = 3, easing = BOUNCE_EASING)
	sleep(0.3 SECONDS)
	icon_state = "Normal Destroyer Charging"
	if(negative)
		animate(src, pixel_x = -LEAP_HEIGHT, pixel_z = LEAP_HEIGHT, time = 7)
	else
		animate(src, pixel_x = LEAP_HEIGHT, pixel_z = LEAP_HEIGHT, time = 7)

/obj/effect/temp_visual/destroyer_leap/end
	pixel_x = LEAP_HEIGHT
	pixel_z = LEAP_HEIGHT
	duration = 10

/obj/effect/temp_visual/destroyer_leap/end/flight(negative)
	if(negative)
		pixel_x = -LEAP_HEIGHT
		animate(src, pixel_x = -16, pixel_z = 0, time = 5)
	else
		animate(src, pixel_x = -16, pixel_z = 0, time = 5)

/obj/effect/xenomorph/xeno_telegraph/destroyer_attack_template
	icon = 'icons/effects/96x96.dmi'
	icon_state = "xenolandingpink"
	layer = BELOW_MOB_LAYER

/obj/effect/xenomorph/xeno_telegraph/destroyer_attack_template/yellow
	icon_state = "xenolandingyellow"
