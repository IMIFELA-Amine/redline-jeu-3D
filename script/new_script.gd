@tool
extends EditorScript

func _run():
	var library = load("res://animation/CLIMB/Climbing.fbx")
	var anim = library.get_animation("mixamo_com").duplicate(true)
	for track in anim.get_track_count():
		if anim.track_get_type(track) == Animation.TYPE_POSITION_3D and str(anim.track_get_path(track)).ends_with("Hips"):
			var start = anim.track_get_key_value(track, 0)
			for key in anim.track_get_key_count(track):
				anim.track_set_key_value(track, key, Vector3(0, start.y, 0))
	var new_library = AnimationLibrary.new()
	new_library.add_animation("mixamo_com", anim)
	ResourceSaver.save(new_library, "res://animation/CLIMB/Climb.res")
	EditorInterface.get_resource_filesystem().scan()
	print("Escalade corrigée : Climb.res créé !")
