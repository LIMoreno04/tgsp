extends SceneTree

## Corre las reglas del Room sin abrir el editor:
##
##     godot --headless --path . --script res://tests/run_tests.gd
##
## Sale con código distinto de cero si algo falla, así que sirve tal cual en un hook o en CI.
##
## Todo va en _process y no en _initialize porque recién en el primer frame la raíz está
## dentro del árbol, y sin eso los _ready de las salas de prueba no corren.

const SUITE := "res://tests/room_rules_test.gd"


func _process(_delta: float) -> bool:
	var host := Node.new()
	host.name = "TestRoot"
	root.add_child(host)

	var suite = load(SUITE).new()
	print("\nroom rules")
	suite.run(host)

	print("\n%d passed, %d failed" % [suite.passed, suite.failed])
	if suite.failed > 0:
		print("\nfailures:")
		for failure: String in suite.failures():
			print("  %s" % failure)

	quit(1 if suite.failed > 0 else 0)
	return true
