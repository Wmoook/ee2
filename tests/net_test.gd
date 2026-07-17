extends Node
## Boots the persistent net-test driver onto the tree root so it survives
## the scene change that NetPlay._launch_mode performs on match start.

func _ready() -> void:
	var driver: Node = Node.new()
	driver.name = "NetTestDriver"
	driver.set_script(preload("res://tests/net_test_driver.gd"))
	get_tree().root.add_child.call_deferred(driver)
